# Migrations

Schema snapshots, saved migrations and their registry are Dart libraries. Generate
current physical facts separately from the application client:

```sh
dart run orm generate lib/schema.dart
# Creates lib/schema.orm.dart and lib/schema.snapshot.dart.
dart run orm migration registry migrations
```

Create `bin/migrate.dart` once:

```dart
import 'package:orm/migrate_cli.dart';
import 'package:orm/sqlite.dart';
import '../lib/schema.snapshot.dart';
import '../migrations/migrations.g.dart';

Future<void> main(List<String> args) => runMigrationCli(
  args,
  directory: 'migrations',
  history: migrationHistory,
  schema: schema,
  connect: ({required readOnly}) => sqlite(
    readOnly
        ? const SqliteOptions.readOnly('app.sqlite')
        : const SqliteOptions.file('app.sqlite'),
  ),
);
```

Run from the project root. Connections, schema, renames and conversions are
ordinary typed Dart configuration; no schema or migration JSON loader is involved.
For PostgreSQL, import `dart:io` and `package:orm/postgres.dart` and provide
`connect: ({required readOnly}) => postgres(PostgresOptions(url:
Uri.parse(Platform.environment['DATABASE_URL']!), schema: 'public'))`.
TLS defaults to certificate verification. SQLite inspection commands require an
existing read-only file; `apply` can create one. Offline commands never call the
connection factory. Database migration/verification operations enforce their own
transaction and locking boundaries.

```sh
dart run bin/migrate.dart create 0001_initial
dart run bin/migrate.dart check
dart run bin/migrate.dart apply
dart run bin/migrate.dart plan
dart run bin/migrate.dart status
dart run bin/migrate.dart verify
dart run bin/migrate.dart inspect users
```

Each new migration is an `m<id>.dart` file with fixed operations, an independent
historical schema and a recorded `migrationChecksum`. The adjacent
`migrations.g.dart` statically imports these definitions. Check both into Git.
The current `.snapshot.dart` contains only physical database metadata and imports
no application models, codec callbacks or Flutter libraries.

`create` compares the current physical schema with the last historical snapshot
and freezes the resulting SQL/steps in a new Dart file. It does not execute DDL.
No-change generation writes no migration. Repeated IDs, overwritten files, stale
registries and broken history chains are rejected when saving a new migration.
`check` validates the compiled history, fixed fingerprints and common supported
dialects without connecting. Rebuilding the registry only updates imports; it
never refreshes fingerprints. All registered migrations must support at least one
common dialect. A PostgreSQL-only checked operation therefore narrows the history
to PostgreSQL.

Edit the latest **unpublished** migration when a generated change needs a reviewed
backfill or manual SQL, then run `dart run bin/migrate.dart record 0002_name`.
This explicit command updates its fingerprint while preserving the surrounding
source. It cannot know whether a migration was deployed. Never edit or re-record
an applied migration: database history also records checksums and rejects the
change. Add a new migration instead. Earlier historical files remain fixed even
when the current application model changes.

Declare physical renames in the entrypoint's `renames` argument:

```dart
renames: const SchemaRenames(
  tables: {'users': 'members'},
  columns: {'members': {'nickname': 'display_name'}},
),
```

Declare conversions in its `using` argument, keyed by dialect, table and column:

```dart
using: {
  SqlDialect.sqlite: {'members': {'score': 'CAST(score AS TEXT)'}},
  SqlDialect.postgres: {'members': {'score': 'CAST(score AS TEXT)'}},
},
```

Import `package:orm/migrate.dart` for `SchemaRenames`. Renames and conversions are
inputs to the next `create`; remove them after generating that change. Pass
`create <id> --allow-destructive` to generate reviewed drop steps. Neither offline
checking nor generation applies them.

Start with [catalog import](importing.md) for an existing database, then run
`baseline` to verify and register its final historical schema without replaying
creation SQL. Commands return JSON reports (not migration artifacts). Exit code 2
indicates catalog drift, 64 invalid CLI arguments, and 1 an execution failure.
Dart's launcher may print build-hook progress on stderr.

Application startup uses the same static history without the CLI/tooling imports:

```dart
import 'migrations/migrations.g.dart';

final migrations = migrationHistory.checked;
final pending = await Migrator(db).plan(migrations);
final appliedIds = await Migrator(db).apply(migrations);
```

For programmatic generation, `writeMigration(migration, directory: 'migrations',
history: migrationHistory)` saves fixed Dart operations and the registry.
`migrationSource`, `schemaSource` and `migrationHistorySource` also return Dart
source without writing files. A saved migration contains frozen SQL and typed
steps; it must not call `Migration.diff` against current models when it runs.
Fingerprints cover SQL, operation data, historical schema and predecessor, while
formatting and comments do not affect them.

`apply` runs a pending batch without `CheckedSql` or `Backfill` in one transaction. A failed copy, required
column, unique constraint, or foreign key rolls back earlier steps and history
records from that invocation. PostgreSQL uses a dedicated connection and a session advisory lock scoped to the
current database/schema; SQLite obtains an immediate write transaction. PostgreSQL
lock acquisition uses short `pg_try_advisory_lock` queries outside a transaction,
with `Migrator(db, lockTimeout: ...)` defaulting to 30 seconds. Waiting does not
hold an old SQL snapshot that could deadlock concurrent index creation.
Migration planning checks applied history and checksums. Catalog verification is
an explicit separate operation; SQL history alone does not prove schema equality.

## Deployment bundle

The project entrypoint can be compiled with the SDK's native-asset-aware CLI build:

```sh
dart build cli --target bin/migrate.dart --output build/migration
./build/migration/bundle/bin/migrate check
./build/migration/bundle/bin/migrate apply
```

Deploy the complete `bundle` directory, including its native libraries. Migration
history and snapshots are compiled into the executable; runtime `check`, `plan`,
`apply`, `status` and `verify` do not read Dart source or migration assets. Supply
the same environment configuration used by your connection factory. Build for the
actual deployment OS/architecture.

Use source execution during authoring. A compiled executable contains the history
from its build and cannot discover a newly generated migration. Rebuild after
reviewing and committing new history. The application imports `migrate.dart` and
its registry; it does not need the generator or CLI entrypoint.

## Application startup compatibility

```dart
// Default: the database must have completed the latest bundled migration.
final version = await Migrator(db).requireVersion(migrations);

// This release can run on either side of a compatible expand migration.
await Migrator(db).requireVersion(
  migrations,
  minimum: '0001_initial',
  maximum: '0002_expand',
);
```

The range is inclusive and uses the ordered bundled history. Without bounds, the
requirement is exactly its latest migration. With only `minimum`, the upper bound
is the latest bundled migration; with only `maximum`, that version is required
exactly. Bounds must name an ordered, nonempty range in the supplied history.
The list is copied before asynchronous work begins.

The check validates every applied ID/checksum in the history prefix, not just its
last ID. An unversioned database, an older required version, a database outside the
range, or a database newer than the bundled history reports `MIGRATION.VERSION`.
Changed checksums or missing history entries report `MIGRATION.CHECKSUM`; corrupt
checkpoint sequences report `MIGRATION.HISTORY`. Any recovery checkpoint for a
migration not yet recorded as applied reports `MIGRATION.INCOMPLETE`, including
checkpoints unknown to an older application. Complete or recover that migration
before accepting application traffic.

Call this on a root database or a leased session, outside an existing transaction.
The check opens a short read transaction: PostgreSQL uses REPEATABLE READ READ ONLY,
and SQLite uses a deferred read snapshot, including on an explicitly read-only
file. It reads catalog/history/checkpoints without creating metadata or applying
migrations. The returned `MigrationStatus` records the accepted ID and checksum.
An existing caller transaction is rejected with `MIGRATION.SESSION` so the method
can establish its own consistent snapshot.

This is a point-in-time startup check. It does not prevent a later deployment
from changing the database, check the actual catalog for drift, or prove that old
application processes have stopped. Use `verifySchema` for catalog checks and
coordinate incompatible contract migrations with application deployment. A
rejected downgrade does not delete or rebuild tables.

## Schema evolution

`diff` generates PostgreSQL and SQLite operations together:

- New nullable/defaulted columns use `ALTER TABLE` when SQLite permits the default.
- SQLite changes to existing columns or keys use an explicit `RebuildTable` step.
- Renames must be declared. Drops require `allowDestructive: true` when generating
  the file; the resulting file makes each removal visible to review.
- A new required column without a default needs a separate add/backfill/constrain
  sequence. Identity changes require a manual migration.
- Type changes require SQL conversion expressions for each dialect. Expressions
  are trusted migration code and use column names after declared renames.

[Computed target columns](computed.md) use their own expressions to populate old
rows and derive values on type changes. They are excluded from rebuild copy maps;
their addition does not require a default or application backfill. Mode conversions
and native expression dependencies have separate documented migration limits.

For long data transformations, use a reviewed [resumable backfill](backfills.md).
It carries a historical table definition, commits bounded batches with their
primary-key cursors, supports bounded runs, and verifies completion. Both SQLite
and PostgreSQL support it; general `CheckedSql` autocommit operations still require
PostgreSQL.

```dart
final change = Migration.diff(
  '0003_score_text',
  from: previousSnapshot,
  to: nextSnapshot,
  previous: previousMigration.checksum,
  using: {
    SqlDialect.sqlite: {'members': {'score': 'CAST(score AS TEXT)'}},
    SqlDialect.postgres: {'members': {'score': 'CAST(score AS TEXT)'}},
  },
);
```

SQLite rebuilds borrow one connection, disable foreign keys before `BEGIN`, copy
explicit columns into a new table, replace the old table, and recreate indexes
and triggers. They check foreign keys before commit and restore the connection's
original foreign-key setting even on failure. Restore failure discards the
connection. Incoming cascade relations therefore do not delete child rows during
replacement. Existing views are retained and checked after replacement.

The runner preserves unmanaged indexes and triggers whose SQL can be restored.
Unmodeled table constraints/options (undeclared `CHECK`, collations, generated expressions,
`STRICT`, `WITHOUT ROWID`, and similar features) require a manual migration;
they are never silently discarded. Removing columns from a table with triggers
also requires explicit manual handling. A new managed index cannot silently
replace an unmanaged index of the same name.

[Declared CHECK constraints](checks.md) participate in schema diffs, inspection
and import. SQLite adds/changes/removes them through a rebuild; PostgreSQL uses
constraint DDL. Checked renames explicitly remove and re-add the declared SQL,
which can require two SQLite copies. Existing rows are validated before commit.

Manual migrations use `Migration(id, {dialect: ['SQL', ...]})`, or
`Migration.steps` with `ExecuteSql`, `DropTable`, and `RebuildTable` operations.
For a custom SQLite copy-and-replace migration, an explicit `DropTable` enables
outer foreign-key handling; preserve dependent SQL objects in the reviewed steps.
Transaction control is owned by the runner. Use `CheckedSql` for PostgreSQL
commands that must run outside a transaction; ordinary `ExecuteSql` rejects them.

# Recoverable PostgreSQL operations

```dart
final migration = Migration.steps(
  '0004_email_index',
  {
    SqlDialect.postgres: [
      CheckedSql.createIndex(
        'members',
        const IndexSchema('members_email_lookup', ['email']),
      ),
    ],
  },
  previous: previousMigration.checksum,
  snapshot: nextSnapshot,
);
```

`CheckedSql.createIndex` builds a concurrent B-tree index using default column
collations and operator classes. Its completion check compares the table, ordered
columns, uniqueness, predicate/expression absence, index options and validity.
A same-name object or an INVALID index is not proof of completion. PostgreSQL's
[concurrent index documentation](https://www.postgresql.org/docs/current/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY)
explains its nontransactional execution and possible INVALID leftovers.

Other operations use `CheckedSql(sql, readyWhen: 'SELECT ...', doneWhen: 'SELECT ...')`.
Each condition must return exactly one boolean and accurately describe durable
state. SQL and probes are reviewed migration code. The runner first checks
`doneWhen`; if false, it requires `readyWhen`, executes SQL in autocommit mode,
and checks `doneWhen` again. If neither state matches, it stops for explicit
inspection/repair. It does not guess that an existing object should be dropped.
Retry the unchanged migration after repairing the actual database.

A migration containing `CheckedSql` uses durable checkpoints for every step.
Ordinary SQL within that migration commits its effect and completion checkpoint
in the same transaction. Checked SQL records its phase before execution and checks
actual state on restart. An interrupted success therefore need not execute twice.
Attempted migration checksums are frozen even before the whole migration completes.

This mode is not one atomic transaction: earlier successful steps remain committed
when a later step fails. Contiguous ordinary migrations outside a mixed migration
still form an atomic batch. The runner lock covers all these phases on the same
connection; baseline and ordinary migration runners use the same lock protocol.
Session lock behavior is documented by
[PostgreSQL](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS).

Use `Migrator(db).progress()` or `dart run bin/migrate.dart status` to inspect step states, failed
phases and failure codes. `dart run bin/migrate.dart plan` reports `atomic: false` for pending
nontransactional work and includes progress. A `MIGRATION.STEP` exception retains
the underlying error as `cause`. A failed lock release discards its connection.
SQLite rejects `CheckedSql`; its schema rebuild path remains transactional.

Tests terminate real Dart processes immediately after a concurrent DDL succeeds
and after an ordinary step commits. Both resume from unchanged files without
replaying committed work. They also exercise INVALID unique indexes, explicit
repair, definition mismatches, lock timeout and simultaneous runners.

# Existing databases

```dart
final result = await Migrator(db).baseline(
  migrations,
  expected: migrations.last.snapshot!,
);
```

Baseline verifies declared columns, storage types, nullability, defaults, primary
and unique keys, foreign keys, and simple indexes before recording history. It
never replays creation SQL and refuses existing nonempty migration history.
`verifySchema(...).matches` covers these supported facts; inspect `unmanaged`
separately for triggers, policies, expression/partial indexes and unmodeled
constraints/options. This catalog currently inspects the declared tables, not all
objects in a database. PostgreSQL constraint removal resolves actual names by
signature, including names chosen before an ORM baseline.
