# MySQL and MariaDB migrations

Use one fixed `mysql` or `mariadb` migration history with its matching driver.
The migration runner checks MySQL 8.4+ or MariaDB 11.8+ before taking a lock or
creating its journal. The MySQL driver has the same 8.4 minimum; the MariaDB
driver's 10.6 connection minimum does not extend migration support to that
version. The normal Dart project workflow applies:

```sh
dart run orm init --database mysql
dart run orm migrate create 0001_initial
# Review migrations/m0001_initial.dart.
dart run orm migrate check
dart run orm migrate apply
dart run orm migrate verify
```

`init --database mariadb` selects MariaDB instead. Models, physical snapshots,
reviewed migration operations and the static registry are all Dart source. A saved
migration contains SQL for its selected engine only; current application models
are not imported by historical migration files. See [migrations](https://github.com/medz/dart-orm/blob/main/doc/migrations.md)
for configuration, fingerprints, deployment bundles, baseline and version checks.

## DDL and recovery

MySQL and MariaDB DDL commits independently of application transactions. MySQL's
atomic DDL guarantees do not make a sequence of DDL statements transactional.
The runner consequently executes each reviewed `CheckedTableSql` outside a
transaction, holding one session lock for the selected database. The step records
its SQL and complete physical table definitions before and after the operation.
A null `before` means creation; a null `after` means removal. Different table names
mean an explicit rename. [MySQL atomic DDL](https://dev.mysql.com/doc/refman/8.4/en/atomic-ddl.html)

For each unfinished step, the runner:

1. Records an attempted step with the immutable migration fingerprint.
2. Compares the live catalog with the complete `after` definition. An exact match
   means the DDL is already complete, including when its response was lost.
3. Otherwise requires an exact `before` definition, executes the SQL, and verifies
   the complete `after` definition before recording completion.
4. Stops if neither definition matches. Repair the database, then retry the same
   unchanged history. An object with the right name and wrong shape is rejected.

Checks cover column storage, nullability, identity/default/computed expressions,
primary and unique keys, indexes, foreign keys and checks. Unmodeled table options,
triggers, unsigned columns, unsupported indexes and other catalog objects block
checked DDL and backfill. The runner does not silently discard them. Expression comparison understands
common arithmetic, comparison, boolean and function forms and preserves operator
precedence. Other SQL syntax uses strict token comparison; a different server
rendering is reported as drift instead of being assumed equivalent.

Completed checkpoints form a durable prefix. A later failure does not roll back
earlier DDL. `migrate status` exposes the step, phase and failure; retrying `apply`
continues the same history. Applied or attempted migrations with changed
fingerprints are rejected. The final declared snapshot is verified before the
migration itself is recorded as applied.

The runner uses `GET_LOCK`/`RELEASE_LOCK` with a database-specific key and
`Migrator(..., lockTimeout: ...)`. Lock ownership stays with one physical session.
A failed acquisition or uncertain release discards that connection. These locks
coordinate ORM migration runners; they do not block independent administrative
DDL or normal application writes. Use deployment coordination for those changes.
[MySQL named locks](https://dev.mysql.com/doc/refman/8.4/en/locking-functions.html)

## Data changes

`ExecuteSql` accepts `INSERT`, `UPDATE`, `DELETE` and `REPLACE` for these engines.
Each such step and its completion checkpoint share an InnoDB transaction. Raw
DDL, transaction control and session administration are rejected during validation;
use a reviewed `CheckedTableSql` for DDL. Keep manual DML within managed InnoDB
tables: arbitrary SQL targeting external nontransactional tables cannot inherit
InnoDB rollback guarantees.

`Backfill` keeps its historical table definition and immutable primary-key cursor.
It locks a bounded batch with `SELECT ... FOR UPDATE`, updates exactly those keys,
and commits the row changes and cursor together. This does not require MySQL
`UPDATE ... RETURNING`. Triggers or other unmanaged table behavior are rejected,
and retained primary keys are checked before advancing. `maxBackfillBatches`
bounds one invocation; a later `apply` resumes its saved cursor.

Add a nullable column, backfill it, then make it required in a later migration.
The diff generator will not add a populated required column without a default or
backfill stage. Primary keys must stay immutable while the backfill runs.
Application writes must preserve the completion condition during deployment.

## Supported schema changes

Creation, explicit table/column renames, column addition/removal, defaults,
nullability, signed integer/decimal/temporal widening, primary and unique keys,
ordinary indexes, foreign keys and named checks produce reviewed table steps.
Foreign keys are created after their tables, including cyclic relationships.
Their required supporting indexes have deterministic names and appear in the
frozen schema, so InnoDB does not create invisible schema drift on the ORM's behalf.
Destructive drops require `allowDestructive`; renames are never inferred.

Automatic narrowing, codec changes, identity changes, generated-to-ordinary
changes and changes between virtual/stored generated columns are rejected during
planning. Use explicit replacement columns and backfill, or author a reviewed
`CheckedTableSql` with accurate historical definitions. MySQL has no PostgreSQL
`ALTER ... USING`; the `using` diff option is rejected. Give checks explicit names
if they may need to be removed or changed later.

Physical defaults are signed `BIGINT`, `VARCHAR(255)` with `utf8mb4_bin`, `DOUBLE`,
`TINYINT(1)`, `LONGBLOB`, `DATE`, `TIME(6)` and `DATETIME(6)`. Decimal columns require
explicit precision 1–65 and scale 0–30 not exceeding precision. Tables use InnoDB
and `utf8mb4_bin`. MariaDB JSON is its native JSON alias, including the generated
validity check; catalog inspection recognizes that representation. `TINYINT(1)`
does not itself restrict values to zero and one. DATETIME catalog metadata does
not identify whether an application intends a UTC instant or a local date/time.

A declared temporal precision below six delegates storage coercion to the engine;
rounding/truncation can differ by engine and SQL mode. The ORM does not promise
cross-engine rounding for these columns. The default six digits preserve Dart's
microsecond precision. Computed expressions and checks can specify separate
`mysql:` and `mariadb:` SQL; each history freezes only its selected expression.

Catalog verification reports unsupported features rather than guessing a mapping:
unsigned/zerofill and binary-string types, prefix/expression/descending/invisible
indexes, nondefault table options, cross-database foreign keys and custom foreign
constraint names. An imported database can be verified and baselined while
reporting unmanaged objects; automated checked changes require resolving them
first. [MySQL column metadata](https://dev.mysql.com/doc/refman/8.4/en/information-schema-columns-table.html),
[MariaDB column metadata](https://mariadb.com/docs/server/reference/system-tables/information-schema/information-schema-tables/information-schema-columns-table)

## Verification

`test/mysql_migration_test.dart` uses `ORM_TEST_MYSQL` and `ORM_TEST_MARIADB` and
optional matching `_TLS` variables. It creates an isolated disposable database
per test and therefore needs `CREATE DATABASE` privileges. Tests cover catalog
round trips, lost DDL acknowledgements, drift rejection, transactional checkpoint
failures, unknown commit outcomes, lock release, bounded backfill, explicit
renames, relationships and baseline. A compiled consumer imports generated Dart
migrations and checks their fingerprints for both engines. An unset
engine environment variable skips its live tests; static planning tests still run.
