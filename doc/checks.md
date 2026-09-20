# Row CHECK constraints

Declare a row constraint beside its entity. Expressions use physical SQL column
names; generation reads literal SQL and never executes a sample Dart record.

```dart
typedef Product = ({
  @Id.generated() int id,
  double price,
  double? discount,
  String label,
});
final products = entity<Product>();
final nonnegativePrice = products.check('price >= 0');
final validDiscount = products.check('discount >= 0 AND discount <= price');
final shortLabel = products.check(
  'length(label) <= 20',
  postgres: 'char_length(label) <= 20',
);
```

`name` defaults to the declaration's snake_case name, for example
`nonnegative_price`. Set an explicit stable name to rename the Dart declaration
without renaming its database constraint. `name: null` deliberately emits an
unnamed constraint. Names must be nonempty and unique per table. SQLite compares
ASCII identifier case without distinction; PostgreSQL preserves quoted case.
Expressions and optional overrides are string literals. An override replaces the
common expression for that backend; the expression selected by the migration
target must be nonempty.

These are trusted schema SQL fragments, like `@Default.sql`; do not construct
them from user input. Dart checks the declaration API, while the database checks
SQL syntax and enforces the predicate. This feature does not type-check SQL column
names or translate arbitrary Dart boolean closures.

SQL NULL is accepted by CHECK. A nullable `discount` can be absent in this example;
requiring a value needs a non-nullable field as well. Constraints concern the
current row and should use stable functions. PostgreSQL assumes a CHECK condition
does not change for the same row; changing a function implementation requires
explicit revalidation. See [PostgreSQL constraints](https://www.postgresql.org/docs/18/ddl-constraints.html)
and [SQLite CHECK semantics](https://www.sqlite.org/lang_createtable.html#check_constraints).

## Snapshots, verification and import

The current generated `TableSchema.checks` retains overrides in `CheckSchema`.
Saved migration schemas freeze only their chosen engine's expressions. Changing
an unused override does not change that migration target's physical fingerprint.

`inspectTable` and `orm db inspect` expose native names and expressions.
`verifySchema` compares declared checks, including duplicate unnamed constraints.
An extra check is reported as an unmanaged object; a missing or different check
is drift. PostgreSQL unvalidated, unenforced, inherited and NO INHERIT constraints
stay unmanaged because they do not meet this declaration's ordinary enforced-row
contract.

SQLite comparison tokenizes SQL, ignores comments, identifier quoting and outer
parentheses, and retains string literals, casts and precedence. It preserves
SQLite's non-ASCII identifier case distinctions. This is conservative comparison,
not a general SQL parser or proof that differently written predicates are equivalent.
The exact unnamed range/precision expressions emitted for `@IntegerBits` and
`@DecimalDigits` remain reserved storage metadata; named row checks are separate.

PostgreSQL rewrites SQL when storing a constraint. Verification uses one
`EXPLAIN (VERBOSE, FORMAT JSON)` projection per checked table to render declared
and catalog expressions in the same typed context. It has planning/catalog cost
and does not execute the SELECT or scan application rows. The planner can evaluate
immutable constant expressions, so this is not a promise of zero function
evaluation. No `ANALYZE` option is used. See [EXPLAIN](https://www.postgresql.org/docs/18/sql-explain.html).
SQL/functions must be available in the selected database schema during verification.

[Import](https://github.com/medz/dart-orm/blob/main/doc/importing.md) retains native check SQL and names, including explicit null
names on SQLite, and emits a nonblocking `IMPORT.CHECK_SQL` review note. Check
other-dialect overrides before deploying an imported declaration elsewhere.

## Reviewed migrations and cost

`Migration.diff` includes additions, removals and expression/name changes.
PostgreSQL drops changed constraints and adds replacements. SQLite rebuilds the
table. Adding a check validates existing rows; a violation rolls back the ordinary
migration batch and its history. Repair data explicitly, then retry the unchanged
migration. A change to only the PostgreSQL expression produces no SQLite DDL.

For an explicit table/column rename, update physical names in the declared SQL.
The diff removes old declared checks before native renames and adds the new
expressions afterward. It never guesses how to rewrite SQL text. On SQLite a
checked rename with target checks uses two visible rebuild steps, potentially
copying the table twice; inspect the migration and budget disk space and write
lock time. Native renames preserve view, trigger and foreign-key references.
Unclaimed checks block a SQLite rebuild instead of being silently removed.

Checks can make writes and schema upgrades more expensive. This API provides
reviewed, transactional changes; an online zero-lock upgrade is not implied.
Function definitions, cross-table invariants and specialized constraint modes
remain explicit native migration work.
