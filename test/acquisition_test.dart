import 'dart:async';
import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';

import 'support/tables.dart';

Matcher code(String code) =>
    isA<OrmException>().having((e) => e.code, 'code', code);

void main() {
  test(
    'an expired lease cannot enter before a delayed Timer gets its turn',
    () async {
      final driver = _GatedDriver(
        await SqliteDriver.open(const SqliteOptions.memory()),
      );
      final db = Database(driver);
      var calls = 0;
      try {
        final result = db.session(
          (s) async {
            calls++;
          },
          acquire: const AcquisitionOptions(
            timeout: Duration(milliseconds: 10),
          ),
        );
        final failure = expectLater(
          result,
          throwsA(code('CONNECTION.TIMEOUT')),
        );
        final busy = Stopwatch()..start();
        while (busy.elapsed < const Duration(milliseconds: 30)) {
          // Deliberately starve the timer; the ready lease resumes in a microtask.
        }
        driver.ready.complete();
        await failure;
        await db.close();
        expect(calls, 0);
      } finally {
        if (!driver.ready.isCompleted) driver.ready.complete();
        await db.close();
      }
    },
  );
  runTests(
    'sqlite',
    (observe) => sqlite(const SqliteOptions.memory(), onQuery: observe),
  );
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    test('PostgreSQL native pool timeout is classified before entering the callback', () async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          maxConnections: 1,
          poolTimeout: const Duration(milliseconds: 50),
        ),
      );
      final entered = Completer<void>(), release = Completer<void>();
      var calls = 0;
      final owner = db.session((session) async {
        entered.complete();
        await release.future;
      });
      try {
        await entered.future;
        await expectLater(
          db.session((s) async {
            calls++;
          }),
          throwsA(code('CONNECTION.TIMEOUT')),
        );
        release.complete();
        await owner;
        await db.execute(SqlCommand('SELECT 1'));
        expect(calls, 0);
        await expectLater(
          db.session((s) async => throw TimeoutException('user callback')),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await owner;
        await db.close();
      }
    }, tags: 'postgres');
    test(
      'PostgreSQL connection establishment timeout does not cap pool waiting',
      () async {
        final db = postgres(
          PostgresOptions(
            url: Uri.parse(url),
            tls: .disable,
            maxConnections: 1,
            connectTimeout: const Duration(milliseconds: 200),
            poolTimeout: const Duration(seconds: 2),
          ),
        );
        final entered = Completer<void>(), release = Completer<void>();
        final owner = db.session((session) async {
          await session.execute(SqlCommand('SELECT 1'));
          entered.complete();
          await release.future;
        });
        try {
          await entered.future.timeout(const Duration(seconds: 3));
          final check = expectLater(
            db.execute(SqlCommand('SELECT 2')),
            completion(
              isA<SqlResult>().having((r) => r.rows, 'rows', [
                [2],
              ]),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 350));
          release.complete();
          await owner;
          await check;
        } finally {
          if (!release.isCompleted) release.complete();
          await owner;
          await db.close();
        }
      },
      tags: 'postgres',
    );
    runTests('postgres', (observe) async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          schema: 'orm_acquire_tests',
          maxConnections: 1,
        ),
        onQuery: observe,
      );
      await db.execute(
        SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_acquire_tests'),
      );
      return db;
    });
    test('PostgreSQL timeout during real connection initialization releases the late lease', () async {
      final uri = Uri.parse(url),
          colon = uri.userInfo.indexOf(':'),
          opening = Completer<void>(),
          ready = Completer<void>();
      var opens = 0, calls = 0;
      final pool = pg.Pool<void>.withEndpoints(
        [
          pg.Endpoint(
            host: uri.host,
            port: uri.hasPort ? uri.port : 5432,
            database: uri.pathSegments.single,
            username: uri.userInfo.isEmpty
                ? null
                : Uri.decodeComponent(
                    colon < 0 ? uri.userInfo : uri.userInfo.substring(0, colon),
                  ),
            password: colon < 0
                ? null
                : Uri.decodeComponent(uri.userInfo.substring(colon + 1)),
          ),
        ],
        settings: pg.PoolSettings(
          maxConnectionCount: 1,
          sslMode: pg.SslMode.disable,
          onOpen: (connection) async {
            opens++;
            opening.complete();
            await ready.future;
          },
        ),
      );
      final db = Database(PostgresDriver.borrow(pool));
      try {
        final result = db.session(
          (session) async {
            calls++;
          },
          acquire: const AcquisitionOptions(
            timeout: Duration(milliseconds: 100),
          ),
        );
        final failure = expectLater(
          result,
          throwsA(code('CONNECTION.TIMEOUT')),
        );
        await opening.future.timeout(const Duration(seconds: 3));
        await failure.timeout(const Duration(seconds: 3));
        expect(calls, 0);
        ready.complete();
        expect((await db.execute(SqlCommand('SELECT 1'))).rows, [
          [1],
        ]);
        expect(
          opens,
          1,
          reason: 'An abandoned request must release, not discard, its late connection.',
        );
        expect(calls, 0);
      } finally {
        if (!ready.isCompleted) ready.complete();
        await db.close();
        await pool.close();
      }
    }, tags: 'postgres');
  }
}

void runTests(
  String name,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open,
) {
  group('acquisition $name', () {
    late Database<Backend> db;
    final events = <QueryEvent>[];
    Future<void>? held;
    Completer<void>? release;
    Future<void> hold() async {
      final entered = Completer<void>();
      release = Completer<void>();
      held = db.session((session) async {
        entered.complete();
        await release!.future;
      });
      await entered.future;
      events.clear();
    }

    Future<void> free() async {
      if (release != null && !release!.isCompleted) release!.complete();
      await held;
      held = null;
    }

    setUp(() async {
      db = await open(events.add);
      await db.execute(SqlCommand('DROP TABLE IF EXISTS users'));
      await createTables(db);
      events.clear();
    });
    tearDown(() async {
      await free();
      await db.close();
    });

    test(
      'expired raw writes never execute after a late lease becomes available',
      () async {
        await hold();
        await expectLater(
          db.execute(
            SqlCommand("INSERT INTO users(email) VALUES ('late')"),
            options: const ExecutionOptions(
              acquireTimeout: Duration(milliseconds: 40),
            ),
          ),
          throwsA(code('CONNECTION.TIMEOUT')),
        ).timeout(const Duration(seconds: 2));
        expect(events, isEmpty);
        await free();
        expect(await db.table(users).count(), 0);
        expect(events.any((e) => e.sql.contains("'late'")), false);
      },
    );

    test(
      'query cancellation returns while the pool is still occupied',
      () async {
        await hold();
        final token = CancellationToken();
        final result = db
            .table(users)
            .get(options: ExecutionOptions(cancellation: token));
        final failure = expectLater(
          result,
          throwsA(code('OPERATION.CANCELLED')),
        );
        token.cancel();
        await failure.timeout(const Duration(seconds: 2));
        expect(release!.isCompleted, false);
        expect(events, isEmpty);
        await free();
        expect(await db.table(users).count(), 0);
        expect(events.length, 1);
      },
    );

    test(
      'typed mutations and batch transactions propagate acquisition limits',
      () async {
        await hold();
        const options = ExecutionOptions(
          acquireTimeout: Duration(milliseconds: 30),
        );
        await expectLater(
          db
              .table(users)
              .insert((u) => [u.email.set('mutation')])
              .execute(options: options),
          throwsA(code('CONNECTION.TIMEOUT')),
        );
        await expectLater(
          db
              .table(users)
              .insertMany(['a', 'b'], (u, email) => [u.email.set(email)])
              .execute(options: options),
          throwsA(code('CONNECTION.TIMEOUT')),
        );
        final token = CancellationToken();
        final cancelled = db
            .table(users)
            .insertMany(['c'], (u, email) => [u.email.set(email)])
            .execute(options: ExecutionOptions(cancellation: token));
        final failure = expectLater(
          cancelled,
          throwsA(code('OPERATION.CANCELLED')),
        );
        token.cancel();
        await failure.timeout(const Duration(seconds: 2));
        expect(events, isEmpty);
        await free();
        expect(await db.table(users).count(), 0);
      },
    );

    test(
      'expired transactions and sessions never enter their callbacks',
      () async {
        await hold();
        var calls = 0;
        const acquire = AcquisitionOptions(timeout: Duration(milliseconds: 30));
        await expectLater(
          db.transaction((tx) async {
            calls++;
          }, acquire: acquire),
          throwsA(code('CONNECTION.TIMEOUT')),
        );
        final token = CancellationToken();
        final session = db.session((s) async {
          calls++;
        }, acquire: AcquisitionOptions(cancellation: token));
        final failure = expectLater(
          session,
          throwsA(code('OPERATION.CANCELLED')),
        );
        token.cancel();
        await failure.timeout(const Duration(seconds: 2));
        await free();
        await db.execute(SqlCommand('SELECT 1'));
        expect(calls, 0);
        expect(events.length, 1);
      },
    );

    test('acquisition timeout stops on entry and statement timeout starts afterward', () async {
      await hold();
      if (!db.capabilities.statementTimeout) {
        expect(
          () => db.execute(
            SqlCommand('SELECT 99'),
            options: const ExecutionOptions(
              acquireTimeout: Duration(seconds: 2),
              timeout: Duration(milliseconds: 100),
            ),
          ),
          throwsA(code('CAPABILITY.CANCEL')),
        );
        expect(events, isEmpty);
      }
      final result = db.execute(
        SqlCommand('SELECT 1'),
        options: ExecutionOptions(
          acquireTimeout: const Duration(seconds: 2),
          timeout: db.capabilities.statementTimeout
              ? const Duration(milliseconds: 100)
              : null,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await free();
      expect((await result).rows, [
        [1],
      ]);
      final token = CancellationToken();
      await db.session(
        (s) async {
          token.cancel();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect((await s.execute(SqlCommand('SELECT 2'))).rows, [
            [2],
          ]);
        },
        acquire: AcquisitionOptions(
          timeout: const Duration(milliseconds: 30),
          cancellation: token,
        ),
      );
    });

    test(
      'invalid and already-cancelled acquisition options never queue work',
      () async {
        var called = false;
        expect(
          () => db.session((s) async {
            called = true;
          }, acquire: const AcquisitionOptions(timeout: Duration.zero)),
          throwsArgumentError,
        );
        final token = CancellationToken()..cancel();
        expect(
          () => db.session((s) async {
            called = true;
          }, acquire: AcquisitionOptions(cancellation: token)),
          throwsA(code('OPERATION.CANCELLED')),
        );
        expect(
          () => db
              .table(users)
              .get(
                options: const ExecutionOptions(acquireTimeout: Duration.zero),
              ),
          throwsArgumentError,
        );
        expect(called, false);
        expect(events, isEmpty);
      },
    );

    test(
      'stream cancellation and timeout return without opening a cursor',
      () async {
        await hold();
        final stream = db
            .table(users)
            .stream(
              options: const ExecutionOptions(
                acquireTimeout: Duration(milliseconds: 40),
              ),
            );
        await expectLater(
          stream.toList(),
          throwsA(code('CONNECTION.TIMEOUT')),
        ).timeout(const Duration(seconds: 2));
        final errors = <Object>[];
        final subscription = db
            .table(users)
            .stream()
            .listen((_) {}, onError: errors.add);
        await subscription.cancel().timeout(const Duration(seconds: 2));
        expect(errors, isEmpty);
        expect(events, isEmpty);
        await free();
        expect(await db.table(users).count(), 0);
        expect(events.length, 1);
      },
    );

    test(
      'query watch acquisition failure can recover on a later invalidation',
      () async {
        await hold();
        final failed = Completer<void>(), rows = Completer<List<String>>();
        final subscription = db
            .table(users)
            .select((u) => u.email)
            .watch(
              options: const ExecutionOptions(
                acquireTimeout: Duration(milliseconds: 40),
              ),
            )
            .listen(
              rows.complete,
              onError: (Object error) {
                expect(error, code('CONNECTION.TIMEOUT'));
                failed.complete();
              },
            );
        try {
          await failed.future.timeout(const Duration(seconds: 2));
          expect(events, isEmpty);
          await free();
          db.invalidate([usersSchema]);
          expect(
            await rows.future.timeout(const Duration(seconds: 2)),
            isEmpty,
          );
        } finally {
          await subscription.cancel();
        }
      },
    );

    test(
      'close drains abandoned reservations without running their callbacks',
      () async {
        await hold();
        await expectLater(
          db.execute(
            SqlCommand('SELECT 99'),
            options: const ExecutionOptions(
              acquireTimeout: Duration(milliseconds: 30),
            ),
          ),
          throwsA(code('CONNECTION.TIMEOUT')),
        );
        var closed = false;
        final closing = db.close().then((_) => closed = true);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(closed, false);
        await free();
        await closing.timeout(const Duration(seconds: 2));
        expect(events, isEmpty);
      },
    );

    test(
      'abandoned requests preserve pool reuse and subsequent action errors',
      () async {
        final pid = name == 'postgres'
            ? (await db.execute(SqlCommand('SELECT pg_backend_pid()')))
                  .rows
                  .single
                  .single
            : null;
        await hold();
        for (var i = 0; i < 3; i++) {
          await expectLater(
            db.execute(
              SqlCommand('SELECT 99'),
              options: const ExecutionOptions(
                acquireTimeout: Duration(milliseconds: 20),
              ),
            ),
            throwsA(code('CONNECTION.TIMEOUT')),
          );
        }
        await free();
        if (pid != null) {
          expect(
            (await db.execute(SqlCommand('SELECT pg_backend_pid()')))
                .rows
                .single
                .single,
            pid,
          );
        }
        await expectLater(
          db.session(
            (s) async => throw StateError('action'),
            acquire: const AcquisitionOptions(timeout: Duration(seconds: 1)),
          ),
          throwsStateError,
        );
        expect((await db.execute(SqlCommand('SELECT 1'))).rows, [
          [1],
        ]);
      },
    );
  }, tags: name);
}

final class _GatedDriver(final Driver<Backend> source)
    implements Driver<Backend> {
  final ready = Completer<void>();
  @override
  Capabilities get capabilities => source.capabilities;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      ready.future.then((_) => source.run(action));
  @override
  Future<void> close() => source.close();
}
