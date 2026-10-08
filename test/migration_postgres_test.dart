import 'dart:io';
import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/postgres.dart';
import 'package:orm/query.dart';
import 'package:orm/schema.dart';
import 'package:postgres/postgres.dart'
    show ForeignKeyViolationException, UniqueViolationException;
import 'package:test/test.dart';

import '../example/migrations/postgres/history.dart' as shop;
import '../example/models.db.dart' show AppDatabase;

const _id = ColumnDefinition(
  name: 'id',
  field: 'id',
  type: ScalarType.integer,
  primaryKey: true,
  identity: true,
);

const _relationships = SchemaSnapshot(
  engine: Engine.postgresql,
  tables: [
    TableDefinition('parents', [_id]),
    TableDefinition('children', [
      _id,
      ColumnDefinition(
        name: 'parent_id',
        field: 'parentId',
        type: ScalarType.integer,
        references: ForeignKey('parents', 'id'),
      ),
    ]),
  ],
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

PostgresDriver _driver({int maxConnections = 2}) {
  final environment = Platform.environment;
  final socket = environment['ORM_TEST_POSTGRES_SOCKET'];
  return PostgresDriver(
    Endpoint(
      host: socket ?? environment['ORM_TEST_POSTGRES_HOST']!,
      port: int.parse(environment['ORM_TEST_POSTGRES_PORT'] ?? '5432'),
      database: environment['ORM_TEST_POSTGRES_DATABASE'] ?? 'postgres',
      username: environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
      password: environment['ORM_TEST_POSTGRES_PASSWORD'],
      isUnixSocket: socket != null,
    ),
    settings: PoolSettings(
      sslMode: SslMode.disable,
      maxConnectionCount: maxConnections,
    ),
  );
}

List<String> _temporaryUsers(String schema, String kind) => [
  'CREATE TEMP TABLE ${kind == 'table' ? 'users' : 'shadow_users'} (LIKE "$schema".users INCLUDING ALL) ON COMMIT PRESERVE ROWS',
  if (kind == 'view')
    'CREATE TEMP VIEW users AS SELECT * FROM pg_temp.shadow_users',
  "INSERT INTO users (username, age) VALUES ('temporary', 99)",
];

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
      late AppDatabase app;
      late String schema;
      Future<void> useSingleConnection({bool temporarySchema = false}) async {
        // Keep the owned persistent schema, but fix temp state to one backend.
        await database.close();
        app = AppDatabase(
          _SchemaDriver(
            _driver(maxConnections: 1),
            temporarySchema ? 'pg_temp' : schema,
          ),
        );
        database = app.database;
      }

      setUp(() async {
        final driver = _driver();
        schema =
            'orm_migration_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        await driver.withConnection(
          (connection) => connection.run('CREATE SCHEMA "$schema"', []),
        );
        app = AppDatabase(_SchemaDriver(driver, schema));
        database = app.database;
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

      for (final kind in ['table', 'view']) {
        test('temporary $kind shadows roll back first migration', () async {
          await useSingleConnection();
          final snapshot = SchemaSnapshot(
            engine: Engine.postgresql,
            tables: [shop.history.migrations.single.snapshot.tables.first],
          );
          final steps = planSchemaChange(
            const SchemaSnapshot(engine: Engine.postgresql, tables: []),
            snapshot,
          ).steps;
          await expectLater(
            MigrationRunner(
              database,
              _history([
                _migration(1, snapshot, [
                  ...steps,
                  ..._temporaryUsers(schema, kind),
                ]),
              ]),
            ).apply(),
            throwsStateError,
          );
          expect(
            (await database.session.run(
              'SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE (n.nspname = \$1 OR n.oid = pg_my_temp_schema()) AND c.relname IN (\'users\', \'shadow_users\', \'_orm_migrations\')',
              parameters: [schema],
            )).rows,
            isEmpty,
          );
        });

        test(
          'temporary $kind shadows reject resumed history and preserve data',
          () async {
            await useSingleConnection();
            final runner = MigrationRunner(database, shop.history);
            expect(await runner.apply(), [1]);
            final persistent = await app.users.create(
              username: 'persistent',
              age: 28,
            );
            final markers = (await database.session.run(
              'SELECT * FROM "$schema"."_orm_migrations" ORDER BY version',
            )).rows;
            for (final sql in _temporaryUsers(schema, kind)) {
              await database.session.run(sql);
            }
            expect((await app.users.get(persistent.id))!.username, 'temporary');
            expect((await app.users.update(persistent.id, age: 100))!.age, 100);
            await expectLater(runner.apply(), throwsStateError);
            expect(
              (await database.session.run(
                'SELECT username, age FROM "$schema".users',
              )).rows,
              [
                ['persistent', 28],
              ],
            );
            expect(
              (await database.session.run(
                'SELECT * FROM "$schema"."_orm_migrations" ORDER BY version',
              )).rows,
              markers,
            );
            // A rejected callback may discard its backend and its temp objects.
            await database.session.run('DROP $kind IF EXISTS pg_temp.users');
            if (kind == 'view') {
              await database.session.run(
                'DROP TABLE IF EXISTS pg_temp.shadow_users',
              );
            }
            expect(await runner.apply(), isEmpty);
            final restored = await app.users.create(
              username: 'after_shadow',
              age: 30,
            );
            expect(
              (await app.users.get(restored.id))!.username,
              'after_shadow',
            );
            expect((await app.users.update(restored.id, age: 31))!.age, 31);
            expect(await app.users.delete(restored.id), 1);
            expect((await app.users.get(persistent.id))!.age, 28);
          },
        );
      }

      test(
        'temporary-only search path rejects internal migration history',
        () async {
          await useSingleConnection(temporarySchema: true);
          await database.session.run('CREATE TEMP TABLE anchor (id BIGINT)');
          await expectLater(
            MigrationRunner(database, shop.history).apply(),
            throwsStateError,
          );
          expect(
            (await database.session.run(
              'SELECT relname FROM pg_class WHERE relnamespace = pg_my_temp_schema() AND relname = \'_orm_migrations\'',
            )).rows,
            isEmpty,
          );
          expect(
            (await database.session.run(
              'SELECT tablename FROM pg_tables WHERE schemaname = \$1',
              parameters: [schema],
            )).rows,
            isEmpty,
          );
          await useSingleConnection();
          final runner = MigrationRunner(database, shop.history);
          expect(await runner.apply(), [1]);
          expect(await runner.apply(), isEmpty);
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

      test(
        'unenforced foreign keys roll back DDL and migration markers',
        () async {
          final version =
              (await database.session.run(
                    "SELECT current_setting('server_version_num')::integer",
                  )).rows.single.single
                  as int;
          if (version < 180000) {
            markTestSkipped('NOT ENFORCED foreign keys require PostgreSQL 18.');
            return;
          }
          final steps = planSchemaChange(
            const SchemaSnapshot(engine: Engine.postgresql, tables: []),
            _relationships,
          ).steps;
          await expectLater(
            MigrationRunner(
              database,
              _history([
                _migration(1, _relationships, [
                  for (final sql in steps)
                    sql.replaceFirst(
                      'ON DELETE RESTRICT',
                      'ON DELETE RESTRICT NOT ENFORCED',
                    ),
                ]),
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
          final runner = MigrationRunner(
            database,
            _history([_migration(1, _relationships, steps)]),
          );
          expect(await runner.apply(), [1]);
          await expectLater(
            database.session.run(
              'INSERT INTO children (parent_id) VALUES (999)',
            ),
            throwsA(isA<ForeignKeyViolationException>()),
          );
          expect(await runner.apply(), isEmpty);
        },
      );

      test(
        'unvalidated foreign keys with orphan rows reject migration markers',
        () async {
          const steps = [
            'CREATE TABLE parents (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL)',
            'CREATE TABLE children (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL, parent_id BIGINT NOT NULL)',
            'INSERT INTO children (parent_id) VALUES (999)',
            'ALTER TABLE children ADD CONSTRAINT parent_fk FOREIGN KEY (parent_id) REFERENCES parents(id) ON DELETE RESTRICT NOT VALID',
          ];
          await expectLater(
            MigrationRunner(
              database,
              _history([_migration(1, _relationships, steps)]),
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
          final runner = MigrationRunner(
            database,
            _history([
              _migration(1, _relationships, [
                ...steps.take(2),
                steps.last,
                'ALTER TABLE children VALIDATE CONSTRAINT parent_fk',
              ]),
            ]),
          );
          expect(await runner.apply(), [1]);
          expect(await runner.apply(), isEmpty);
        },
      );

      test(
        'failed concurrent unique indexes reject migration markers',
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
                  unique: true,
                ),
              ]),
            ],
          );
          await database.session.run(
            'CREATE TABLE users (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL, name TEXT NOT NULL)',
          );
          await database.session.run(
            "INSERT INTO users (name) VALUES ('duplicate'), ('duplicate')",
          );
          await expectLater(
            database.session.run(
              'CREATE UNIQUE INDEX CONCURRENTLY names ON users (name)',
            ),
            throwsA(isA<UniqueViolationException>()),
          );
          expect(
            (await database.session.run(
              "SELECT indisvalid, indisready FROM pg_index WHERE indexrelid = 'names'::regclass",
            )).rows,
            [
              [false, false],
            ],
          );
          final runner = MigrationRunner(
            database,
            _history([_migration(1, snapshot, [])]),
          );
          await expectLater(runner.apply(), throwsStateError);
          expect(
            (await database.session.run(
              "SELECT to_regclass('_orm_migrations')",
            )).rows,
            [
              [null],
            ],
          );
          expect(
            (await database.session.run('SELECT count(*) FROM users'))
                .rows
                .single
                .single,
            2,
          );
          await database.session.run('DROP INDEX names');
          await database.session.run('DELETE FROM users WHERE id = 2');
          await database.session.run(
            'CREATE UNIQUE INDEX CONCURRENTLY names ON users (name)',
          );
          expect(await runner.apply(), [1]);
          await expectLater(
            database.session.run(
              "INSERT INTO users (name) VALUES ('duplicate')",
            ),
            throwsA(isA<UniqueViolationException>()),
          );
          expect(await runner.apply(), isEmpty);
        },
      );

      test(
        'deferrable unique keys reject before typed conflict creation',
        () async {
          final snapshot = SchemaSnapshot(
            engine: Engine.postgresql,
            tables: [shop.history.migrations.single.snapshot.tables.first],
          );
          final steps = planSchemaChange(
            const SchemaSnapshot(engine: Engine.postgresql, tables: []),
            snapshot,
          ).steps;
          await expectLater(
            MigrationRunner(
              database,
              _history([
                _migration(1, snapshot, [
                  steps.single.replaceFirst(
                    ' UNIQUE',
                    ' UNIQUE DEFERRABLE INITIALLY IMMEDIATE',
                  ),
                ]),
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
          final runner = MigrationRunner(
            database,
            _history([_migration(1, snapshot, steps)]),
          );
          expect(await runner.apply(), [1]);
          final row = await app.users.createIfAbsent(
            .username,
            username: 'claim',
            age: 28,
          );
          expect(row!.username, 'claim');
          expect(
            await app.users.createIfAbsent(
              .username,
              username: 'claim',
              age: 99,
            ),
            isNull,
          );
          expect((await app.users.get(row.id))!.age, 28);
          expect(await runner.apply(), isEmpty);
        },
      );

      test(
        'deferrable primary keys reject before typed conflict creation',
        () async {
          const table = TableDefinition('claims', [
            ColumnDefinition(
              name: 'id',
              field: 'id',
              type: ScalarType.integer,
              primaryKey: true,
            ),
            ColumnDefinition(
              name: 'value',
              field: 'value',
              type: ScalarType.text,
            ),
          ]);
          const snapshot = SchemaSnapshot(
            engine: Engine.postgresql,
            tables: [table],
          );
          final steps = planSchemaChange(
            const SchemaSnapshot(engine: Engine.postgresql, tables: []),
            snapshot,
          ).steps;
          await expectLater(
            MigrationRunner(
              database,
              _history([
                _migration(1, snapshot, [
                  steps.single.replaceFirst(
                    ' PRIMARY KEY',
                    ' PRIMARY KEY DEFERRABLE INITIALLY DEFERRED',
                  ),
                ]),
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
          final runner = MigrationRunner(
            database,
            _history([_migration(1, snapshot, steps)]),
          );
          expect(await runner.apply(), [1]);
          final query = TableQuery(
            database.session,
            table,
            (row) => (
              id: decodeValue<int>(row[0]),
              value: decodeValue<String>(row[1]),
            ),
          );
          expect(
            await query.insertIfAbsent({
              'id': 1,
              'value': 'claim',
            }, conflictField: 'id'),
            (id: 1, value: 'claim'),
          );
          expect(
            await query.insertIfAbsent({
              'id': 1,
              'value': 'ignored',
            }, conflictField: 'id'),
            isNull,
          );
          expect(await query.get(1), (id: 1, value: 'claim'));
          expect(await runner.apply(), isEmpty);
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
