import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';
import 'package:test/test.dart';

import '../example/migrations/postgres/history.dart' as postgres;
import '../example/migrations/sqlite/history.dart' as sqlite;
import 'support/database.dart';

Migration _migration(int version, SchemaSnapshot snapshot, List<String> steps) {
  final name = 'identity history $version';
  return Migration(
    version: version,
    name: name,
    engine: snapshot.engine,
    steps: steps,
    snapshot: snapshot,
    reviewedFingerprint: migrationFingerprint(
      version: version,
      name: name,
      engine: snapshot.engine,
      steps: steps,
      snapshot: snapshot,
    ),
  );
}

SchemaSnapshot _userAliases(
  SchemaSnapshot base,
  String tableName,
  String keyName,
) => SchemaSnapshot(
  engine: base.engine,
  tables: [
    for (final table in base.tables)
      TableDefinition(table.name == 'users' ? tableName : table.name, [
        for (final column in table.columns)
          ColumnDefinition(
            name: table.name == 'users' && column.name == 'id'
                ? keyName
                : column.name,
            field: column.field,
            type: column.type,
            nullable: column.nullable,
            primaryKey: column.primaryKey,
            identity: column.identity,
            unique: column.unique,
            defaultValue: column.defaultValue,
            references: column.references?.table == 'users'
                ? ForeignKey(
                    tableName,
                    keyName,
                    onDelete: column.references!.onDelete,
                  )
                : column.references,
          ),
      ]),
  ],
);

void main() {
  test(
    'SQLite consecutive casing-only snapshots keep one table and its data',
    () async {
      final fixture = await openTestDatabase(Engine.sqlite);
      addTearDown(fixture.db.close);
      final initial = sqlite.history;
      final before = initial.migrations.last.snapshot;
      final upper = _userAliases(before, 'Users', 'ID');
      final lower = _userAliases(before, 'users', 'id');
      final upperPlan = planSchemaChange(before, upper);
      final lowerPlan = planSchemaChange(upper, lower);
      expect(upperPlan.steps, isEmpty);
      expect(lowerPlan.steps, isEmpty);
      final adoptUpper = _migration(2, upper, upperPlan.steps);
      final adoptLower = _migration(3, lower, lowerPlan.steps);
      expect(adoptUpper.snapshot.tables.first.name, 'Users');
      expect(adoptUpper.snapshot.tables.first.columns.first.name, 'ID');
      expect(adoptUpper.fingerprint, isNot(adoptLower.fingerprint));
      final user = await fixture.db.users.create(username: 'retained', age: 31);
      final post = await fixture.db.posts.create(
        authorId: user.id,
        title: 'retained post',
      );
      final upperHistory = MigrationHistory(
        engine: Engine.sqlite,
        migrations: [...initial.migrations, adoptUpper],
      );
      expect(await MigrationRunner(fixture.db.database, upperHistory).apply(), [
        2,
      ]);
      expect(
        await MigrationRunner(fixture.db.database, upperHistory).apply(),
        isEmpty,
      );
      final full = MigrationHistory(
        engine: Engine.sqlite,
        migrations: [...upperHistory.migrations, adoptLower],
      );
      expect(await MigrationRunner(fixture.db.database, full).apply(), [3]);
      expect(await MigrationRunner(fixture.db.database, full).apply(), isEmpty);
      expect((await fixture.db.users.get(user.id))?.username, 'retained');
      expect((await fixture.db.posts.get(post.id))?.authorId, user.id);
      final markers = await fixture.db.session.run(
        'SELECT version, fingerprint FROM _orm_migrations ORDER BY version',
      );
      expect(markers.rows.last, [3, adoptLower.fingerprint]);
    },
  );

  test(
    'PostgreSQL casing change requires the old physical table to be dropped',
    () async {
      final fixture = await openTestDatabase(Engine.postgresql);
      addTearDown(fixture.db.close);
      final initial = postgres.history;
      final before = initial.migrations.last.snapshot;
      const id = ColumnDefinition(
        name: 'id',
        field: 'id',
        type: ScalarType.integer,
        primaryKey: true,
      );
      final upper = SchemaSnapshot(
        engine: Engine.postgresql,
        tables: [
          ...before.tables,
          const TableDefinition('CaseUsers', [id]),
        ],
      );
      final lower = SchemaSnapshot(
        engine: Engine.postgresql,
        tables: [
          ...before.tables,
          const TableDefinition('caseusers', [id]),
        ],
      );
      final create = _migration(
        2,
        upper,
        planSchemaChange(before, upper).steps,
      );
      final created = MigrationHistory(
        engine: Engine.postgresql,
        migrations: [...initial.migrations, create],
      );
      expect(await MigrationRunner(fixture.db.database, created).apply(), [2]);
      await fixture.db.session.run('INSERT INTO "CaseUsers" (id) VALUES (7)');
      fixture.events.clear();
      expect(() => planSchemaChange(upper, lower), throwsStateError);
      final upperColumn = SchemaSnapshot(
        engine: Engine.postgresql,
        tables: [
          ...before.tables,
          const TableDefinition('CaseUsers', [
            ColumnDefinition(
              name: 'ID',
              field: 'id',
              type: ScalarType.integer,
              primaryKey: true,
            ),
          ]),
        ],
      );
      expect(() => planSchemaChange(upper, upperColumn), throwsStateError);
      expect(fixture.events, isEmpty);
      final incomplete = _migration(3, lower, [
        'CREATE TABLE "caseusers" (id BIGINT PRIMARY KEY NOT NULL)',
      ]);
      await expectLater(
        MigrationRunner(
          fixture.db.database,
          MigrationHistory(
            engine: Engine.postgresql,
            migrations: [...created.migrations, incomplete],
          ),
        ).apply(),
        throwsStateError,
      );
      expect(
        (await fixture.db.session.run('SELECT id FROM "CaseUsers"')).rows,
        [
          [7],
        ],
      );
      expect(
        (await fixture.db.session.run("SELECT to_regclass('caseusers')")).rows,
        [
          [null],
        ],
      );
      expect(
        (await fixture.db.session.run(
          'SELECT max(version) FROM _orm_migrations',
        )).rows,
        [
          [2],
        ],
      );
      final drop = _migration(3, lower, [
        'DROP TABLE "CaseUsers"',
        'CREATE TABLE "caseusers" (id BIGINT PRIMARY KEY NOT NULL)',
      ]);
      final full = MigrationHistory(
        engine: Engine.postgresql,
        migrations: [...created.migrations, drop],
      );
      expect(await MigrationRunner(fixture.db.database, full).apply(), [3]);
      expect(await MigrationRunner(fixture.db.database, full).apply(), isEmpty);
      expect(
        (await fixture.db.session.run('SELECT id FROM "caseusers"')).rows,
        isEmpty,
      );
    },
    skip: !hasPostgres ? 'Requires a disposable PostgreSQL instance.' : false,
  );
}
