@Tags(['database'])
library;

import 'dart:async';
import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';

import 'support/tables.dart';

Matcher code(String value) =>
    isA<OrmException>().having((e) => e.code, 'code', value);

pg.Endpoint endpointFor(String url) {
  final uri = Uri.parse(url), colon = Uri.parse(url).userInfo.indexOf(':');
  return pg.Endpoint(
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
  );
}

void main() {
  runTests(
    'sqlite',
    (observe) => sqlite(const SqliteOptions.memory(), onQuery: observe),
  );
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    runTests('postgres', (observe) async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: PostgresTls.disable,
          schema: 'orm_stream_tests',
          maxConnections: 1,
        ),
        onQuery: observe,
      );
      await db.execute(
        SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_stream_tests'),
      );
      return db;
    });
    test(
      'late PostgreSQL cancellation cannot reach the next statement',
      () async {
        final endpoint = endpointFor(url);
        final pool = pg.Pool<void>.withEndpoints(
          [endpoint],
          settings: pg.PoolSettings(
            sslMode: pg.SslMode.disable,
            maxConnectionCount: 1,
          ),
        );
        var controls = 0;
        final db = Database(
          PostgresDriver.borrow(
            pool,
            cancellationConnection: () async {
              controls++;
              await Future<void>.delayed(const Duration(milliseconds: 150));
              return pg.Connection.open(
                endpoint,
                settings: const pg.ConnectionSettings(
                  sslMode: pg.SslMode.disable,
                ),
              );
            },
          ),
        );
        try {
          // SQL finishes while the deliberately delayed cancellation connects.
          await db.execute(
            SqlCommand('SELECT pg_sleep(0.08)'),
            options: const ExecutionOptions(
              timeout: Duration(milliseconds: 20),
            ),
          );
          expect(controls, 1);
          await db.execute(SqlCommand('SELECT pg_sleep(0.2)'));
          expect(controls, 1);
        } finally {
          await db.close();
          await pool.close();
        }
      },
      tags: 'postgres',
    );
    test(
      'borrowed pool requires cancellation support and retains ownership',
      () async {
        final pool = pg.Pool<void>.withEndpoints(
          [endpointFor(url)],
          settings: pg.PoolSettings(
            sslMode: pg.SslMode.disable,
            maxConnectionCount: 1,
          ),
        );
        final db = Database(PostgresDriver.borrow(pool));
        try {
          expect(db.capabilities.cancellation, isFalse);
          expect(
            () => db.execute(
              SqlCommand('SELECT 1'),
              options: const ExecutionOptions(timeout: Duration(seconds: 1)),
            ),
            throwsA(code('CAPABILITY.CANCEL')),
          );
          await db.close();
          expect((await pool.execute('SELECT 7')).single.single, 7);
        } finally {
          await db.close();
          await pool.close();
        }
      },
      tags: 'postgres',
    );
    test(
      'failed cancellation control discards the physical connection',
      () async {
        final pool = pg.Pool<void>.withEndpoints(
          [endpointFor(url)],
          settings: pg.PoolSettings(
            sslMode: pg.SslMode.disable,
            maxConnectionCount: 1,
          ),
        );
        final db = Database(
          PostgresDriver.borrow(
            pool,
            cancellationConnection: () async =>
                throw StateError('control unavailable'),
          ),
        );
        try {
          final before = (await db.execute(
            SqlCommand('SELECT pg_backend_pid()'),
          )).rows.single.single;
          await expectLater(
            db.execute(
              SqlCommand('SELECT pg_sleep(10)'),
              options: const ExecutionOptions(
                timeout: Duration(milliseconds: 30),
              ),
            ),
            throwsStateError,
          );
          final after = (await db.execute(
            SqlCommand('SELECT pg_backend_pid()'),
          )).rows.single.single;
          expect(after, isNot(before));
        } finally {
          await db.close();
          await pool.close();
        }
      },
      tags: 'postgres',
    );
  }
}

void runTests(
  String name,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open,
) {
  group(name, () {
    late Database<Backend> db;
    final events = <QueryEvent>[];
    void Function(QueryEvent)? hook;
    setUp(() async {
      hook = null;
      db = await open((event) {
        events.add(event);
        hook?.call(event);
      });
      await db.execute(SqlCommand('DROP TABLE IF EXISTS posts'));
      await db.execute(SqlCommand('DROP TABLE IF EXISTS users'));
      await createTables(db);
      await db.execute(
        SqlCommand('''
        WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<31)
        INSERT INTO users(id,email,score) SELECT x,'user'||x,x FROM n
      '''),
      );
      events.clear();
    });
    tearDown(() => db.close());
    Query<int, UserFields> ids(Database<Backend> db) =>
        db.table(users).orderBy((u) => [u.id.asc()]).select((u) => u.id);
    Iterable<QueryEvent> getFetches() =>
        events.where((e) => e.operation == QueryOperation.cursorFetch);
    void cancellationTest(String description, Future<void> Function() body) {
      test(description, () async {
        if (!db.capabilities.cancellation) {
          markTestSkipped(
            'This SQLite build does not export sqlite3_interrupt.',
          );
          return;
        }
        await body();
      });
    }

    final slow = name == 'postgres'
        ? 'SELECT pg_sleep(10)'
        : '''WITH RECURSIVE n(x) AS (
          SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1000000000
        ) SELECT sum(x) FROM n''';
    final slowValue = sql<int>(
      [name == 'postgres' ? '(SELECT 1 FROM pg_sleep(10))' : '($slow)'],
      const [],
      Codecs.integer,
    );

    cancellationTest(
      'cancellation between batch chunks prevents a partial commit',
      () async {
        final token = CancellationToken();
        hook = (event) {
          if (event.sql.startsWith('INSERT') && event.error == null) {
            token.cancel();
          }
        };
        await expectLater(
          db.transaction((tx) async {
            await expectLater(
              tx
                  .table(users)
                  .insertMany(
                    [40, 41, 42],
                    (u, i) => [
                      u.id.set(i),
                      u.email.set('new$i'),
                      if (i == 41) u.nickname.set('second'),
                    ],
                  )
                  .execute(options: ExecutionOptions(cancellation: token)),
              throwsA(code('OPERATION.CANCELLED')),
            );
          }),
          throwsA(code('TRANSACTION.FAILED')),
        );
        expect(await db.table(users).count(), 31);
      },
    );

    cancellationTest(
      'cancellation interrupts an active cursor fetch',
      () async {
        final token = CancellationToken();
        final timer = Timer(const Duration(milliseconds: 50), token.cancel);
        try {
          await expectLater(
            db
                .table(users)
                .select((_) => slowValue)
                .take(1)
                .stream(
                  batchSize: 1,
                  options: ExecutionOptions(cancellation: token),
                )
                .toList(),
            throwsA(code('OPERATION.CANCELLED')),
          );
        } finally {
          timer.cancel();
        }
        expect(getFetches().single.error, isNotNull);
        expect(await db.table(users).count(), 31);
      },
    );

    cancellationTest('timed-out mutations return no partial write', () async {
      await expectLater(
        db
            .table(users)
            .where((u) => u.id.eq(.value(1)))
            .update((u) => [u.score.setExpression(slowValue)])
            .returning((u) => u.score)
            .single(
              options: const ExecutionOptions(
                timeout: Duration(milliseconds: 40),
              ),
            ),
        throwsA(code('OPERATION.TIMEOUT')),
      );
      expect(
        (await db.table(users).where((u) => u.id.eq(.value(1))).single()).score,
        1,
      );
    });

    test(
      'database close stops a paused cursor and releases the driver',
      () async {
        final first = Completer<void>();
        late StreamSubscription<int> subscription;
        subscription = ids(db).stream(batchSize: 4).listen((_) {
          subscription.pause();
          first.complete();
        });
        await first.future;
        await db.close();
        await subscription.cancel();
        expect(events.last.sql, 'ROLLBACK');
      },
    );

    cancellationTest(
      'cancellation between stream creation and listening needs no rollback',
      () async {
        final token = CancellationToken();
        final stream = ids(db)
            .stream(options: ExecutionOptions(cancellation: token));
        token.cancel();
        await expectLater(
          stream.toList(),
          throwsA(code('OPERATION.CANCELLED')),
        );
        expect(events, isEmpty);
        expect(await db.table(users).count(), 31);
      },
    );

    test('bounded cursor fetches preserve parameters and typed rows', () async {
      expect(db.capabilities.streaming, isTrue);
      final rows = await ids(db)
          .where((u) => u.id.gt(.value(3)))
          .stream(batchSize: 6)
          .toList();
      expect(rows, List.generate(28, (i) => i + 4));
      expect(getFetches().map((e) => e.rowCount), [6, 6, 6, 6, 4]);
      expect(
        events.where((e) => e.operation == .cursorOpen).single.parameterCount,
        1,
      );
      expect(events.last.sql, 'COMMIT');
      expect(await db.table(users).count(), 31);
    });

    test(
      'pause stops fetches and early cancellation releases the lease',
      () async {
        final received = <int>[];
        final first = Completer<void>();
        late StreamSubscription<int> subscription;
        subscription = ids(db).stream(batchSize: 4).listen((row) {
          received.add(row);
          subscription.pause();
          if (!first.isCompleted) first.complete();
        });
        await first.future;
        await Future<void>.delayed(const Duration(milliseconds: 35));
        expect(received, [1]);
        expect(getFetches().length, 1);
        await subscription.cancel();
        expect(events.where((e) => e.operation == .cursorClose).length, 1);
        expect(events.last.sql, 'ROLLBACK');
        expect(await db.table(users).count(), 31);
      },
    );

    test(
      'await-for provides demand and take closes without exhausting',
      () async {
        final rows = <int>[];
        await for (final row in ids(db).stream(batchSize: 3).take(7)) {
          rows.add(row);
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(rows, [1, 2, 3, 4, 5, 6, 7]);
        expect(getFetches().length, 3);
        expect(await db.table(users).count(), 31);
      },
    );

    test('relation projections load once per root batch', () async {
      await db.execute(
        SqlCommand(
          'CREATE TABLE posts ('
          'id INTEGER PRIMARY KEY, author_id INTEGER REFERENCES users(id), '
          'title TEXT NOT NULL, tag TEXT)',
        ),
      );
      await db.execute(
        SqlCommand(
          'INSERT INTO posts(id,author_id,title) '
          "SELECT id,id,email FROM users",
        ),
      );
      events.clear();
      final rows = await db
          .table(users)
          .orderBy((u) => [u.id.asc()])
          .select(
            (u) => (
              u.id,
              u.posts.select((p) => p.title).many(),
            ).map((id, titles) => (id: id, titles: titles)),
          )
          .stream(batchSize: 10)
          .toList();
      expect(rows.map((r) => r.id), List.generate(31, (i) => i + 1));
      for (final row in rows) {
        expect(row.titles, ['user${row.id}']);
      }
      expect(
        events
            .where(
              (e) => e.operation == .execute && e.sql.contains('FROM "posts"'),
            )
            .length,
        4,
      );
    });

    test('mapper failure closes the cursor and rolls back', () async {
      await expectLater(
        db
            .table(users)
            .select((u) => u.id.map<int>((_) => throw StateError('decode')))
            .stream(batchSize: 2)
            .toList(),
        throwsStateError,
      );
      expect(events.last.sql, 'ROLLBACK');
      expect(await db.table(users).count(), 31);
    });

    test(
      'early stream end inside a transaction preserves other work',
      () async {
        await db.transaction((tx) async {
          expect(await ids(tx).stream(batchSize: 4).take(2).toList(), [1, 2]);
          await tx
              .table(users)
              .where((u) => u.id.eq(.value(1)))
              .update((u) => [u.score.set(90)])
              .execute();
        });
        expect(
          (await db.table(users).where((u) => u.id.eq(.value(1))).single())
              .score,
          90,
        );
      },
    );

    test('escaping paused stream cannot keep a transaction alive', () async {
      late StreamSubscription<int> subscription;
      await expectLater(
        db.transaction((tx) async {
          await tx
              .table(users)
              .where((u) => u.id.eq(.value(1)))
              .update((u) => [u.score.set(90)])
              .execute();
          final first = Completer<void>();
          subscription = ids(tx).stream(batchSize: 4).listen((_) {
            subscription.pause();
            if (!first.isCompleted) first.complete();
          });
          await first.future;
        }),
        throwsA(code('TRANSACTION.UNAWAITED')),
      );
      await subscription.cancel();
      expect(
        (await db.table(users).where((u) => u.id.eq(.value(1))).single()).score,
        1,
      );
    });

    cancellationTest(
      'cancels executing SQL and allows the next statement',
      () async {
        expect(db.capabilities.cancellation, isTrue);
        final token = CancellationToken();
        final timer = Timer(const Duration(milliseconds: 45), token.cancel);
        final elapsed = Stopwatch()..start();
        try {
          await expectLater(
            db.execute(
              SqlCommand(slow),
              options: ExecutionOptions(cancellation: token),
            ),
            throwsA(code('OPERATION.CANCELLED')),
          );
        } finally {
          timer.cancel();
        }
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
        expect(await db.table(users).count(), 31);
      },
    );

    cancellationTest(
      'statement timeout stops SQL and leaves a usable connection',
      () async {
        await expectLater(
          db.execute(
            SqlCommand(slow),
            options: const ExecutionOptions(
              timeout: Duration(milliseconds: 40),
            ),
          ),
          throwsA(code('OPERATION.TIMEOUT')),
        );
        expect(await db.table(users).count(), 31);
      },
    );

    cancellationTest(
      'cancelled statement poisons a transaction even if caught',
      () async {
        await expectLater(
          db.transaction((tx) async {
            await tx
                .table(users)
                .where((u) => u.id.eq(.value(1)))
                .update((u) => [u.score.set(90)])
                .execute();
            final token = CancellationToken();
            final timer = Timer(const Duration(milliseconds: 40), token.cancel);
            try {
              await expectLater(
                tx.execute(
                  SqlCommand(slow),
                  options: ExecutionOptions(cancellation: token),
                ),
                throwsA(code('OPERATION.CANCELLED')),
              );
            } finally {
              timer.cancel();
            }
          }),
          throwsA(code('TRANSACTION.FAILED')),
        );
        expect(
          (await db.table(users).where((u) => u.id.eq(.value(1))).single())
              .score,
          1,
        );
      },
    );

    cancellationTest(
      'cancelling a paused stream releases its connection before resume',
      () async {
        final token = CancellationToken();
        final first = Completer<void>();
        final stopped = Completer<void>();
        final errors = <Object>[];
        late StreamSubscription<int> subscription;
        subscription = ids(db)
            .stream(
              batchSize: 4,
              options: ExecutionOptions(cancellation: token),
            )
            .listen(
              (_) {
                subscription.pause();
                first.complete();
              },
              onError: errors.add,
              onDone: stopped.complete,
            );
        await first.future;
        token.cancel();
        expect(await db.table(users).count(), 31);
        subscription.resume();
        await stopped.future;
        expect(errors.single, code('OPERATION.CANCELLED'));
      },
    );

    test('unsupported interruption rejects options before SQL or cursor acquisition', () async {
      if (db.capabilities.cancellation) {
        markTestSkipped(
          'This build supports interruption; behavior is tested above.',
        );
        return;
      }
      for (final options in [
        const ExecutionOptions(timeout: Duration(milliseconds: 40)),
        ExecutionOptions(cancellation: CancellationToken()),
      ]) {
        expect(
          () => db.execute(
            SqlCommand('UPDATE users SET score=0'),
            options: options,
          ),
          throwsA(code('CAPABILITY.CANCEL')),
        );
        expect(
          () => ids(db).stream(options: options),
          throwsA(code('CAPABILITY.CANCEL')),
        );
      }
      expect(events, isEmpty);
      expect(
        (await db.table(users).where((u) => u.id.eq(.value(1))).single()).score,
        1,
      );
    });

    test('cancellation before starting performs no SQL', () async {
      final token = CancellationToken()..cancel();
      expect(
        () => db.execute(
          SqlCommand(slow),
          options: ExecutionOptions(cancellation: token),
        ),
        throwsA(code('OPERATION.CANCELLED')),
      );
      expect(
        () => ids(db).stream(options: ExecutionOptions(cancellation: token)),
        throwsA(
          code(
            db.capabilities.cancellation
                ? 'OPERATION.CANCELLED'
                : 'CAPABILITY.CANCEL',
          ),
        ),
      );
      expect(events, isEmpty);
    });
  }, tags: name);
}
