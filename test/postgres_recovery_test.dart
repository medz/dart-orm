import 'dart:async';
import 'dart:io';

import 'package:orm/database.dart';
import 'package:orm/postgres.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';

const _wait = Duration(seconds: 15);

void main() {
  final environment = Platform.environment;
  final socket = environment['ORM_TEST_POSTGRES_SOCKET'];
  final host = environment['ORM_TEST_POSTGRES_HOST'];
  final port = int.parse(
    environment['ORM_TEST_POSTGRES_PORT'] ??
        (socket == null ? '5432' : '55439'),
  );
  final socketPath = socket == null || socket.contains('.s.PGSQL.')
      ? socket
      : '$socket/.s.PGSQL.$port';
  pg.Endpoint endpoint() => pg.Endpoint(
    host: socketPath ?? host!,
    port: port,
    database: environment['ORM_TEST_POSTGRES_DATABASE'] ?? 'postgres',
    username: environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
    password: environment['ORM_TEST_POSTGRES_PASSWORD'],
    isUnixSocket: socket != null,
  );
  PostgresDriver driver() => PostgresDriver(
    endpoint(),
    settings: const PoolSettings(
      sslMode: SslMode.disable,
      maxConnectionCount: 1,
      connectTimeout: Duration(seconds: 5),
      queryTimeout: Duration(seconds: 10),
    ),
  );

  group(
    'real PostgreSQL recovery',
    () {
      late Database database;
      late pg.Connection control;
      late String table;
      final events = <DatabaseEvent>[];
      setUp(() async {
        events.clear();
        control = await pg.Connection.open(
          endpoint(),
          settings: const pg.ConnectionSettings(
            sslMode: pg.SslMode.disable,
            connectTimeout: Duration(seconds: 5),
            queryTimeout: Duration(seconds: 10),
          ),
        ).timeout(_wait);
        database = openDatabase(driver(), observer: events.add);
        table = 'orm_recovery_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        await control.execute('CREATE TABLE "$table" (id BIGINT PRIMARY KEY)');
      });
      tearDown(() async {
        try {
          await database.close().timeout(_wait);
        } finally {
          try {
            await control.execute('DROP TABLE "$table"');
          } finally {
            await control.close().timeout(_wait);
          }
        }
      });

      test(
        'server timeout preserves its cause and replaces the backend',
        () async {
          final before = (await database.session.run('SELECT pg_backend_pid()'))
              .rows
              .single
              .single;
          late Session expired;
          late Object nativeError;
          late StackTrace nativeStack;
          Object? caught;
          StackTrace? caughtStack;
          try {
            await database
                .transaction((session) async {
                  expired = session;
                  await session.run('INSERT INTO "$table" VALUES (1)');
                  await session.run('SET LOCAL statement_timeout = 100');
                  try {
                    await session.run('SELECT pg_sleep(5)');
                  } catch (error, stack) {
                    nativeError = error;
                    nativeStack = stack;
                    rethrow;
                  }
                })
                .timeout(_wait);
          } catch (error, stack) {
            caught = error;
            caughtStack = stack;
          }
          expect(nativeError, isA<pg.ServerException>());
          expect((nativeError as pg.ServerException).code, '57014');
          expect(caught, same(nativeError));
          expect(caughtStack.toString(), nativeStack.toString());
          await expectLater(expired.run('SELECT 1'), throwsStateError);
          expect((await control.execute('SELECT id FROM "$table"')), isEmpty);
          expect(events.map((event) => event.kind), contains('statementError'));
          expect(events.map((event) => event.kind), contains('rollback'));
          final after = (await database.session.run('SELECT pg_backend_pid()'))
              .rows
              .single
              .single;
          expect(after, isNot(before));
          await database
              .transaction(
                (session) => session.run('INSERT INTO "$table" VALUES (2)'),
              )
              .timeout(_wait);
          expect(
            (await control.execute('SELECT id FROM "$table"')).single.single,
            2,
          );
        },
      );

      test(
        'client timeout preserves its cause and replaces the backend',
        () async {
          final timed = openDatabase(
            PostgresDriver(
              endpoint(),
              settings: const PoolSettings(
                sslMode: SslMode.disable,
                maxConnectionCount: 1,
                connectTimeout: Duration(seconds: 2),
                queryTimeout: Duration(milliseconds: 100),
              ),
            ),
          );
          addTearDown(() => timed.close().timeout(_wait));
          final before = (await timed.session.run('SELECT pg_backend_pid()'))
              .rows
              .single
              .single;
          late Session expired;
          late Object nativeError;
          late StackTrace nativeStack;
          Object? caught;
          StackTrace? caughtStack;
          try {
            await timed
                .transaction((session) async {
                  expired = session;
                  await session.run('INSERT INTO "$table" VALUES (1)');
                  try {
                    await session.run('SELECT pg_sleep(5)');
                  } catch (error, stack) {
                    nativeError = error;
                    nativeStack = stack;
                    rethrow;
                  }
                })
                .timeout(_wait);
          } catch (error, stack) {
            caught = error;
            caughtStack = stack;
          }
          expect(
            nativeError,
            anyOf(
              isA<TimeoutException>(),
              isA<pg.ServerException>().having(
                (error) => error.code,
                'SQLSTATE',
                '57014',
              ),
            ),
          );
          expect(caught, same(nativeError));
          expect(caughtStack.toString(), nativeStack.toString());
          await expectLater(expired.run('SELECT 1'), throwsStateError);
          expect((await control.execute('SELECT id FROM "$table"')), isEmpty);
          final after = (await timed.session.run('SELECT pg_backend_pid()'))
              .rows
              .single
              .single;
          expect(after, isNot(before));
          await timed
              .transaction(
                (session) => session.run('INSERT INTO "$table" VALUES (2)'),
              )
              .timeout(_wait);
          expect(
            (await control.execute('SELECT id FROM "$table"')).single.single,
            2,
          );
        },
      );

      test(
        'terminated backend preserves native cause through failed cleanup',
        () async {
          final entered = Completer<int>();
          late Session expired;
          late Object nativeError;
          late StackTrace nativeStack;
          final work = database.transaction((session) async {
            expired = session;
            final backend =
                (await session.run('SELECT pg_backend_pid()'))
                        .rows
                        .single
                        .single
                    as int;
            await session.run('INSERT INTO "$table" VALUES (1)');
            final sleeping = session.run('SELECT pg_sleep(30)');
            entered.complete(backend);
            try {
              await sleeping;
            } catch (error, stack) {
              nativeError = error;
              nativeStack = stack;
              rethrow;
            }
          });
          // Attach the error handler before the independent connection interrupts SQL.
          final outcome = work.then<(Object?, StackTrace?)>(
            (_) => (null, null),
            onError: (Object error, StackTrace stack) => (error, stack),
          );
          final backend = await entered.future.timeout(_wait);
          await _waitForSleep(control, backend);
          await _terminate(control, backend);
          final (caught, caughtStack) = await outcome.timeout(_wait);
          expect(nativeError, isA<pg.ServerException>());
          expect((nativeError as pg.ServerException).code, '57P01');
          expect(
            (nativeError as pg.ServerException).severity,
            pg.Severity.fatal,
          );
          expect(caught, same(nativeError));
          expect(caughtStack.toString(), nativeStack.toString());
          expect(events.map((event) => event.kind), contains('rollbackError'));
          await expectLater(expired.run('SELECT 1'), throwsStateError);
          expect((await control.execute('SELECT id FROM "$table"')), isEmpty);
          final replacement = (await database.session.run(
            'SELECT pg_backend_pid()',
          )).rows.single.single;
          expect(replacement, isNot(backend));
          await database
              .transaction(
                (session) => session.run('INSERT INTO "$table" VALUES (2)'),
              )
              .timeout(_wait);
          expect(
            (await control.execute('SELECT id FROM "$table"')).single.single,
            2,
          );
        },
      );

      test('caught backend failure survives direct callback cleanup', () async {
        final direct = driver();
        addTearDown(() => direct.close().timeout(_wait));
        final entered = Completer<int>();
        late Connection expired;
        late Object nativeError;
        late StackTrace nativeStack;
        final work = direct.withConnection<void>((connection) async {
          expired = connection;
          await connection.run('BEGIN', const []);
          final backend =
              (await connection.run(
                    'SELECT pg_backend_pid()',
                    const [],
                  )).rows.single.single
                  as int;
          await connection.run('INSERT INTO "$table" VALUES (1)', const []);
          final sleeping = connection.run('SELECT pg_sleep(30)', const []);
          entered.complete(backend);
          try {
            await sleeping;
          } catch (error, stack) {
            nativeError = error;
            nativeStack = stack;
            // Return normally: the driver must surface the issued SQL failure.
          }
        });
        final outcome = work.then<(Object?, StackTrace?)>(
          (_) => (null, null),
          onError: (Object error, StackTrace stack) => (error, stack),
        );
        final backend = await entered.future.timeout(_wait);
        await _waitForSleep(control, backend);
        await _terminate(control, backend);
        final (caught, caughtStack) = await outcome.timeout(_wait);
        expect(nativeError, isA<pg.ServerException>());
        expect((nativeError as pg.ServerException).code, '57P01');
        expect((nativeError as pg.ServerException).severity, pg.Severity.fatal);
        expect(caught, same(nativeError));
        expect(caughtStack.toString(), nativeStack.toString());
        await expectLater(expired.run('SELECT 1', const []), throwsStateError);
        expect((await control.execute('SELECT id FROM "$table"')), isEmpty);
        final replacement = (await direct.withConnection(
          (connection) => connection.run('SELECT pg_backend_pid()', const []),
        )).rows.single.single;
        expect(replacement, isNot(backend));
        await direct.withConnection(
          (connection) =>
              connection.run('INSERT INTO "$table" VALUES (2)', const []),
        );
        expect(
          (await control.execute('SELECT id FROM "$table"')).single.single,
          2,
        );
      });

      test(
        'close drains admitted work when its backend is terminated',
        () async {
          final entered = Completer<int>();
          final work = database.transaction((session) async {
            final backend =
                (await session.run('SELECT pg_backend_pid()'))
                        .rows
                        .single
                        .single
                    as int;
            await session.run('INSERT INTO "$table" VALUES (1)');
            final sleeping = session.run('SELECT pg_sleep(30)');
            entered.complete(backend);
            await sleeping;
          });
          final outcome = work.then<Object?>(
            (_) => null,
            onError: (Object error, StackTrace _) => error,
          );
          final backend = await entered.future.timeout(_wait);
          await _waitForSleep(control, backend);
          final close = database.close();
          expect(database.close(), same(close));
          var closed = false;
          final drained = close.then((_) => closed = true);
          await expectLater(database.session.run('SELECT 1'), throwsStateError);
          await expectLater(
            database.transaction((_) async {}),
            throwsStateError,
          );
          expect(closed, isFalse);
          await _terminate(control, backend);
          expect(await outcome.timeout(_wait), isA<pg.PgException>());
          await drained.timeout(_wait);
          expect(closed, isTrue);
          expect(database.close(), same(close));
          expect((await control.execute('SELECT id FROM "$table"')), isEmpty);
          await expectLater(database.session.run('SELECT 1'), throwsStateError);
        },
      );
    },
    skip: socket == null && host == null
        ? 'Set ORM_TEST_POSTGRES_SOCKET or ORM_TEST_POSTGRES_HOST to verify PostgreSQL against a real server.'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

Future<void> _waitForSleep(pg.Connection control, int backend) async {
  final deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 5)) {
    final result = await control.execute(
      pg.Sql(
        r'SELECT wait_event FROM pg_stat_activity WHERE pid = $1',
        types: [pg.Type.integer],
      ),
      parameters: [backend],
    );
    if (result.isNotEmpty && result.single.single == 'PgSleep') return;
  }
  fail('Backend $backend did not enter pg_sleep within five seconds.');
}

Future<void> _terminate(pg.Connection control, int backend) async {
  final result = await control.execute(
    pg.Sql(r'SELECT pg_terminate_backend($1)', types: [pg.Type.integer]),
    parameters: [backend],
  );
  expect(result.single.single, isTrue);
}
