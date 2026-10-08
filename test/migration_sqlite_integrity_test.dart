import 'dart:io';

import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';
import 'package:orm/sqlite.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

const _id = ColumnDefinition(
  name: 'id',
  field: 'id',
  type: ScalarType.integer,
  primaryKey: true,
);
const _relations = SchemaSnapshot(
  engine: Engine.sqlite,
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
const _users = SchemaSnapshot(
  engine: Engine.sqlite,
  tables: [
    TableDefinition('users', [_id]),
  ],
);
const _audit = TableDefinition('audit', [_id]);

Migration _migration(
  int version,
  SchemaSnapshot snapshot,
  List<String> steps,
) => Migration(
  version: version,
  name: 'integrity $version',
  engine: Engine.sqlite,
  steps: steps,
  snapshot: snapshot,
  reviewedFingerprint: migrationFingerprint(
    version: version,
    name: 'integrity $version',
    engine: Engine.sqlite,
    steps: steps,
    snapshot: snapshot,
  ),
);

MigrationHistory _history(List<Migration> migrations) =>
    MigrationHistory(engine: Engine.sqlite, migrations: migrations);

Future<String> _path() async {
  final directory = await Directory.systemTemp.createTemp(
    'orm-sqlite-integrity-',
  );
  addTearDown(() => directory.delete(recursive: true));
  return '${directory.path}/main.db';
}

Database _open(String path) {
  final database = openDatabase(SqliteDriver.open(path));
  addTearDown(database.close);
  return database;
}

void _withNative(String path, void Function(sqlite.Database) action) {
  final database = sqlite.sqlite3.open(path);
  try {
    action(database);
  } finally {
    database.close();
  }
}

void main() {
  test(
    'preexisting orphan rows reject new markers and roll back new DDL',
    () async {
      final path = await _path();
      _withNative(path, (native) {
        native.execute('PRAGMA foreign_keys = OFF');
        for (final sql in planSchemaChange(
          const SchemaSnapshot(engine: Engine.sqlite, tables: []),
          _relations,
        ).steps) {
          native.execute(sql);
        }
        native.execute('INSERT INTO children VALUES (1, 999)');
        native.execute(
          'CREATE TABLE unmanaged_parent (id INTEGER PRIMARY KEY)',
        );
        native.execute(
          'CREATE TABLE unmanaged_child (parent_id INTEGER REFERENCES unmanaged_parent(id))',
        );
        native.execute('INSERT INTO unmanaged_child VALUES (999)');
      });
      final snapshot = SchemaSnapshot(
        engine: Engine.sqlite,
        tables: [..._relations.tables, _audit],
      );
      final history = _history([
        _migration(1, snapshot, [
          'CREATE TABLE audit (id INTEGER PRIMARY KEY NOT NULL)',
        ]),
      ]);
      var database = _open(path);
      expect((await database.session.run('PRAGMA foreign_keys')).rows, [
        [1],
      ]);
      await expectLater(
        MigrationRunner(database, history).apply(),
        throwsStateError,
      );
      expect(
        (await database.session.run(
          "SELECT name FROM main.sqlite_schema WHERE name IN ('audit', '_orm_migrations')",
        )).rows,
        isEmpty,
      );
      expect((await database.session.run('SELECT * FROM children')).rows, [
        [1, 999],
      ]);
      await database.close();
      database = _open(path);
      await expectLater(
        MigrationRunner(database, history).apply(),
        throwsStateError,
      );
      await database.session.run('INSERT INTO parents VALUES (999)');
      final runner = MigrationRunner(database, history);
      expect(await runner.apply(), [1]);
      expect(await runner.apply(), isEmpty);
      expect(
        (await database.session.run(
          'PRAGMA main.foreign_key_check(unmanaged_child)',
        )).rows,
        hasLength(1),
      );
      await expectLater(
        database.session.run('INSERT INTO children VALUES (2, 123)'),
        throwsException,
      );
      await database.close();
      database = _open(path);
      expect(await MigrationRunner(database, history).apply(), isEmpty);
      expect((await database.session.run('SELECT * FROM children')).rows, [
        [1, 999],
      ]);
    },
  );

  test('orphan rows introduced outside ORM reject resume and preserve saved history', () async {
    final path = await _path();
    final first = _migration(
      1,
      _relations,
      planSchemaChange(
        const SchemaSnapshot(engine: Engine.sqlite, tables: []),
        _relations,
      ).steps,
    );
    var database = _open(path);
    expect(await MigrationRunner(database, _history([first])).apply(), [1]);
    final saved = (await database.session.run(
      'SELECT * FROM main."_orm_migrations"',
    )).rows;
    await database.close();
    _withNative(path, (native) {
      native.execute('PRAGMA foreign_keys = OFF');
      native.execute('INSERT INTO children VALUES (1, 999)');
    });
    final next = SchemaSnapshot(
      engine: Engine.sqlite,
      tables: [..._relations.tables, _audit],
    );
    final history = _history([
      first,
      _migration(2, next, planSchemaChange(_relations, next).steps),
    ]);
    database = _open(path);
    await expectLater(
      MigrationRunner(database, history).apply(),
      throwsStateError,
    );
    expect(
      (await database.session.run('SELECT * FROM main."_orm_migrations"')).rows,
      saved,
    );
    expect(
      (await database.session.run(
        "SELECT name FROM main.sqlite_schema WHERE name = 'audit'",
      )).rows,
      isEmpty,
    );
    expect((await database.session.run('SELECT * FROM children')).rows, [
      [1, 999],
    ]);
    await database.close();
    database = _open(path);
    await expectLater(
      MigrationRunner(database, _history([first])).apply(),
      throwsStateError,
    );
    expect(
      (await database.session.run('SELECT * FROM main."_orm_migrations"')).rows,
      saved,
    );
    await database.session.run('INSERT INTO parents VALUES (999)');
    expect(await MigrationRunner(database, history).apply(), [2]);
  });

  for (final kind in ['table', 'view']) {
    test(
      'temporary $kind cannot satisfy or shadow a persistent table',
      () async {
        final path = await _path();
        var database = _open(path);
        final createTemp = kind == 'table'
            ? 'CREATE TEMP TABLE "UsErS" (id INTEGER PRIMARY KEY NOT NULL)'
            : 'CREATE TEMP VIEW "UsErS" AS SELECT 1 AS id';
        final snapshot = SchemaSnapshot(
          engine: Engine.sqlite,
          tables: [..._users.tables, _audit],
        );
        await expectLater(
          MigrationRunner(
            database,
            _history([
              _migration(1, snapshot, [
                createTemp,
                'CREATE TABLE audit (id INTEGER PRIMARY KEY NOT NULL)',
              ]),
            ]),
          ).apply(),
          throwsStateError,
        );
        expect(
          (await database.session.run(
            "SELECT name FROM main.sqlite_schema WHERE type = 'table'",
          )).rows,
          isEmpty,
        );
        expect(
          (await database.session.run('SELECT name FROM temp.sqlite_schema'))
              .rows,
          isEmpty,
        );
        final first = _migration(
          1,
          _users,
          planSchemaChange(
            const SchemaSnapshot(engine: Engine.sqlite, tables: []),
            _users,
          ).steps,
        );
        expect(await MigrationRunner(database, _history([first])).apply(), [1]);
        await database.session.run('INSERT INTO main.users VALUES (7)');
        await database.session.run(createTemp);
        final saved = (await database.session.run(
          'SELECT * FROM main."_orm_migrations"',
        )).rows;
        final history = _history([
          first,
          _migration(2, snapshot, planSchemaChange(_users, snapshot).steps),
        ]);
        await expectLater(
          MigrationRunner(database, history).apply(),
          throwsStateError,
        );
        expect(
          (await database.session.run('SELECT * FROM main."_orm_migrations"'))
              .rows,
          saved,
        );
        expect((await database.session.run('SELECT * FROM main.users')).rows, [
          [7],
        ]);
        expect(
          (await database.session.run(
            "SELECT name FROM main.sqlite_schema WHERE name = 'audit'",
          )).rows,
          isEmpty,
        );
        await database.close();
        database = _open(path);
        expect(await MigrationRunner(database, history).apply(), [2]);
        expect((await database.session.run('SELECT * FROM users')).rows, [
          [7],
        ]);
      },
    );
  }

  test('attached tables cannot satisfy the main persistent snapshot', () async {
    final path = await _path();
    var database = _open(path);
    await database.session.run(
      'ATTACH DATABASE ? AS external',
      parameters: ['$path.attached'],
    );
    await database.session.run(
      'CREATE TABLE external.users (id INTEGER PRIMARY KEY NOT NULL)',
    );
    await database.session.run('INSERT INTO external.users VALUES (9)');
    final history = _history([_migration(1, _users, [])]);
    await expectLater(
      MigrationRunner(database, history).apply(),
      throwsStateError,
    );
    expect(
      (await database.session.run(
        "SELECT name FROM main.sqlite_schema WHERE type = 'table'",
      )).rows,
      isEmpty,
    );
    expect((await database.session.run('SELECT * FROM external.users')).rows, [
      [9],
    ]);
    await database.close();
    database = _open(path);
    final steps = planSchemaChange(
      const SchemaSnapshot(engine: Engine.sqlite, tables: []),
      _users,
    ).steps;
    expect(
      await MigrationRunner(
        database,
        _history([_migration(1, _users, steps)]),
      ).apply(),
      [1],
    );
    expect((await database.session.run('SELECT * FROM users')).rows, isEmpty);
  });
}
