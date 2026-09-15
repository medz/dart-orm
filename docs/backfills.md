# Resumable backfills

`Backfill` is an explicit migration step for a long data update. It commits small
batches with durable primary-key cursors and verifies completion before recording
the migration as applied. Import `package:orm/migrate.dart` alongside your database
entry point.

```dart
// Use the snapshot committed with the expand migration, not current app models.
final historical = expand.snapshot!;
final users = historical.tables.singleWhere((t) => t.name == 'users');
final backfill = Migration.steps(
  '0003_display_names',
  [
    Backfill(
      users,
      set: {'display_name': 'name'},
      where: 'display_name IS NULL',
      doneWhen: 'SELECT NOT EXISTS(SELECT 1 FROM users WHERE display_name IS NULL)',
      batchSize: 1000,
    ),
  ],
  dialect: expand.dialect,
  previous: expand.checksum,
  snapshot: historical,
);
```

Save this migration with `writeMigration` from `package:orm/generate.dart`, review
the emitted Dart file, and import it through the static history on subsequent runs. Its table definition, assignments, filter, completion SQL and
batch size are covered by the migration checksum. Expressions are trusted migration
SQL for this history's chosen database.
No latest generated client or application codec callback is needed to resume.

## Running a bounded amount of work

```dart
final appliedIds = await Migrator(db).apply(
  migrations,
  maxBackfillBatches: 10,
);
final pending = await Migrator(db).plan(migrations);
final checkpoints = await Migrator(db).progress();
```

The default completes all pending work. `maxBackfillBatches` limits the number of
nonempty data batches performed by this call, shared across backfill steps. It
does not change the saved migration or its checksum. The call returns IDs of
migrations it completed; a paused migration remains pending. Completion verification
may need the next call after the final permitted data batch. A batch limit is not
a wall-clock or statement timeout.

```sh
dart run bin/migrate.dart plan
dart run bin/migrate.dart apply --max-backfill-batches 10
dart run bin/migrate.dart status
```

Configure PostgreSQL in the Dart entrypoint as described in [migrations](migrations.md).
Plans report `atomic: false` when pending work includes a backfill. Bounded CLI
runs additionally return `complete: false` until the entire migration list is
applied. Status includes `backfill.rows`, `batches`, `last` and `upper`. Keys are
stored as lossless strings; binary keys use base64, and integer keys never pass
through floating-point JSON. These records contain primary-key data. A `running`
checkpoint describes unfinished durable work; it is not proof of a live process.

## Transaction and recovery behavior

The runner checks the historical schema, captures an upper primary-key boundary,
and scans matching keys in ascending order from the last committed key. Composite
primary keys use row comparisons. There is no growing OFFSET. Actual batch sizes
are reduced to fit the driver's parameter limit. SQLite documents this use of
[row values for scrolling queries](https://www.sqlite.org/rowvalue.html).

Each batch selects keys, updates exactly those rows and records its new cursor
in one transaction. PostgreSQL locks selected rows without skipping locked rows;
SQLite uses BEGIN IMMEDIATE for the batch. Skipping locked rows would be unsafe
for a cursor that advances past them. See PostgreSQL's
[row-locking semantics](https://www.postgresql.org/docs/current/sql-select.html).
The whole invocation retains one leased connection, while other connections can
operate between batch commits. SQLite runners recheck history and progress inside
their write transaction; PostgreSQL runners retain the existing migration advisory
lock. Competing runners do not repeat committed batches.

A process exit during a batch rolls back both its writes and cursor. An exit after
commit preserves both. A lost commit acknowledgement remains an error; a later
invocation reads durable state to decide where to resume. It never assumes that
an uncertain batch should be replayed. Successful chunks invalidate relevant typed
query subscriptions after commit; rolled-back chunks do not publish their writes.

An explicit backfill makes its containing migration recoverable rather than atomic
as a whole. Other steps in that migration have individual checkpoints. Adjacent
ordinary migrations retain their atomic grouping. SQLite table rebuilds remain
whole-table operations with foreign-key verification and setting restoration;
`batchSize` does not make a rebuild incremental.

## Completion and constraints

`doneWhen` must return exactly one boolean: a PostgreSQL boolean, or SQLite's integer
0/1 representation. NULL, floating-point values and wrong result shapes are errors.
A false condition leaves the migration pending with a failed verification checkpoint.
Already committed batches stay committed. Repair the condition or missing data and
resume the unchanged migration; the runner does not rewind and risk repeating
non-idempotent updates.

Primary keys must be non-null, unique across the scan and immutable throughout the
operation, including application writes and triggers. Assigning a primary key is
rejected. The runner checks updated/retained keys and rejects detected key movement.
Integer, bigint, text, finite real, boolean, UTC instant, historical timestamp, local date/time and binary cursors are
supported, including composite keys. JSON keys are rejected because the current
driver boundary cannot promise lossless cursor representation for every document.
Ordering follows the actual database storage type and collation.

Use expand → compatible application writes → backfill → contract. New writes must
already satisfy the intended invariant, including rows inserted behind the cursor
or above the captured boundary. Completion SQL must cover that invariant. Keep
the historical table/key definition stable while the job runs. Temporary tables
cannot shadow the data target or durable migration metadata. PostgreSQL backfills
reject active row security rather than letting hidden rows satisfy a false
completion claim; the check uses the current role's
[row-security state](https://www.postgresql.org/docs/current/functions-info.html).

The historical catalog check happens at the start of each backfill attempt; normal
chunks do not rescan the catalog. The runner bounds returned key rows and update
parameters. Filter and verification SQL may still scan substantial data: inspect
their query plans and add appropriate indexes as reviewed migrations. This feature
does not promise a particular throughput, zero downtime, or automatic repair of an
incorrect transformation. Statement timeouts and lock waits retain driver behavior.

Reproduce the standalone SQLite native acceptance check with:

```sh
dart build cli --target test/support/native_backfill.dart --output .dart_tool/backfill-aot
.dart_tool/backfill-aot/bundle/bin/native_backfill
```
