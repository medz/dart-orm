# Reviewed migrations in Dart

A migration history fixes one database engine. Each saved migration contains
that engine's SQL, the complete frozen physical schema after it, and a literal
reviewed fingerprint. Historical files import only public ORM metadata; they
remain independent of current model classes and generated snapshots.

The complete examples have separate histories:

- [SQLite](../example/migrations/sqlite/history.dart)
- [PostgreSQL](../example/migrations/postgres/history.dart)

```dart
import 'package:orm/migration.dart';
import 'migrations/sqlite/history.dart' as migrations;

await MigrationRunner(db.database, migrations.history).apply();
```

The runner checks the connection engine before DDL. It verifies saved versions,
names and fingerprints, then checks the actual catalog against the last frozen
schema. Pending DDL, catalog validation and history markers share one transaction.
Failures roll back the invocation. Already applied histories are verified;
modified or missing historical entries fail. PostgreSQL runners take a
transaction advisory lock. SQLite runners sharing one owned driver use its FIFO
queue; separate native handles can fail with SQLITE_BUSY and need an application
retry policy.

## Preparing a new migration

1. Generate the current engine's `models.snapshot.dart`.
2. Compare the last historical snapshot with the new snapshot using
   `planSchemaChange(before, after)`.
3. Save a new Dart file containing the returned steps and a **copied** frozen
   snapshot. Review every SQL statement and its effects on existing data.
4. Calculate `migrationFingerprint` over that definition and save the hash as a
   literal `reviewedFingerprint`. Register it with a static import in history.

`planSchemaChange` is a pure API. It creates new tables and adds nullable columns
or columns with a supported literal default. It rejects drops, renames, type,
identity and constraint changes. Author such SQL explicitly after reviewing the
engine behavior; a new snapshot still describes its final managed schema.
Destructive renames are never inferred.

```dart
final plan = planSchemaChange(previousSnapshot, newSnapshot);
for (final sql in plan.steps) {
  print(sql); // Review before saving.
}
final fingerprint = migrationFingerprint(
  version: 2,
  name: 'add_nickname',
  engine: newSnapshot.engine,
  steps: plan.steps,
  snapshot: newSnapshot,
);
print(fingerprint); // Paste the reviewed literal into the new historical file.
```

A saved definition looks like
[the SQLite initial migration](../example/migrations/sqlite/v001_initial.dart).
Keep a static registry:

```dart
import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'v001_initial.dart' as v001;
import 'v002_add_nickname.dart' as v002;

final history = MigrationHistory(
  engine: Engine.sqlite,
  migrations: [v001.migration, v002.migration],
);
```

Versions are positive and strictly increasing; gaps are allowed. Do not sort or
edit old entries to reconcile drift. Fix a deployed schema with a new reviewed
migration. A fingerprint detects source changes; it does not replace SQL review
or backups. There is no automatic migration file writer or rename inference.
Never compute an old migration's reviewed hash dynamically at startup, or import
the current application's snapshot into a historical definition.

The runner manages the tables listed in its snapshots and checks historical
removed tables. Other tables in the database are outside that history. Catalog
verification covers columns, storage types, nullability, single-column primary
keys, identity, single-column unique constraints and foreign keys, and literal
defaults. Composite constraints are unsupported. Arbitrary non-unique indexes,
triggers and check constraints are not represented in the current snapshot API.
