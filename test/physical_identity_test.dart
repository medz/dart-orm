import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/query.dart';
import 'package:orm/schema.dart';
import 'package:test/test.dart';

import '../example/migrations/postgres/history.dart' as postgres;
import '../example/migrations/sqlite/history.dart' as sqlite;
import 'support/database.dart';

const _id = ColumnDefinition(
  name: 'id',
  field: 'id',
  type: ScalarType.integer,
  primaryKey: true,
);
const _upperId = ColumnDefinition(
  name: 'ID',
  field: 'upperId',
  type: ScalarType.integer,
);

Future<void> _applyTables(
  TestDatabase fixture,
  Engine engine,
  List<TableDefinition> tables,
) async {
  final initial = engine == Engine.sqlite ? sqlite.history : postgres.history;
  final before = initial.migrations.last.snapshot;
  final after = SchemaSnapshot(
    engine: engine,
    tables: [...before.tables, ...tables],
  );
  final plan = planSchemaChange(before, after);
  final next = Migration(
    version: 2,
    name: 'physical identities',
    engine: engine,
    steps: plan.steps,
    snapshot: plan.snapshot,
    reviewedFingerprint: migrationFingerprint(
      version: 2,
      name: 'physical identities',
      engine: engine,
      steps: plan.steps,
      snapshot: plan.snapshot,
    ),
  );
  expect(
    await MigrationRunner(
      fixture.db.database,
      MigrationHistory(
        engine: engine,
        migrations: [...initial.migrations, next],
      ),
    ).apply(),
    [2],
  );
}

void main() {
  test(
    'real SQLite treats quoted ASCII aliases as the same identity',
    () async {
      final fixture = await openTestDatabase(Engine.sqlite);
      addTearDown(fixture.db.close);
      for (final sql in [
        'CREATE TABLE "Users" (id INTEGER)',
        'CREATE TABLE "_ORM_MIGRATIONS" (id INTEGER)',
        'CREATE TABLE duplicate_columns ("id" INTEGER, "ID" INTEGER)',
      ]) {
        await expectLater(fixture.db.session.run(sql), throwsException);
      }
    },
  );

  test(
    'SQLite rejects reserved aliases and ASCII duplicates before SQL',
    () async {
      final fixture = await openTestDatabase(Engine.sqlite);
      addTearDown(fixture.db.close);
      const invalidTables = [
        [
          TableDefinition('_ORM_MIGRATIONS', [_id]),
        ],
        [
          TableDefinition('_Orm_Migrations', [_id]),
        ],
        [
          TableDefinition('users', [_id]),
          TableDefinition('Users', [_id]),
        ],
        [
          TableDefinition('mixed_columns', [_id, _upperId]),
        ],
      ];
      for (final tables in invalidTables) {
        expect(
          () => planSchemaChange(
            const SchemaSnapshot(engine: Engine.sqlite, tables: []),
            SchemaSnapshot(engine: Engine.sqlite, tables: tables),
          ),
          throwsArgumentError,
        );
      }
      for (final table in [
        const TableDefinition('_ORM_MIGRATIONS', [_id]),
        const TableDefinition('mixed_columns', [_id, _upperId]),
      ]) {
        expect(
          () => TableQuery(fixture.db.session, table, (row) => row),
          throwsArgumentError,
        );
      }
      expect(fixture.events, isEmpty);
    },
  );

  for (final engine in Engine.values) {
    group(
      'physical identity on ${engine.name}',
      skip: engine == Engine.postgresql && !hasPostgres
          ? 'Set ORM_TEST_POSTGRES_HOST or ORM_TEST_POSTGRES_SOCKET for a real database'
          : false,
      () {
        test('exact history name remains reserved before SQL', () async {
          final fixture = await openTestDatabase(engine);
          addTearDown(fixture.db.close);
          const table = TableDefinition('_orm_migrations', [_id]);
          expect(
            () => MigrationPlan(
              engine: engine,
              steps: const [],
              snapshot: SchemaSnapshot(engine: engine, tables: const [table]),
            ),
            throwsArgumentError,
          );
          expect(
            () => TableQuery(fixture.db.session, table, (row) => row),
            throwsArgumentError,
          );
          expect(fixture.events, isEmpty);
        });

        test(
          'non-ASCII case variants stay distinct in tables and columns',
          () async {
            final fixture = await openTestDatabase(engine);
            addTearDown(fixture.db.close);
            const tables = [
              TableDefinition('Ä', [
                _id,
                ColumnDefinition(
                  name: 'Ä',
                  field: 'upper',
                  type: ScalarType.text,
                ),
                ColumnDefinition(
                  name: 'ä',
                  field: 'lower',
                  type: ScalarType.text,
                ),
              ]),
              TableDefinition('ä', [
                _id,
                ColumnDefinition(
                  name: 'Ä',
                  field: 'upper',
                  type: ScalarType.text,
                ),
                ColumnDefinition(
                  name: 'ä',
                  field: 'lower',
                  type: ScalarType.text,
                ),
              ]),
            ];
            await _applyTables(fixture, engine, tables);
            for (final (index, table) in tables.indexed) {
              final query = TableQuery(
                fixture.db.session,
                table,
                (row) => (
                  id: decodeValue<int>(row[0]),
                  upper: decodeValue<String>(row[1]),
                  lower: decodeValue<String>(row[2]),
                ),
              );
              final row = await query.insert({
                'id': 1,
                'upper': 'upper$index',
                'lower': 'lower$index',
              });
              expect(row, (id: 1, upper: 'upper$index', lower: 'lower$index'));
              expect(await query.get(1), row);
            }
          },
        );
      },
    );
  }

  test(
    'PostgreSQL quoted ASCII variants are separate physical identities',
    skip: !hasPostgres
        ? 'Set ORM_TEST_POSTGRES_HOST or ORM_TEST_POSTGRES_SOCKET for a real database'
        : false,
    () async {
      final fixture = await openTestDatabase(Engine.postgresql);
      addTearDown(fixture.db.close);
      const tables = [
        TableDefinition('cases', [_id, _upperId]),
        TableDefinition('Cases', [_id, _upperId]),
        TableDefinition('_ORM_MIGRATIONS', [_id, _upperId]),
      ];
      await _applyTables(fixture, Engine.postgresql, tables);
      for (final (index, table) in tables.indexed) {
        final query = TableQuery(
          fixture.db.session,
          table,
          (row) =>
              (id: decodeValue<int>(row[0]), upperId: decodeValue<int>(row[1])),
        );
        final row = await query.insert({'id': 1, 'upperId': index + 2});
        expect(row, (id: 1, upperId: index + 2));
        expect(await query.get(1), row);
      }
    },
  );
}
