import 'dart:io';
import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/postgres.dart';
import 'package:orm/schema.dart';
import 'package:test/test.dart';

import '../example/migrations/postgres/history.dart' as shop;

const _id = ColumnDefinition(
  name: 'id',
  field: 'id',
  type: ScalarType.integer,
  primaryKey: true,
  identity: true,
);

Migration _migration(
  int version,
  SchemaSnapshot snapshot,
  List<String> steps,
) => Migration(
  version: version,
  name: 'postgres migration $version',
  engine: Engine.postgresql,
  steps: steps,
  snapshot: snapshot,
  reviewedFingerprint: migrationFingerprint(
    version: version,
    name: 'postgres migration $version',
    engine: Engine.postgresql,
    steps: steps,
    snapshot: snapshot,
  ),
);

MigrationHistory _history(List<Migration> migrations) =>
    MigrationHistory(engine: Engine.postgresql, migrations: migrations);

/// Pins this test's schema on each acquired connection, independent of pool size.
final class _SchemaDriver implements Driver {
  _SchemaDriver(this.driver, this.schema);
  final Driver driver;
  final String schema;
  @override
  Engine get engine => driver.engine;
  @override
  Capabilities get capabilities => driver.capabilities;
  @override
  Future<T> withConnection<T>(Future<T> Function(Connection) action) =>
      driver.withConnection((connection) async {
        await connection.run('SET search_path TO "$schema"', []);
        return action(connection);
      });
  @override
  Future<void> close() => driver.close();
}

void main() {
  final socket = Platform.environment['ORM_TEST_POSTGRES_SOCKET'];
  final host = Platform.environment['ORM_TEST_POSTGRES_HOST'];
  group(
    'real PostgreSQL migration runner',
    () {
      late Database database;
      late String schema;
      setUp(() async {
        final driver = PostgresDriver(
          Endpoint(
            host: socket ?? host!,
            port: int.parse(
              Platform.environment['ORM_TEST_POSTGRES_PORT'] ?? '5432',
            ),
            database:
                Platform.environment['ORM_TEST_POSTGRES_DATABASE'] ??
                'postgres',
            username:
                Platform.environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
            password: Platform.environment['ORM_TEST_POSTGRES_PASSWORD'],
            isUnixSocket: socket != null,
          ),
          settings: const PoolSettings(
            sslMode: SslMode.disable,
            maxConnectionCount: 2,
          ),
        );
        schema =
            'orm_migration_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        await driver.withConnection(
          (connection) => connection.run('CREATE SCHEMA "$schema"', []),
        );
        database = openDatabase(_SchemaDriver(driver, schema));
      });
      tearDown(() async {
        await database.session.run('DROP SCHEMA "$schema" CASCADE');
        await database.close();
      });

      test(
        'static shop history creates its PostgreSQL schema and resumes',
        () async {
          final runner = MigrationRunner(database, shop.history);
          expect(await runner.apply(), [1]);
          expect(await runner.apply(), isEmpty);
          expect(
            (await database.session.run(
              'SELECT tablename FROM pg_tables WHERE schemaname = \$1 ORDER BY tablename',
              parameters: [schema],
            )).rows,
            [
              ['_orm_migrations'],
              ['order_lines'],
              ['orders'],
              ['posts'],
              ['products'],
              ['users'],
            ],
          );
        },
      );

      test('concurrent first application saves one history prefix', () async {
        final backends = await Future.wait([
          database.session.run(
            'SELECT pg_backend_pid() FROM (SELECT pg_sleep(0.02)) AS wait',
          ),
          database.session.run(
            'SELECT pg_backend_pid() FROM (SELECT pg_sleep(0.02)) AS wait',
          ),
        ]);
        expect(
          backends.map((result) => result.rows.single.single).toSet().length,
          2,
        );
        const snapshot = SchemaSnapshot(
          engine: Engine.postgresql,
          tables: [
            TableDefinition('users', [_id]),
          ],
        );
        final history = _history([
          _migration(
            1,
            snapshot,
            planSchemaChange(
              const SchemaSnapshot(engine: Engine.postgresql, tables: []),
              snapshot,
            ).steps,
          ),
        ]);
        final runner = MigrationRunner(database, history);
        final results = await Future.wait([runner.apply(), runner.apply()]);
        expect(results.where((result) => result.isNotEmpty).single, [1]);
        expect(results.where((result) => result.isEmpty).length, 1);
        expect(
          (await database.session.run('SELECT version FROM "_orm_migrations"'))
              .rows,
          [
            [1],
          ],
        );
      });

      test(
        'native types, literal defaults and constraints match the real catalog',
        () async {
          final snapshot = SchemaSnapshot(
            engine: Engine.postgresql,
            tables: [
              TableDefinition('users', [
                _id,
                const ColumnDefinition(
                  name: 'active',
                  field: 'active',
                  type: ScalarType.boolean,
                  defaultValue: true,
                ),
                const ColumnDefinition(
                  name: 'score',
                  field: 'score',
                  type: ScalarType.real,
                  defaultValue: -2.5,
                ),
                const ColumnDefinition(
                  name: 'name',
                  field: 'name',
                  type: ScalarType.text,
                  unique: true,
                  defaultValue: "O'Reilly",
                ),
                ColumnDefinition(
                  name: 'joined',
                  field: 'joined',
                  type: ScalarType.dateTime,
                  defaultValue: DateTime.utc(2026, 10, 9),
                ),
                ColumnDefinition(
                  name: 'avatar',
                  field: 'avatar',
                  type: ScalarType.bytes,
                  defaultValue: Uint8List.fromList([1, 255]),
                ),
              ]),
              const TableDefinition('posts', [
                _id,
                ColumnDefinition(
                  name: 'author_id',
                  field: 'authorId',
                  type: ScalarType.integer,
                  references: ForeignKey('users', 'id', onDelete: 'cascade'),
                ),
              ]),
            ],
          );
          final steps = planSchemaChange(
            const SchemaSnapshot(engine: Engine.postgresql, tables: []),
            snapshot,
          ).steps;
          final runner = MigrationRunner(
            database,
            _history([_migration(1, snapshot, steps)]),
          );
          expect(await runner.apply(), [1]);
          await database.session.run('INSERT INTO users DEFAULT VALUES');
          await database.session.run(
            'INSERT INTO posts (author_id) VALUES (\$1)',
            parameters: [1],
          );
          final row = (await database.session.run(
            'SELECT active, score, name, joined, avatar FROM users',
          )).rows.single;
          expect(row, [
            true,
            -2.5,
            "O'Reilly",
            DateTime.utc(2026, 10, 9),
            [1, 255],
          ]);
          expect(await runner.apply(), isEmpty);
          await database.session.run('DELETE FROM users');
          expect(
            (await database.session.run('SELECT * FROM posts')).rows,
            isEmpty,
          );
        },
      );

      test(
        'safe additions, saved fingerprints and catalog drift are enforced',
        () async {
          const before = SchemaSnapshot(
            engine: Engine.postgresql,
            tables: [
              TableDefinition('users', [_id]),
            ],
          );
          final first = _migration(
            1,
            before,
            planSchemaChange(
              const SchemaSnapshot(engine: Engine.postgresql, tables: []),
              before,
            ).steps,
          );
          await MigrationRunner(database, _history([first])).apply();
          await database.session.run('INSERT INTO users DEFAULT VALUES');
          const after = SchemaSnapshot(
            engine: Engine.postgresql,
            tables: [
              TableDefinition('users', [
                _id,
                ColumnDefinition(
                  name: 'nickname',
                  field: 'nickname',
                  type: ScalarType.text,
                  nullable: true,
                ),
                ColumnDefinition(
                  name: 'active',
                  field: 'active',
                  type: ScalarType.boolean,
                  defaultValue: true,
                ),
              ]),
            ],
          );
          final second = _migration(
            2,
            after,
            planSchemaChange(before, after).steps,
          );
          final runner = MigrationRunner(database, _history([first, second]));
          expect(await runner.apply(), [2]);
          expect(
            (await database.session.run('SELECT nickname, active FROM users'))
                .rows
                .single,
            [null, true],
          );
          final edited = _migration(2, after, [
            '${second.steps.first} ',
            second.steps.last,
          ]);
          await expectLater(
            MigrationRunner(database, _history([first, edited])).apply(),
            throwsStateError,
          );
          await database.session.run('ALTER TABLE users ADD COLUMN drift TEXT');
          await expectLater(runner.apply(), throwsStateError);
        },
      );

      test(
        'SQL failures and empty-SQL snapshot mismatch roll back all DDL',
        () async {
          const snapshot = SchemaSnapshot(
            engine: Engine.postgresql,
            tables: [
              TableDefinition('users', [_id]),
            ],
          );
          final steps = planSchemaChange(
            const SchemaSnapshot(engine: Engine.postgresql, tables: []),
            snapshot,
          ).steps;
          await expectLater(
            MigrationRunner(
              database,
              _history([
                _migration(1, snapshot, [steps.single, 'INVALID SQL']),
              ]),
            ).apply(),
            throwsA(anything),
          );
          expect(
            (await database.session.run(
              'SELECT tablename FROM pg_tables WHERE schemaname = \$1',
              parameters: [schema],
            )).rows,
            isEmpty,
          );
          await expectLater(
            MigrationRunner(
              database,
              _history([_migration(1, snapshot, [])]),
            ).apply(),
            throwsStateError,
          );
          expect(
            (await database.session.run(
              'SELECT tablename FROM pg_tables WHERE schemaname = \$1',
              parameters: [schema],
            )).rows,
            isEmpty,
          );
        },
      );

      test('wrong identity and missing unique constraints reject migration markers', () async {
        const snapshot = SchemaSnapshot(
          engine: Engine.postgresql,
          tables: [
            TableDefinition('users', [
              _id,
              ColumnDefinition(
                name: 'name',
                field: 'name',
                type: ScalarType.text,
                unique: true,
              ),
            ]),
          ],
        );
        for (final sql in [
          'CREATE TABLE users (id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY NOT NULL, name TEXT NOT NULL UNIQUE)',
          'CREATE TABLE users (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL, name TEXT NOT NULL)',
        ]) {
          await expectLater(
            MigrationRunner(
              database,
              _history([
                _migration(1, snapshot, [sql]),
              ]),
            ).apply(),
            throwsStateError,
          );
        }
        expect(
          (await database.session.run(
            'SELECT tablename FROM pg_tables WHERE schemaname = \$1',
            parameters: [schema],
          )).rows,
          isEmpty,
        );
      });
      test(
        'unmodeled unique index shapes reject while nonunique indexes survive',
        () async {
          const snapshot = SchemaSnapshot(
            engine: Engine.postgresql,
            tables: [
              TableDefinition('users', [
                _id,
                ColumnDefinition(
                  name: 'name',
                  field: 'name',
                  type: ScalarType.text,
                ),
                ColumnDefinition(
                  name: 'age',
                  field: 'age',
                  type: ScalarType.integer,
                ),
              ]),
            ],
          );
          final create = planSchemaChange(
            const SchemaSnapshot(engine: Engine.postgresql, tables: []),
            snapshot,
          ).steps.single;
          for (final index in [
            'CREATE UNIQUE INDEX composite ON users (name, age)',
            'CREATE UNIQUE INDEX partial ON users (name) WHERE age > 0',
            'CREATE UNIQUE INDEX expression ON users (lower(name))',
          ]) {
            await expectLater(
              MigrationRunner(
                database,
                _history([
                  _migration(1, snapshot, [create, index]),
                ]),
              ).apply(),
              throwsStateError,
            );
            expect(
              (await database.session.run(
                'SELECT tablename FROM pg_tables WHERE schemaname = \$1',
                parameters: [schema],
              )).rows,
              isEmpty,
            );
          }
          expect(
            await MigrationRunner(
              database,
              _history([
                _migration(1, snapshot, [
                  create,
                  'CREATE INDEX custom ON users (name, age)',
                ]),
              ]),
            ).apply(),
            [1],
          );
        },
      );
    },
    skip: socket == null && host == null
        ? 'Set ORM_TEST_POSTGRES_SOCKET or ORM_TEST_POSTGRES_HOST to an isolated PostgreSQL test instance.'
        : false,
  );
}
