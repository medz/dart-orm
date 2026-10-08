import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/query.dart';
import 'package:orm/schema.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

const _table = TableDefinition('keys', [
  ColumnDefinition(
    name: 'id',
    field: 'id',
    type: ScalarType.integer,
    primaryKey: true,
  ),
  ColumnDefinition(name: 'value', field: 'value', type: ScalarType.text),
]);
const _snapshot = SchemaSnapshot(engine: Engine.sqlite, tables: [_table]);

MigrationHistory _history(List<String> steps) => MigrationHistory(
  engine: Engine.sqlite,
  migrations: [
    Migration(
      version: 1,
      name: 'primary key',
      engine: Engine.sqlite,
      steps: steps,
      snapshot: _snapshot,
      reviewedFingerprint: migrationFingerprint(
        version: 1,
        name: 'primary key',
        engine: Engine.sqlite,
        steps: steps,
        snapshot: _snapshot,
      ),
    ),
  ],
);

TableQuery<({int id, String value})> _query(Database database) => TableQuery(
  database.session,
  _table,
  (row) => (id: decodeValue<int>(row[0]), value: decodeValue<String>(row[1])),
);

void main() {
  late Database database;
  setUp(() => database = openDatabase(SqliteDriver.memory()));
  tearDown(() => database.close());

  test('column-level INTEGER PRIMARY KEY DESC permits multiple NULLs and is rejected', () async {
    await database.session.run(
      'CREATE TABLE "keys" (id INTEGER PRIMARY KEY DESC, value TEXT NOT NULL)',
    );
    await database.session.run(
      "INSERT INTO \"keys\" (id,value) VALUES (NULL,'one'), (NULL,'two')",
    );
    final columns = await database.session.run('PRAGMA table_xinfo("keys")');
    final id = columns.rows.first;
    expect(id[columns.columns.indexOf('notnull')], 0);
    expect(id[columns.columns.indexOf('pk')], 1);
    final indexes = await database.session.run('PRAGMA index_list("keys")');
    expect(indexes.rows.single[indexes.columns.indexOf('origin')], 'pk');
    expect(
      (await database.session.run(
        'SELECT count(*) FROM "keys" WHERE id IS NULL',
      )).rows,
      [
        [2],
      ],
    );
    await expectLater(
      MigrationRunner(database, _history([])).apply(),
      throwsStateError,
    );
    expect(
      (await database.session.run(
        "SELECT name FROM sqlite_schema WHERE name='_orm_migrations'",
      )).rows,
      isEmpty,
    );
    expect(
      (await database.session.run(
        'SELECT count(*) FROM "keys" WHERE id IS NULL',
      )).rows,
      [
        [2],
      ],
    );
  });

  test('nullable descending key DDL rolls back and explicit NOT NULL supports typed mutations', () async {
    await expectLater(
      MigrationRunner(
        database,
        _history([
          'CREATE TABLE "keys" (id INTEGER PRIMARY KEY DESC, value TEXT NOT NULL)',
        ]),
      ).apply(),
      throwsStateError,
    );
    expect(
      (await database.session.run(
        "SELECT name FROM sqlite_schema WHERE name IN ('keys','_orm_migrations')",
      )).rows,
      isEmpty,
    );
    final history = _history([
      'CREATE TABLE "keys" (id INTEGER PRIMARY KEY DESC NOT NULL, value TEXT NOT NULL)',
    ]);
    final runner = MigrationRunner(database, history);
    expect(await runner.apply(), [1]);
    final query = _query(database);
    expect(await query.insert({'id': 1, 'value': 'one'}), (
      id: 1,
      value: 'one',
    ));
    expect(await query.get(1), (id: 1, value: 'one'));
    expect(await query.updateById(1, {'value': 'updated'}), (
      id: 1,
      value: 'updated',
    ));
    expect(
      await query.insertIfAbsent({
        'id': 1,
        'value': 'duplicate',
      }, conflictField: 'id'),
      isNull,
    );
    expect(
      await query.insertIfAbsent({
        'id': 2,
        'value': 'two',
      }, conflictField: 'id'),
      (id: 2, value: 'two'),
    );
    await expectLater(
      database.session.run(
        'INSERT INTO "keys" (id,value) VALUES (NULL,\'invalid\')',
      ),
      throwsException,
    );
    expect(await runner.apply(), isEmpty);
    expect(await query.deleteById(2), 1);
    expect(await query.all(), [(id: 1, value: 'updated')]);
    expect(
      (await database.session.run('SELECT version FROM _orm_migrations')).rows,
      [
        [1],
      ],
    );
  });

  test('ordinary INTEGER primary key and table-level descending key remain rowid aliases', () async {
    for (final ddl in [
      'CREATE TABLE "keys" (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
      'CREATE TABLE "keys" (id INTEGER, value TEXT NOT NULL, PRIMARY KEY(id DESC))',
    ]) {
      final fixture = openDatabase(SqliteDriver.memory());
      try {
        final runner = MigrationRunner(fixture, _history([ddl]));
        expect(await runner.apply(), [1]);
        final columns = await fixture.session.run('PRAGMA table_xinfo("keys")');
        expect(columns.rows.first[columns.columns.indexOf('notnull')], 0);
        expect(
          (await fixture.session.run('PRAGMA index_list("keys")')).rows,
          isEmpty,
        );
        await fixture.session.run(
          "INSERT INTO \"keys\" (id,value) VALUES (NULL,'generated')",
        );
        expect(await _query(fixture).get(1), (id: 1, value: 'generated'));
        expect(await runner.apply(), isEmpty);
      } finally {
        await fixture.close();
      }
    }
  });

  test('WITHOUT ROWID primary key remains nonnullable and accepted', () async {
    final runner = MigrationRunner(
      database,
      _history([
        'CREATE TABLE "keys" (id INTEGER PRIMARY KEY DESC, value TEXT NOT NULL) WITHOUT ROWID',
      ]),
    );
    expect(await runner.apply(), [1]);
    final columns = await database.session.run('PRAGMA table_xinfo("keys")');
    expect(columns.rows.first[columns.columns.indexOf('notnull')], 1);
    final indexes = await database.session.run('PRAGMA index_list("keys")');
    expect(indexes.rows.single[indexes.columns.indexOf('origin')], 'pk');
    expect(await _query(database).insert({'id': 1, 'value': 'one'}), (
      id: 1,
      value: 'one',
    ));
    await expectLater(
      database.session.run(
        "INSERT INTO \"keys\" (id,value) VALUES (NULL,'invalid')",
      ),
      throwsException,
    );
    expect(await runner.apply(), isEmpty);
  });
}
