import 'package:orm/database.dart';
import 'package:orm/schema.dart';

import 'catalog.dart';
import 'definition.dart';

/// Applies a static migration history through the database's owned transaction.
///
/// The engine and every persisted fingerprint are checked before executing DDL.
/// Pending SQL, catalog verification and history markers commit together. A
/// failure rolls back the whole invocation, including newly created tables.
/// Already-applied history is verified against both source and the live catalog.
/// An existing internal history table must have the exact required structure;
/// incompatible tables are rejected before application migration SQL runs.
/// PostgreSQL callers on the same database/schema serialize through an advisory
/// transaction lock at read-committed isolation, including first-time creation.
/// SQLite uses the driver's queue and an immediate serializable transaction.
final class MigrationRunner {
  const MigrationRunner(this.database, this.history);

  final Database database;
  final MigrationHistory history;

  /// Returns the versions applied by this invocation, in registration order.
  Future<List<int>> apply() async {
    if (database.session.engine != history.engine) {
      throw ArgumentError('Migration history and database engines differ.');
    }
    return database.transaction(
      (session) async {
        if (session.engine == Engine.postgresql) {
          // Serialize the first CREATE as well as later history reads. A table
          // lock alone cannot protect two callers before that table exists.
          await session.run(
            "SELECT pg_advisory_xact_lock(hashtextextended(current_database() || ':' || current_schema() || ':orm_migrations', 0))",
          );
        }
        final versionType = session.engine == Engine.sqlite
            ? 'INTEGER'
            : 'BIGINT';
        await session.run(
          'CREATE TABLE IF NOT EXISTS "_orm_migrations" ("version" $versionType PRIMARY KEY NOT NULL, "name" TEXT NOT NULL, "engine" TEXT NOT NULL, "fingerprint" TEXT NOT NULL)',
        );
        await verifyCatalog(
          session,
          SchemaSnapshot(engine: session.engine, tables: _historyTables),
          const {},
        );
        final saved = await session.run(
          'SELECT "version", "name", "engine", "fingerprint" FROM "_orm_migrations" ORDER BY "version"',
        );
        if (saved.rows.length > history.migrations.length) {
          throw StateError(
            'Database contains migrations absent from the registered history.',
          );
        }
        for (var i = 0; i < saved.rows.length; i++) {
          final row = saved.rows[i];
          final expected = history.migrations[i];
          if (row[0] != expected.version ||
              row[1] != expected.name ||
              row[2] != history.engine.name ||
              row[3] != expected.fingerprint) {
            throw StateError(
              'Applied migration history differs from the reviewed Dart definitions.',
            );
          }
        }
        final versions = <int>[];
        final knownTables = <String>{};
        SchemaSnapshot? previous;
        for (var i = 0; i < saved.rows.length; i++) {
          previous = history.migrations[i].snapshot;
          knownTables.addAll(
            previous.tables.map(
              (t) => physicalIdentity(session.engine, t.name),
            ),
          );
        }
        if (previous != null) {
          await verifyCatalog(
            session,
            previous,
            knownTables.difference(
              previous.tables
                  .map((t) => physicalIdentity(session.engine, t.name))
                  .toSet(),
            ),
          );
        }
        for (final migration in history.migrations.skip(saved.rows.length)) {
          for (final step in migration.steps) {
            await session.run(step);
          }
          final names = migration.snapshot.tables
              .map((t) => physicalIdentity(session.engine, t.name))
              .toSet();
          await verifyCatalog(
            session,
            migration.snapshot,
            knownTables.difference(names),
          );
          final placeholders = session.engine == Engine.sqlite
              ? '?, ?, ?, ?'
              : '\$1, \$2, \$3, \$4';
          await session.run(
            'INSERT INTO "_orm_migrations" ("version", "name", "engine", "fingerprint") VALUES ($placeholders)',
            parameters: [
              migration.version,
              migration.name,
              history.engine.name,
              migration.fingerprint,
            ],
          );
          versions.add(migration.version);
          knownTables.addAll(names);
        }
        return List<int>.unmodifiable(versions);
      },
      isolation: history.engine == Engine.postgresql
          ? Isolation.readCommitted
          : Isolation.serializable,
    );
  }
}

const _historyTables = [
  TableDefinition('_orm_migrations', [
    ColumnDefinition(
      name: 'version',
      field: 'version',
      type: ScalarType.integer,
      primaryKey: true,
    ),
    ColumnDefinition(name: 'name', field: 'name', type: ScalarType.text),
    ColumnDefinition(name: 'engine', field: 'engine', type: ScalarType.text),
    ColumnDefinition(
      name: 'fingerprint',
      field: 'fingerprint',
      type: ScalarType.text,
    ),
  ]),
];
