import 'dart:convert';

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

Future<MigrationHistory> _applyTables(
  TestDatabase fixture,
  Engine engine,
  List<TableDefinition> tables, {
  List<String>? steps,
}) async {
  final initial = engine == Engine.sqlite ? sqlite.history : postgres.history;
  final before = initial.migrations.last.snapshot;
  final after = SchemaSnapshot(
    engine: engine,
    tables: [...before.tables, ...tables],
  );
  final plan = planSchemaChange(before, after);
  final sql = steps ?? plan.steps;
  final next = Migration(
    version: 2,
    name: 'physical identities',
    engine: engine,
    steps: sql,
    snapshot: plan.snapshot,
    reviewedFingerprint: migrationFingerprint(
      version: 2,
      name: 'physical identities',
      engine: engine,
      steps: sql,
      snapshot: plan.snapshot,
    ),
  );
  final history = MigrationHistory(
    engine: engine,
    migrations: [...initial.migrations, next],
  );
  expect(await MigrationRunner(fixture.db.database, history).apply(), [2]);
  return history;
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
        'CREATE TABLE "SQLite_widgets" (id INTEGER)',
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
          TableDefinition('sqlite_widgets', [_id]),
        ],
        [
          TableDefinition('SQLite_schema', [_id]),
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
        const TableDefinition('sqlite_widgets', [_id]),
        const TableDefinition('SQLite_schema', [_id]),
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

  test(
    'SQLite catalog accepts reviewed physical aliases in handwritten DDL',
    () async {
      final fixture = await openTestDatabase(Engine.sqlite);
      addTearDown(fixture.db.close);
      const parent = TableDefinition('Parents', [
        ColumnDefinition(
          name: 'ID',
          field: 'id',
          type: ScalarType.integer,
          primaryKey: true,
          identity: true,
        ),
      ]);
      const child = TableDefinition('Children', [
        _id,
        ColumnDefinition(
          name: 'parent_id',
          field: 'parentId',
          type: ScalarType.integer,
          references: ForeignKey('parents', 'id'),
        ),
      ]);
      final history = await _applyTables(
        fixture,
        Engine.sqlite,
        [child, parent],
        steps: [
          'CREATE TABLE "pARENTS" ("Id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL)',
          'CREATE TABLE "cHILDREN" ("iD" INTEGER PRIMARY KEY NOT NULL, "PARENT_ID" INTEGER NOT NULL REFERENCES "PARENTS" ("Id") ON DELETE RESTRICT)',
        ],
      );
      final parents = TableQuery(
        fixture.db.session,
        parent,
        (row) => row.single,
      );
      final children = TableQuery(
        fixture.db.session,
        child,
        (row) => (row[0], row[1]),
      );
      final id = await parents.insert({});
      expect(id, 1);
      expect(await children.insert({'id': 2, 'parentId': id}), (2, 1));
      expect(
        await MigrationRunner(fixture.db.database, history).apply(),
        isEmpty,
      );
      expect(await parents.get(1), 1);
      expect(await children.get(2), (2, 1));
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
          'foreign keys use the engine table and column identity rules',
          () async {
            final fixture = await openTestDatabase(engine);
            addTearDown(fixture.db.close);
            const child = TableDefinition('Children', [
              _id,
              ColumnDefinition(
                name: 'parent_id',
                field: 'parentId',
                type: ScalarType.integer,
                references: ForeignKey('parents', 'id'),
              ),
            ]);
            const parent = TableDefinition('Parents', [
              ColumnDefinition(
                name: 'ID',
                field: 'id',
                type: ScalarType.integer,
                primaryKey: true,
              ),
            ]);
            const tables = [child, parent];
            if (engine == Engine.postgresql) {
              for (final invalid in [
                tables,
                const [
                  TableDefinition('Children', [
                    _id,
                    ColumnDefinition(
                      name: 'parent_id',
                      field: 'parentId',
                      type: ScalarType.integer,
                      references: ForeignKey('Parents', 'id'),
                    ),
                  ]),
                  parent,
                ],
              ]) {
                expect(
                  () => planSchemaChange(
                    const SchemaSnapshot(engine: Engine.postgresql, tables: []),
                    SchemaSnapshot(engine: Engine.postgresql, tables: invalid),
                  ),
                  throwsArgumentError,
                );
              }
              expect(fixture.events, isEmpty);
              return;
            }
            final plan = planSchemaChange(
              const SchemaSnapshot(engine: Engine.sqlite, tables: []),
              const SchemaSnapshot(engine: Engine.sqlite, tables: tables),
            );
            expect(
              plan.steps.first.startsWith('CREATE TABLE "Parents"'),
              isTrue,
            );
            expect(plan.steps.last, contains('REFERENCES "parents" ("id")'));
            final history = await _applyTables(fixture, engine, tables);
            final parents = TableQuery(
              fixture.db.session,
              parent,
              (row) => row.single,
            );
            final children = TableQuery(
              fixture.db.session,
              child,
              (row) => (row[0], row[1]),
            );
            expect(await parents.insert({'id': 1}), 1);
            expect(await children.insert({'id': 2, 'parentId': 1}), (2, 1));
            await expectLater(
              children.insert({'id': 3, 'parentId': 999}),
              throwsException,
            );
            expect(
              await MigrationRunner(fixture.db.database, history).apply(),
              isEmpty,
            );
            expect(await children.get(2), (2, 1));
          },
        );

        test(
          '63-byte table, column and reference identities stay exact',
          () async {
            final fixture = await openTestDatabase(engine);
            addTearDown(fixture.db.close);
            final tableName = List.filled(63, 't').join();
            final columnName = '${List.filled(61, 'c').join()}é';
            expect(utf8.encode(tableName), hasLength(63));
            expect(utf8.encode(columnName), hasLength(63));
            final parent = TableDefinition(tableName, [
              ColumnDefinition(
                name: columnName,
                field: 'id',
                type: ScalarType.integer,
                primaryKey: true,
              ),
              const ColumnDefinition(
                name: 'value',
                field: 'value',
                type: ScalarType.text,
              ),
            ]);
            final child = TableDefinition('boundary_reference', [
              _id,
              ColumnDefinition(
                name: 'parent_id',
                field: 'parentId',
                type: ScalarType.integer,
                references: ForeignKey(tableName, columnName),
              ),
            ]);
            await _applyTables(fixture, engine, [parent, child]);
            final parentQuery = TableQuery(
              fixture.db.session,
              parent,
              (row) => (
                id: decodeValue<int>(row[0]),
                value: decodeValue<String>(row[1]),
              ),
            );
            final childQuery = TableQuery(
              fixture.db.session,
              child,
              (row) => (
                id: decodeValue<int>(row[0]),
                parentId: decodeValue<int>(row[1]),
              ),
            );
            expect(await parentQuery.insert({'id': 1, 'value': 'exact'}), (
              id: 1,
              value: 'exact',
            ));
            expect(await childQuery.insert({'id': 2, 'parentId': 1}), (
              id: 2,
              parentId: 1,
            ));
            expect(await parentQuery.updateById(1, {'value': 'updated'}), (
              id: 1,
              value: 'updated',
            ));
            expect(await parentQuery.get(1), (id: 1, value: 'updated'));
            expect(await childQuery.get(2), (id: 2, parentId: 1));
          },
        );

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
    'PostgreSQL rejects overlong physical identities without touching short names',
    skip: !hasPostgres
        ? 'Set ORM_TEST_POSTGRES_HOST or ORM_TEST_POSTGRES_SOCKET for a real database'
        : false,
    () async {
      final fixture = await openTestDatabase(Engine.postgresql);
      addTearDown(fixture.db.close);
      final shortTable = List.filled(63, 't').join();
      final shortColumn = '${List.filled(61, 'c').join()}é';
      final longTable = '${shortTable}x';
      final longColumn = '${shortColumn}x';
      expect(utf8.encode(longColumn), hasLength(64));
      expect(longColumn, hasLength(63));
      final table = TableDefinition(shortTable, const [
        _id,
        ColumnDefinition(name: 'value', field: 'value', type: ScalarType.text),
      ]);
      final columns = TableDefinition('column_boundary', [
        _id,
        ColumnDefinition(
          name: shortColumn,
          field: 'value',
          type: ScalarType.text,
        ),
      ]);
      await _applyTables(fixture, Engine.postgresql, [table, columns]);
      final tableQuery = TableQuery(fixture.db.session, table, (row) => row[1]);
      final columnQuery = TableQuery(
        fixture.db.session,
        columns,
        (row) => row[1],
      );
      await tableQuery.insert({'id': 1, 'value': 'short-table-original'});
      await columnQuery.insert({'id': 1, 'value': 'short-column-original'});
      fixture.events.clear();
      final invalid = [
        TableDefinition(longTable, table.columns),
        TableDefinition(longColumn, table.columns),
        TableDefinition(columns.name, [
          _id,
          ColumnDefinition(
            name: longColumn,
            field: 'value',
            type: ScalarType.text,
          ),
        ]),
        TableDefinition('reference_boundary', [
          _id,
          ColumnDefinition(
            name: 'parent_id',
            field: 'value',
            type: ScalarType.integer,
            references: ForeignKey(longTable, 'id'),
          ),
        ]),
        TableDefinition('reference_boundary', [
          _id,
          ColumnDefinition(
            name: 'parent_value',
            field: 'value',
            type: ScalarType.text,
            references: ForeignKey(columns.name, longColumn),
          ),
        ]),
      ];
      final rejected = throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('63 UTF-8 bytes'),
        ),
      );
      for (final definition in invalid) {
        expect(
          () => freezeSnapshot(
            SchemaSnapshot(engine: Engine.postgresql, tables: [definition]),
          ),
          rejected,
        );
        await expectLater(
          Future.sync(
            () => TableQuery(
              fixture.db.session,
              definition,
              (row) => row,
            ).updateById(1, {'value': 'must-not-write'}),
          ),
          rejected,
        );
      }
      expect(fixture.events, isEmpty);
      expect(await tableQuery.get(1), 'short-table-original');
      expect(await columnQuery.get(1), 'short-column-original');
    },
  );

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
