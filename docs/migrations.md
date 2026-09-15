# Migrations

The CLI reads saved snapshots and migration files:

```sh
dart run orm generate example/schema.dart
dart run orm migration create 0001_initial --schema example/schema.orm.json
dart run orm migration check
dart run orm migrate apply --sqlite app.sqlite
dart run orm migrate plan --sqlite app.sqlite
dart run orm migrate status --sqlite app.sqlite
dart run orm db verify --sqlite app.sqlite --schema example/schema.orm.json
dart run orm db inspect --sqlite app.sqlite --table users
```

The default migration directory is `migrations`; change it with `--dir`. `plan`,
`status`, `inspect` and `verify` open SQLite read-only and require an existing file.
`apply` can create a new file. No-change generation writes no migration. Repeated
IDs, overwritten files, unknown options and broken history chains are rejected.

For PostgreSQL, use `--postgres-env DATABASE_URL`, with the URL held in that
variable. TLS defaults to `verifyFull`; `--tls require|disable` is explicit.
`--database-schema name` selects a PostgreSQL schema. SQLite rejects these
PostgreSQL-specific flags. Offline `migration check --dialect postgres` checks
PostgreSQL operations without connecting. `db baseline` uses the final snapshot
in the selected migration directory to register a verified existing database.

Start with [catalog import](importing.md) when the database has no Dart schema.
It drafts Record declarations and a separate review report before client generation
and baseline; it does not change existing tables or rows.

Commands return JSON, apart from `generate` and help. Exit code 2 indicates schema
drift or blocking import issues, 64 indicates invalid CLI arguments, and 1 indicates an execution failure.
Dart's launcher may also print its own build-hook progress on stderr.

For renames, pass `--renames file.json` with:

```json
{"tables":{"users":"members"},"columns":{"members":{"nickname":"display_name"}}}
```

Conversions use `--using file.json`, mapping dialect → table → column → SQL:

```json
{"sqlite":{"members":{"score":"CAST(score AS TEXT)"}},"postgres":{"members":{"score":"CAST(score AS TEXT)"}}}
```

`--allow-destructive` permits generating reviewed drop steps. Neither generation
nor offline checking executes those steps.

Import `package:orm/migrate.dart`. Schema files produced by `orm generate` are
portable snapshots; generated Dart clients are not executed to obtain them.

```dart
final initial = Migration.create('0001_initial', appSchema);
final target = SchemaSnapshot(nextSchema);
final change = Migration.diff(
  '0002_member_names',
  from: initial.snapshot!,
  to: target,
  previous: initial.checksum,
  renames: const SchemaRenames(
    tables: {'users': 'members'},
    columns: {'members': {'nickname': 'display_name'}},
  ),
);
```

Save `migration.toJson()` as a reviewed JSON file and commit it. Load it with
`Migration.fromJson(...)`. Migration format 2 stores ordered operations and a
final snapshot; schema snapshot format 1 stores portable table facts. Applied
checksums cover the entire migration, including its snapshot and predecessor.
Never edit an applied migration. Add another migration instead.

```dart
final migrations = [initial, change];
final pending = await Migrator(db).plan(migrations); // reads; does not create history
final appliedIds = await Migrator(db).apply(migrations);
final verification = await verifySchema(db, target);
```

`apply` runs a pending batch without `CheckedSql` or `Backfill` in one transaction. A failed copy, required
column, unique constraint, or foreign key rolls back earlier steps and history
records from that invocation. PostgreSQL uses a dedicated connection and a session advisory lock scoped to the
current database/schema; SQLite obtains an immediate write transaction. PostgreSQL
lock acquisition uses short `pg_try_advisory_lock` queries outside a transaction,
with `Migrator(db, lockTimeout: ...)` defaulting to 30 seconds. Waiting does not
hold an old SQL snapshot that could deadlock concurrent index creation.
Migration planning checks applied history and checksums. Catalog verification is
an explicit separate operation; SQL history alone does not prove schema equality.

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

Use `Migrator(db).progress()` or `migrate status` to inspect step states, failed
phases and failure codes. `migrate plan` reports `atomic: false` for pending
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
