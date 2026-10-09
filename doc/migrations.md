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
schema. The internal `_orm_migrations` table must also have the required column
types, nullability and primary key; an incompatible preexisting table is rejected
before application migration SQL runs. Pending DDL, catalog validation and
history markers share one transaction.
Each marker insertion must affect one row. When applying new versions, the
runner reads the complete history back before committing; suppressed, deleted
or rewritten markers roll back the invocation, including application DDL.
PostgreSQL flushes deferred constraint triggers before this readback.
The final catalog check follows marker triggers and also verifies the internal
history-table structure, so a trigger cannot record success for a changed schema.
Failures roll back the invocation. Already applied histories are verified;
modified or missing historical entries fail. PostgreSQL runners take a
transaction advisory lock. SQLite runners sharing one owned driver use its FIFO
queue; separate native handles can fail with SQLITE_BUSY and need an application
retry policy.

The driver's fixed schema identifies both managed tables and the history table:
SQLite uses `main`; PostgreSQL uses its configured schema, which must already
exist. PostgreSQL migration transactions set that schema first and `pg_temp`
last in a local `search_path`; connection settings are restored at transaction
completion. Typed queries qualify the schema directly on every pooled connection.

## Preparing a new migration

Draft the initial migration from a generated snapshot:

```sh
dart run orm migration draft --to lib/models.snapshot.dart --out lib/migrations/v001_initial.dart --version 1 --name initial
```

For later changes, pass the previous historical definition as `--from`:

```sh
dart run orm migration draft --from lib/migrations/v001_initial.dart --to lib/models.snapshot.dart --out lib/migrations/v002_add_nickname.dart --version 2 --name add_nickname
```

The command reads the constant schema without executing either input file. It
copies the complete frozen schema, engine SQL and a literal fingerprint into one
standalone Dart draft. It never overwrites an existing file or infers a rename.
Review its SQL and effects on existing data before committing it, then add one
static import and one entry to your history. A computed hash records the draft's
contents; review is still your responsibility.

Draft input needs `const frozenSchema`, or one unambiguous top-level constant
`SchemaSnapshot` in the file. Literal string, number and boolean defaults are
supported. An unchanged schema has nothing to draft. Unsupported transitions
still require an explicitly authored migration.
String defaults containing NUL are rejected before generating SQL or replacing
output files, since neither engine accepts NUL in a SQL statement.

To author a migration directly:

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
or backups. Draft generation never infers renames or applies SQL.
Never compute an old migration's reviewed hash dynamically at startup, or import
the current application's snapshot into a historical definition.

The runner manages the tables listed in its snapshots and checks historical
removed tables. Other tables in the database are outside that history. Catalog
verification covers columns, storage types, nullability, single-column primary
keys, identity, single-column unique constraints and foreign keys, and literal
defaults. PostgreSQL foreign keys must be enforced and validated, with their
internal checks and parent actions enabled for ordinary application sessions
and the current migration session. Disabled or replica-only constraint triggers
are rejected. This checks current enforcement configuration; it does not scan
PostgreSQL rows for violations introduced while checks were previously disabled.
Unique indexes must be valid, ready and immediate, so typed unique-key claims can
use them.
Managed tables must be persistent; temporary table or view shadows are rejected
on the connection applying migrations. PostgreSQL requires permanent logged,
non-partitioned tables; unlogged tables, partitioned roots and individual
partitions are unsupported. Primary keys must enforce non-null
values. SQLite also checks existing foreign-key rows in managed tables, including
when resuming a history. Those checks inspect data as well as catalog metadata.
Deferrable unique constraints and unfinished constraint/index builds cannot be
recorded as matching the frozen schema. Composite constraints are unsupported.
Arbitrary non-unique indexes, triggers and check constraints are not represented
in the current snapshot API.
