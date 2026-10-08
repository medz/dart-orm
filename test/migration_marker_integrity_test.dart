import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/query.dart' show quoteIdentifier;
import 'package:orm/schema.dart';
import 'package:test/test.dart';

import '../example/migrations/postgres/history.dart' as postgres;
import '../example/migrations/sqlite/history.dart' as sqlite;
import 'support/database.dart';

MigrationHistory _history(Engine engine) {
  final initial = engine == Engine.sqlite ? sqlite.history : postgres.history;
  final migrations = [...initial.migrations];
  var before = initial.migrations.last.snapshot;
  for (final version in [2, 3]) {
    final after = SchemaSnapshot(
      engine: engine,
      tables: [
        ...before.tables,
        TableDefinition('marker_$version', const [
          ColumnDefinition(
            name: 'id',
            field: 'id',
            type: ScalarType.integer,
            primaryKey: true,
          ),
        ]),
      ],
    );
    final steps = planSchemaChange(before, after).steps;
    migrations.add(
      Migration(
        version: version,
        name: 'marker integrity $version',
        engine: engine,
        steps: steps,
        snapshot: after,
        reviewedFingerprint: migrationFingerprint(
          version: version,
          name: 'marker integrity $version',
          engine: engine,
          steps: steps,
          snapshot: after,
        ),
      ),
    );
    before = after;
  }
  return MigrationHistory(engine: engine, migrations: migrations);
}

Future<void> _installTrigger(Session session, String kind) async {
  final schema = quoteIdentifier(session.schema);
  final marker = '$schema."_orm_migrations"';
  final timing = kind == 'suppress' ? 'BEFORE' : 'AFTER';
  if (session.engine == Engine.sqlite) {
    final action = switch (kind) {
      'suppress' => 'SELECT RAISE(IGNORE);',
      'delete' => 'DELETE FROM "_orm_migrations" WHERE version = NEW.version;',
      _ =>
        'UPDATE "_orm_migrations" SET name = \'tampered\' WHERE version = 1;',
    };
    await session.run(
      'CREATE TRIGGER $schema.marker_tamper $timing INSERT ON $marker WHEN NEW.version = 3 BEGIN $action END',
    );
  } else {
    final action = switch (kind) {
      'suppress' => 'RETURN NULL;',
      'delete' ||
      'deferred delete' => 'DELETE FROM $marker WHERE version = NEW.version;',
      _ => 'UPDATE $marker SET name = \'tampered\' WHERE version = 1;',
    };
    await session.run('''
CREATE FUNCTION $schema.marker_tamper() RETURNS trigger LANGUAGE plpgsql AS \$marker\$
BEGIN
  IF NEW.version = 3 THEN $action END IF;
  RETURN NEW;
END
\$marker\$
''');
    final deferred = kind == 'deferred delete';
    await session.run(
      'CREATE ${deferred ? 'CONSTRAINT ' : ''}TRIGGER marker_tamper $timing INSERT ON $marker ${deferred ? 'DEFERRABLE INITIALLY DEFERRED ' : ''}FOR EACH ROW EXECUTE FUNCTION $schema.marker_tamper()',
    );
  }
}

void main() {
  for (final engine in Engine.values) {
    for (final kind in [
      'suppress',
      'delete',
      'rewrite',
      if (engine == Engine.postgresql) 'deferred delete',
    ]) {
      test(
        '${engine.name} $kind marker trigger rolls back pending migrations and preserves saved history',
        () async {
          final fixture = await openTestDatabase(engine);
          addTearDown(fixture.db.close);
          final session = fixture.db.session;
          final schema = quoteIdentifier(session.schema);
          final marker = '$schema."_orm_migrations"';
          final readHistory =
              'SELECT "version", "name", "engine", "fingerprint" FROM $marker ORDER BY "version"';
          final prefix = (await session.run(readHistory)).rows;
          final history = _history(engine);
          final runner = MigrationRunner(fixture.db.database, history);
          await _installTrigger(session, kind);
          fixture.events.clear();
          await expectLater(runner.apply(), throwsStateError);
          expect(
            fixture.statements
                .where((event) => event.sql == readHistory)
                .length,
            kind == 'suppress' ? 1 : 2,
          );
          expect((await session.run(readHistory)).rows, prefix);
          final pendingTables = engine == Engine.sqlite
              ? await session.run(
                  "SELECT name FROM main.sqlite_schema WHERE type = 'table' AND name IN ('marker_2', 'marker_3')",
                )
              : await session.run(
                  "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = \$1 AND tablename IN ('marker_2', 'marker_3')",
                  parameters: [session.schema],
                );
          expect(pendingTables.rows, isEmpty);
          await session.run(
            engine == Engine.sqlite
                ? 'DROP TRIGGER $schema.marker_tamper'
                : 'DROP TRIGGER marker_tamper ON $marker',
          );
          fixture.events.clear();
          expect(await runner.apply(), [2, 3]);
          expect(
            fixture.statements
                .where((event) => event.sql == readHistory)
                .length,
            2,
          );
          expect(
            fixture.statements
                .where((event) => event.sql == 'SET CONSTRAINTS ALL IMMEDIATE')
                .length,
            engine == Engine.postgresql ? 1 : 0,
          );
          expect((await session.run(readHistory)).rows, [
            for (final migration in history.migrations)
              [
                migration.version,
                migration.name,
                engine.name,
                migration.fingerprint,
              ],
          ]);
          fixture.events.clear();
          expect(await runner.apply(), isEmpty);
          expect(
            fixture.statements
                .where((event) => event.sql == readHistory)
                .length,
            1,
          );
          expect(
            fixture.statements.any(
              (event) => event.sql == 'SET CONSTRAINTS ALL IMMEDIATE',
            ),
            isFalse,
          );
        },
        skip: engine == Engine.postgresql && !hasPostgres
            ? 'Requires a disposable PostgreSQL instance.'
            : false,
      );
    }
  }
}
