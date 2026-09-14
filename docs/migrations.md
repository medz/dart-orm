# Migrations

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

`apply` runs the entire pending batch in one transaction. A failed copy, required
column, unique constraint, or foreign key rolls back earlier steps and history
records from that invocation. PostgreSQL uses an advisory transaction lock scoped
to the current database/schema; SQLite obtains an immediate write transaction.
Migration planning checks applied history and checksums. Catalog verification is
an explicit separate operation; SQL history alone does not prove schema equality.

`diff` generates PostgreSQL and SQLite operations together:

- New nullable/defaulted columns use `ALTER TABLE` when SQLite permits the default.
- SQLite changes to existing columns or keys use an explicit `RebuildTable` step.
- Renames must be declared. Drops require `allowDestructive: true` when generating
  the file; the resulting file makes each removal visible to review.
- A new required column without a default needs a separate add/backfill/constrain
  sequence. Identity changes require a manual migration.
- Type changes require SQL conversion expressions for each dialect. Expressions
  are trusted migration code and use column names after declared renames.

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
Unmodeled table constraints/options (`CHECK`, collations, generated expressions,
`STRICT`, `WITHOUT ROWID`, and similar features) require a manual migration;
they are never silently discarded. Removing columns from a table with triggers
also requires explicit manual handling. A new managed index cannot silently
replace an unmanaged index of the same name.

Manual migrations use `Migration(id, {dialect: ['SQL', ...]})`, or
`Migration.steps` with `ExecuteSql`, `DropTable`, and `RebuildTable` operations.
For a custom SQLite copy-and-replace migration, an explicit `DropTable` enables
outer foreign-key handling; preserve dependent SQL objects in the reviewed steps.
Transaction control and nontransactional commands are currently rejected by the
runner. Recoverable nontransactional execution remains under development.

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
