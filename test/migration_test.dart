import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/migrations/sqlite/history.dart' as shop;

const _id = ColumnDefinition(
  name: 'id',
  field: 'id',
  type: ScalarType.integer,
  primaryKey: true,
  identity: true,
);
const _name = ColumnDefinition(
  name: 'name',
  field: 'name',
  type: ScalarType.text,
  unique: true,
);
const _nickname = ColumnDefinition(
  name: 'nickname',
  field: 'nickname',
  type: ScalarType.text,
  nullable: true,
);

SchemaSnapshot _schema(
  List<ColumnDefinition> columns, {
  Engine engine = Engine.sqlite,
  String table = 'users',
}) => SchemaSnapshot(engine: engine, tables: [TableDefinition(table, columns)]);

Migration _migration(
  int version,
  SchemaSnapshot snapshot,
  List<String> steps, {
  String? fingerprint,
}) => Migration(
  version: version,
  name: 'migration $version',
  engine: snapshot.engine,
  steps: steps,
  snapshot: snapshot,
  reviewedFingerprint:
      fingerprint ??
      migrationFingerprint(
        version: version,
        name: 'migration $version',
        engine: snapshot.engine,
        steps: steps,
        snapshot: snapshot,
      ),
);

MigrationHistory _history(
  List<Migration> migrations, {
  Engine engine = Engine.sqlite,
}) => MigrationHistory(engine: engine, migrations: migrations);

void main() {
  test('fingerprint protects SQL, engine and all frozen schema properties', () {
    final original = _schema([_id, _name]);
    final migration = _migration(1, original, [
      'CREATE TABLE users (id INTEGER)',
    ]);
    expect(migration.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      () => _migration(1, original, [
        'CREATE TABLE users (id TEXT)',
      ], fingerprint: migration.reviewedFingerprint),
      throwsStateError,
    );
    expect(
      () => _migration(
        1,
        _schema([_id, _name, _nickname]),
        migration.steps,
        fingerprint: migration.reviewedFingerprint,
      ),
      throwsStateError,
    );
    expect(
      () => _migration(
        1,
        _schema([_id, _name], engine: Engine.postgresql),
        migration.steps,
        fingerprint: migration.reviewedFingerprint,
      ),
      throwsStateError,
    );
  });

  test('migration deeply copies mutable schema lists and byte defaults', () {
    final bytes = Uint8List.fromList([1, 2]);
    final columns = [
      _id,
      ColumnDefinition(
        name: 'data',
        field: 'data',
        type: ScalarType.bytes,
        defaultValue: bytes,
      ),
    ];
    final tables = [TableDefinition('users', columns)];
    final migration = _migration(
      1,
      SchemaSnapshot(engine: Engine.sqlite, tables: tables),
      [],
    );
    final fingerprint = migration.fingerprint;
    bytes[0] = 9;
    columns.clear();
    tables.clear();
    expect(migration.fingerprint, fingerprint);
    expect(() => migration.snapshot.tables.clear(), throwsUnsupportedError);
    expect(
      () =>
          (migration.snapshot.tables.single.columns[1].defaultValue
                  as Uint8List)[0] =
              3,
      throwsUnsupportedError,
    );
  });

  test('history rejects duplicate, unordered, mixed-engine definitions', () {
    final first = _migration(1, _schema([_id]), []);
    final second = _migration(2, _schema([_id]), []);
    final pg = _migration(3, _schema([_id], engine: Engine.postgresql), []);
    expect(() => _history([first, first]), throwsArgumentError);
    expect(() => _history([second, first]), throwsArgumentError);
    expect(() => _history([first, pg]), throwsArgumentError);
    expect(_history([first, second]).migrations, [first, second]);
  });

  test('planner creates engine SQL and conservatively adds columns', () {
    final empty = SchemaSnapshot(engine: Engine.sqlite, tables: []);
    final initial = _schema([_id, _name]);
    final plan = planSchemaChange(empty, initial);
    expect(
      plan.steps.single,
      contains('"id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL'),
    );
    final next = _schema([
      _id,
      _name,
      _nickname,
      const ColumnDefinition(
        name: 'active',
        field: 'active',
        type: ScalarType.boolean,
        defaultValue: true,
      ),
    ]);
    expect(planSchemaChange(initial, next).steps, [
      'ALTER TABLE "users" ADD COLUMN "nickname" TEXT',
      'ALTER TABLE "users" ADD COLUMN "active" INTEGER NOT NULL DEFAULT 1',
    ]);
    final pg = planSchemaChange(
      const SchemaSnapshot(engine: Engine.postgresql, tables: []),
      _schema([_id], engine: Engine.postgresql),
    );
    expect(
      pg.steps.single,
      contains('BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY NOT NULL'),
    );
  });

  test('planner rejects drops, inferred renames and risky alterations', () {
    final original = _schema([_id, _name]);
    for (final next in [
      _schema([_id]),
      _schema([_id, _name], table: 'accounts'),
      _schema([
        _id,
        const ColumnDefinition(
          name: 'name',
          field: 'name',
          type: ScalarType.integer,
          unique: true,
        ),
      ]),
      _schema([
        _id,
        _name,
        const ColumnDefinition(
          name: 'required',
          field: 'required',
          type: ScalarType.text,
        ),
      ]),
      _schema([
        _id,
        _name,
        const ColumnDefinition(
          name: 'unique',
          field: 'unique',
          type: ScalarType.text,
          nullable: true,
          unique: true,
        ),
      ]),
    ]) {
      expect(() => planSchemaChange(original, next), throwsStateError);
    }
    expect(
      () => planSchemaChange(
        original,
        _schema([_id, _name], engine: Engine.postgresql),
      ),
      throwsArgumentError,
    );
    expect(
      planSchemaChange(
        original,
        _schema([
          _id,
          const ColumnDefinition(
            name: 'name',
            field: 'renamedDartField',
            type: ScalarType.text,
            unique: true,
          ),
        ]),
      ).steps,
      isEmpty,
    );
  });

  group('real SQLite migration runner', () {
    late Database database;
    setUp(() => database = openDatabase(SqliteDriver.memory()));
    tearDown(() => database.close());

    test(
      'static shop history creates five tables independently of models',
      () async {
        final runner = MigrationRunner(database, shop.history);
        expect(await runner.apply(), [1]);
        expect(await runner.apply(), isEmpty);
        expect(
          (await database.session.run(
            "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
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

    test(
      'concurrent calls share the SQLite driver transaction queue',
      () async {
        final runner = MigrationRunner(database, shop.history);
        final results = await Future.wait([runner.apply(), runner.apply()]);
        expect(results, [
          [1],
          <int>[],
        ]);
        expect(
          (await database.session.run('SELECT version FROM "_orm_migrations"'))
              .rows,
          [
            [1],
          ],
        );
      },
    );

    test(
      'applies frozen SQL, backfills defaults and resumes idempotently',
      () async {
        final initial = _schema([_id, _name]);
        final first = _migration(
          1,
          initial,
          planSchemaChange(
            const SchemaSnapshot(engine: Engine.sqlite, tables: []),
            initial,
          ).steps,
        );
        expect(await MigrationRunner(database, _history([first])).apply(), [1]);
        await database.session.run(
          'INSERT INTO "users" ("name") VALUES (?)',
          parameters: ['Ada'],
        );
        final next = _schema([
          _id,
          _name,
          _nickname,
          const ColumnDefinition(
            name: 'active',
            field: 'active',
            type: ScalarType.boolean,
            defaultValue: true,
          ),
        ]);
        final second = _migration(
          2,
          next,
          planSchemaChange(initial, next).steps,
        );
        final runner = MigrationRunner(database, _history([first, second]));
        expect(await runner.apply(), [2]);
        expect(
          (await database.session.run(
            'SELECT name, nickname, active FROM users',
          )).rows.single,
          ['Ada', null, 1],
        );
        expect(await runner.apply(), isEmpty);
      },
    );

    test(
      'catalog mismatch and failed SQL roll back DDL and marker together',
      () async {
        final snapshot = _schema([_id]);
        final first = _migration(1, snapshot, [
          'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL)',
          'INVALID SQL',
        ]);
        await expectLater(
          MigrationRunner(database, _history([first])).apply(),
          throwsA(anything),
        );
        expect(
          (await database.session.run(
            "SELECT name FROM sqlite_schema WHERE name IN ('users', '_orm_migrations')",
          )).rows,
          isEmpty,
        );
        final wrong = _migration(1, snapshot, [
          'CREATE TABLE users (id TEXT PRIMARY KEY NOT NULL)',
        ]);
        await expectLater(
          MigrationRunner(database, _history([wrong])).apply(),
          throwsStateError,
        );
        expect(
          (await database.session.run(
            "SELECT name FROM sqlite_schema WHERE name = 'users'",
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
      },
    );

    test('already applied SQL/schema/name hashes cannot be replaced', () async {
      final snapshot = _schema([_id]);
      final steps = planSchemaChange(
        const SchemaSnapshot(engine: Engine.sqlite, tables: []),
        snapshot,
      ).steps;
      final first = _migration(1, snapshot, steps);
      await MigrationRunner(database, _history([first])).apply();
      final modified = _migration(1, snapshot, ['${steps.single} ']);
      await expectLater(
        MigrationRunner(database, _history([modified])).apply(),
        throwsStateError,
      );
      await expectLater(
        MigrationRunner(database, _history([])).apply(),
        throwsStateError,
      );
      await database.session.run(
        'UPDATE "_orm_migrations" SET "engine" = ?',
        parameters: ['postgresql'],
      );
      await expectLater(
        MigrationRunner(database, _history([first])).apply(),
        throwsStateError,
      );
    });

    test('rejects connection mismatch before creating history table', () async {
      await expectLater(
        MigrationRunner(
          database,
          _history([], engine: Engine.postgresql),
        ).apply(),
        throwsArgumentError,
      );
      expect(
        (await database.session.run(
          "SELECT name FROM sqlite_schema WHERE name = '_orm_migrations'",
        )).rows,
        isEmpty,
      );
    });

    test(
      'detects catalog drift including identity, unique and foreign key',
      () async {
        final snapshot = _schema([_id, _name]);
        for (final sql in [
          'CREATE TABLE users (id INTEGER PRIMARY KEY NOT NULL, name TEXT NOT NULL UNIQUE)',
          'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, name TEXT NOT NULL)',
          'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, name TEXT NOT NULL UNIQUE, extra TEXT)',
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
        final actual = _migration(
          1,
          snapshot,
          planSchemaChange(
            const SchemaSnapshot(engine: Engine.sqlite, tables: []),
            snapshot,
          ).steps,
        );
        await MigrationRunner(database, _history([actual])).apply();
        await database.session.run('ALTER TABLE users ADD COLUMN drift TEXT');
        await expectLater(
          MigrationRunner(database, _history([actual])).apply(),
          throwsStateError,
        );
      },
    );

    test('quoted names, literal defaults and relevant foreign keys survive catalog validation', () async {
      final snapshot = SchemaSnapshot(
        engine: Engine.sqlite,
        tables: [
          const TableDefinition('parent"table', [_id]),
          TableDefinition('child', [
            _id,
            const ColumnDefinition(
              name: 'parent_id',
              field: 'parentId',
              type: ScalarType.integer,
              references: ForeignKey('parent"table', 'id', onDelete: 'cascade'),
            ),
            const ColumnDefinition(
              name: 'text',
              field: 'text',
              type: ScalarType.text,
              defaultValue: "O'Reilly",
            ),
            ColumnDefinition(
              name: 'created',
              field: 'created',
              type: ScalarType.dateTime,
              defaultValue: DateTime.utc(2026, 10, 9),
            ),
            ColumnDefinition(
              name: 'bytes',
              field: 'bytes',
              type: ScalarType.bytes,
              defaultValue: Uint8List.fromList([1, 255]),
            ),
          ]),
        ],
      );
      final steps = planSchemaChange(
        const SchemaSnapshot(engine: Engine.sqlite, tables: []),
        snapshot,
      ).steps;
      await MigrationRunner(
        database,
        _history([_migration(1, snapshot, steps)]),
      ).apply();
      await database.session.run('INSERT INTO "parent""table" DEFAULT VALUES');
      await database.session.run(
        'INSERT INTO child (parent_id) VALUES (?)',
        parameters: [1],
      );
      expect(
        (await database.session.run('SELECT text, created, bytes FROM child'))
            .rows
            .single,
        [
          "O'Reilly",
          '2026-10-09T00:00:00.000Z',
          [1, 255],
        ],
      );
      final invalidSteps = [
        steps.first,
        steps.last.replaceFirst('ON DELETE CASCADE', 'ON DELETE RESTRICT'),
      ];
      final other = openDatabase(SqliteDriver.memory());
      try {
        await expectLater(
          MigrationRunner(
            other,
            _history([_migration(1, snapshot, invalidSteps)]),
          ).apply(),
          throwsStateError,
        );
      } finally {
        await other.close();
      }
    });

    test('explicit drops are checked against old snapshots', () async {
      final before = _schema([_id]);
      final first = _migration(
        1,
        before,
        planSchemaChange(
          const SchemaSnapshot(engine: Engine.sqlite, tables: []),
          before,
        ).steps,
      );
      await MigrationRunner(database, _history([first])).apply();
      const empty = SchemaSnapshot(engine: Engine.sqlite, tables: []);
      await expectLater(
        MigrationRunner(
          database,
          _history([first, _migration(2, empty, [])]),
        ).apply(),
        throwsStateError,
      );
      expect(
        await MigrationRunner(
          database,
          _history([
            first,
            _migration(2, empty, ['DROP TABLE "users"']),
          ]),
        ).apply(),
        [2],
      );
    });

    test(
      'identity words in defaults cannot hide a missing AUTOINCREMENT',
      () async {
        final snapshot = _schema([
          _id,
          const ColumnDefinition(
            name: 'note',
            field: 'note',
            type: ScalarType.text,
            defaultValue: 'AUTOINCREMENT',
          ),
        ]);
        await expectLater(
          MigrationRunner(
            database,
            _history([
              _migration(1, snapshot, [
                "CREATE TABLE users (id INTEGER PRIMARY KEY NOT NULL, note TEXT NOT NULL DEFAULT 'AUTOINCREMENT')",
              ]),
            ]),
          ).apply(),
          throwsStateError,
        );
      },
    );

    test(
      'text primary key must enforce its frozen NOT NULL boundary',
      () async {
        final snapshot = _schema([
          const ColumnDefinition(
            name: 'id',
            field: 'id',
            type: ScalarType.text,
            primaryKey: true,
          ),
        ]);
        await expectLater(
          MigrationRunner(
            database,
            _history([
              _migration(1, snapshot, [
                'CREATE TABLE users (id TEXT PRIMARY KEY)',
              ]),
            ]),
          ).apply(),
          throwsStateError,
        );
        expect(
          await MigrationRunner(
            database,
            _history([
              _migration(1, snapshot, [
                'CREATE TABLE users (id TEXT PRIMARY KEY NOT NULL)',
              ]),
            ]),
          ).apply(),
          [1],
        );
        await expectLater(
          database.session.run(
            'INSERT INTO users (id) VALUES (?)',
            parameters: [null],
          ),
          throwsA(anything),
        );
      },
    );

    test(
      'unmodeled unique index shapes reject while nonunique indexes survive',
      () async {
        final snapshot = _schema([
          _id,
          const ColumnDefinition(
            name: 'name',
            field: 'name',
            type: ScalarType.text,
          ),
          const ColumnDefinition(
            name: 'age',
            field: 'age',
            type: ScalarType.integer,
          ),
        ]);
        final create = planSchemaChange(
          const SchemaSnapshot(engine: Engine.sqlite, tables: []),
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
              "SELECT name FROM sqlite_schema WHERE name = 'users'",
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
  });
}
