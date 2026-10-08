import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';
import 'package:test/test.dart';

import 'support/database.dart';

MigrationHistory _history(Engine engine) {
  final snapshot = SchemaSnapshot(
    engine: engine,
    tables: [
      const TableDefinition('history_probe', [
        ColumnDefinition(
          name: 'id',
          field: 'id',
          type: ScalarType.integer,
          primaryKey: true,
        ),
      ]),
    ],
  );
  final plan = planSchemaChange(
    SchemaSnapshot(engine: engine, tables: const []),
    snapshot,
  );
  return MigrationHistory(
    engine: engine,
    migrations: [
      Migration(
        version: 1,
        name: 'history integrity',
        engine: engine,
        steps: plan.steps,
        snapshot: snapshot,
        reviewedFingerprint: migrationFingerprint(
          version: 1,
          name: 'history integrity',
          engine: engine,
          steps: plan.steps,
          snapshot: snapshot,
        ),
      ),
    ],
  );
}

void main() {
  for (final engine in Engine.values) {
    final integer = engine == Engine.sqlite ? 'INTEGER' : 'BIGINT';
    final invalidDefinitions = {
      'text version': 'version TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL',
      'missing primary key': 'version $integer NOT NULL, name TEXT NOT NULL',
      'nullable name': 'version $integer PRIMARY KEY NOT NULL, name TEXT',
      'extra column':
          'version $integer PRIMARY KEY NOT NULL, name TEXT NOT NULL, extra TEXT',
    };
    for (final entry in invalidDefinitions.entries) {
      test(
        '${engine.name} rejects history table ${entry.key} before migration SQL',
        () async {
          final fixture = await openTestDatabase(engine);
          addTearDown(fixture.db.close);
          final session = fixture.db.session;
          await session.run('DROP TABLE "_orm_migrations"');
          await session.run(
            'CREATE TABLE "_orm_migrations" (${entry.value}, engine TEXT NOT NULL, fingerprint TEXT NOT NULL)',
          );
          fixture.events.clear();
          final runner = MigrationRunner(fixture.db.database, _history(engine));
          await expectLater(runner.apply(), throwsStateError);
          expect(
            fixture.statements.any(
              (event) => event.sql.startsWith('CREATE TABLE "history_probe"'),
            ),
            isFalse,
          );
          expect(
            (await session.run('SELECT * FROM "_orm_migrations"')).rows,
            isEmpty,
          );
          // The rejected preexisting table survives rollback. Removing it lets
          // the runner create its own exact structure and resume reliably.
          await session.run('DROP TABLE "_orm_migrations"');
          expect(await runner.apply(), [1]);
          expect(await runner.apply(), isEmpty);
          expect(
            (await session.run('SELECT version FROM "_orm_migrations"')).rows,
            [
              [1],
            ],
          );
        },
        skip: engine == Engine.postgresql && !hasPostgres
            ? 'Requires a disposable PostgreSQL instance.'
            : false,
      );
    }
  }
}
