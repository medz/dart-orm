import 'dart:async';
import 'dart:io';

import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/postgres.dart';
import 'package:orm/query.dart' show quoteIdentifier;
import 'package:test/test.dart';

import '../example/migrations/postgres/history.dart' as shop;
import '../example/models.db.dart';

Future<({AppDatabase app, PostgresDriver driver, String schema})> _open(
  List<DatabaseEvent> events, {
  required int maxConnections,
}) async {
  final environment = Platform.environment;
  final socket = environment['ORM_TEST_POSTGRES_SOCKET'];
  final schema =
      'orm_scope_${pid}_${DateTime.now().microsecondsSinceEpoch}_"Case';
  final driver = PostgresDriver(
    Endpoint(
      host: socket ?? environment['ORM_TEST_POSTGRES_HOST']!,
      port: int.parse(environment['ORM_TEST_POSTGRES_PORT'] ?? '5432'),
      database: environment['ORM_TEST_POSTGRES_DATABASE'] ?? 'postgres',
      username: environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
      password: environment['ORM_TEST_POSTGRES_PASSWORD'],
      isUnixSocket: socket != null,
    ),
    schema: schema,
    settings: PoolSettings(
      sslMode: SslMode.disable,
      maxConnectionCount: maxConnections,
    ),
  );
  try {
    await driver.withConnection(
      (connection) =>
          connection.run('CREATE SCHEMA ${quoteIdentifier(schema)}', []),
    );
  } catch (_) {
    await driver.close();
    rethrow;
  }
  final app = AppDatabase(driver, onEvent: events.add);
  addTearDown(() async {
    try {
      await driver.withConnection(
        (connection) => connection.run(
          'DROP SCHEMA ${quoteIdentifier(schema)} CASCADE',
          [],
        ),
      );
    } finally {
      await app.close();
    }
  });
  return (app: app, driver: driver, schema: schema);
}

void _oneStatement(List<DatabaseEvent> events, String schema) {
  expect(events, hasLength(1));
  expect(events.single.kind, 'statement');
  expect(events.single.sql, contains('${quoteIdentifier(schema)}."users"'));
}

void main() {
  group(
    'fixed PostgreSQL schema scope',
    () {
      test('typed writes stay persistent on a pooled temporary backend', () async {
        final events = <DatabaseEvent>[];
        final fixture = await _open(events, maxConnections: 2);
        final app = fixture.app;
        final driver = fixture.driver;
        final schema = quoteIdentifier(fixture.schema);
        final runner = MigrationRunner(app.database, shop.history);
        expect(await runner.apply(), [1]);
        final persistent = await app.users.create(
          username: 'persistent',
          age: 28,
        );

        final readyA = Completer<int>();
        final releaseA = Completer<void>();
        final heldA = driver
            .withConnection((connection) async {
              await connection.run(
                'CREATE TEMP TABLE users (LIKE $schema.users INCLUDING ALL) ON COMMIT PRESERVE ROWS',
                [],
              );
              await connection.run(
                "INSERT INTO users (username, age) VALUES ('temporary', 99)",
                [],
              );
              readyA.complete(
                (await connection.run(
                      'SELECT pg_backend_pid()',
                      [],
                    )).rows.single.single
                    as int,
              );
              await releaseA.future;
            })
            .catchError((Object error, StackTrace stack) {
              if (!readyA.isCompleted) readyA.completeError(error, stack);
            });
        final readyB = Completer<int>();
        final releaseB = Completer<void>();
        Future<void>? heldB;
        try {
          final backendA = await readyA.future;
          // A remains occupied, so migration verification must acquire B.
          expect(await runner.apply(), isEmpty);
          heldB = driver
              .withConnection((connection) async {
                readyB.complete(
                  (await connection.run(
                        'SELECT pg_backend_pid()',
                        [],
                      )).rows.single.single
                      as int,
                );
                await releaseB.future;
              })
              .catchError((Object error, StackTrace stack) {
                if (!readyB.isCompleted) readyB.completeError(error, stack);
              });
          expect(await readyB.future, isNot(backendA));
          // Hold B and release A, outside either native acquisition callback.
          releaseA.complete();
          await heldA;
          expect(
            (await driver.withConnection(
              (connection) => connection.run('SELECT pg_backend_pid()', []),
            )).rows.single.single,
            backendA,
          );
          events.clear();
          expect((await app.users.get(persistent.id))!.username, 'persistent');
          _oneStatement(events, fixture.schema);
          events.clear();
          expect((await app.users.update(persistent.id, age: 29))!.age, 29);
          _oneStatement(events, fixture.schema);
          events.clear();
          final claimed = await app.users.createIfAbsent(
            .username,
            username: 'temporary',
            age: 40,
          );
          expect(claimed, isNotNull);
          _oneStatement(events, fixture.schema);
          events.clear();
          expect(await app.users.delete(persistent.id), 1);
          _oneStatement(events, fixture.schema);
          await driver.withConnection((connection) async {
            expect(
              (await connection.run(
                'SELECT username, age FROM pg_temp.users',
                [],
              )).rows,
              [
                ['temporary', 99],
              ],
            );
            expect(
              (await connection.run(
                'SELECT username, age FROM $schema.users',
                [],
              )).rows,
              [
                ['temporary', 40],
              ],
            );
          });
        } finally {
          if (!releaseA.isCompleted) releaseA.complete();
          if (!releaseB.isCompleted) releaseB.complete();
          await heldA;
          await heldB;
        }
      });

      test('raw search_path cannot redirect typed operations', () async {
        final events = <DatabaseEvent>[];
        final fixture = await _open(events, maxConnections: 1);
        final app = fixture.app;
        final driver = fixture.driver;
        final schema = quoteIdentifier(fixture.schema);
        final other = quoteIdentifier('${fixture.schema}_other');
        await driver.withConnection(
          (connection) => connection.run('CREATE SCHEMA $other', []),
        );
        addTearDown(
          () => driver.withConnection(
            (connection) => connection.run('DROP SCHEMA $other CASCADE', []),
          ),
        );
        expect(await MigrationRunner(app.database, shop.history).apply(), [1]);
        final persistent = await app.users.create(
          username: 'persistent',
          age: 28,
        );
        await app.database.session.run(
          'CREATE TABLE $other.users (LIKE $schema.users INCLUDING ALL)',
        );
        await app.database.session.run(
          "INSERT INTO $other.users (username, age) VALUES ('other', 90)",
        );
        await app.database.session.run('SET search_path TO $other');
        expect(app.database.session.schema, fixture.schema);
        events.clear();
        expect((await app.users.get(persistent.id))!.username, 'persistent');
        _oneStatement(events, fixture.schema);
        events.clear();
        expect((await app.users.update(persistent.id, age: 29))!.age, 29);
        _oneStatement(events, fixture.schema);
        events.clear();
        expect(
          await app.users.createIfAbsent(.username, username: 'other', age: 40),
          isNotNull,
        );
        _oneStatement(events, fixture.schema);
        events.clear();
        expect(await app.users.delete(persistent.id), 1);
        _oneStatement(events, fixture.schema);
        expect(
          (await app.database.session.run(
            'SELECT username, age FROM $other.users',
          )).rows,
          [
            ['other', 90],
          ],
        );
        expect(
          (await app.database.session.run(
            'SELECT username, age FROM $schema.users',
          )).rows,
          [
            ['other', 40],
          ],
        );
      });
    },
    skip:
        !Platform.environment.containsKey('ORM_TEST_POSTGRES_SOCKET') &&
            !Platform.environment.containsKey('ORM_TEST_POSTGRES_HOST')
        ? 'Requires a disposable PostgreSQL instance.'
        : false,
  );
}
