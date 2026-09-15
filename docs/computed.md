# Database computed columns

Declare SQL over physical column names. The generated Record includes the result;
creation and patch inputs omit it.

```dart
typedef Line = ({
  @Id.generated() int id,
  int price,
  int quantity,
  String label,
  @Computed.sql('price * quantity') int total,
  @Computed.sql('length(label)', postgres: 'char_length(label)',
      storage: ComputedStorage.virtual) int labelSize,
});
final lines = entity<Line>();

final row = await db.lines.create(price: 4, quantity: 3, label: 'cat');
print(row.total); // 12
await db.lines.byId(row.id).patch(quantity: .set(5)); // total becomes 20
final totals = await db.lines.select((r) => r.total).get();
```

`ComputedStorage.stored` is the ORM default and computes on writes; `virtual`
computes on reads. Both modes emit an explicit SQL storage clause. Select based
on expression cost, read/write frequency and storage needs. PostgreSQL 18 and
SQLite support both, but PostgreSQL 18 rejects indexes/unique keys on virtual
columns. Use stored columns for that portable schema. No performance advantage
is assumed from these correctness tests.

Generated computed fields are `ReadField<T>`: they support expressions, ordering,
selection and relationship keys, but have no `set`, `increment`, `change` or
`defaultValue` method. They cannot coexist with identity, SQL defaults or client
factories. Portable models cannot use computed primary keys, and every table
needs an ordinary column. Raw SQL retains the database's own write rules.

SQL is trusted schema code. Generation reads the literal; it does not translate
Dart closures or validate SQL function volatility. The database validates names,
operators and determinism. PostgreSQL disallows references to another generated
column and restricts virtual expressions to built-in functions/types. SQLite has
its own deterministic-expression rules. Review overrides for each backend.
[PostgreSQL rules](https://www.postgresql.org/docs/18/ddl-generated-columns.html),
[SQLite rules](https://www.sqlite.org/gencol.html).

## Migration behavior

Snapshots preserve expression SQL for each dialect and the storage mode. Existing
snapshots without computed metadata retain their representation and checksum.

| Change | PostgreSQL | SQLite |
| --- | --- | --- |
| Add a computed column | Native ADD COLUMN; old rows get computed values | Virtual: ADD COLUMN. Stored: rebuild |
| Change expression | SET EXPRESSION AS; stored values are rewritten | Rebuild, recomputing target columns |
| Change computed result type | Native TYPE without USING, followed by target expression | Rebuild with target expression |
| Drop a computed column | Explicit destructive diff, native DROP COLUMN | Explicit destructive diff, rebuild |
| Stored to ordinary | DROP EXPRESSION retains existing values | Rebuild copies the old computed values |
| Ordinary to computed, storage-mode change, virtual to ordinary | Automatic diff requires a reviewed replacement/materialization plan | A manual RebuildTable can express the SQLite transition |

The shared automatic diff refuses mode transitions that cannot be emitted natively
for PostgreSQL. Use reviewed `Migration.steps` with explicit per-dialect operations;
preserve indexes, constraints, views and triggers when replacing a column. Changing
types of columns used by generated expressions can also require a manual plan due
to native dependency rules. Automatic TYPE assumes the database accepts the cast;
it is not a promise of a lossless type conversion.

Stored-to-ordinary type changes still require explicit `using` conversions. A
computed target derives values from its declared expression and rejects `using`.
Rebuild copy maps and Backfill assignments must omit computed target columns.
Adding a computed non-null column needs no invented default/backfill: the
expression supplies values for old rows, and invalid results abort the migration.

Explicit renames require the target declaration's updated SQL; the ORM never
rewrites arbitrary expression text. PostgreSQL performs native renames and updates
the target expression. SQLite first materializes old computed values, performs
the rename, then rebuilds using the target expressions. A renamed computed table
can be copied twice; related CHECK preparation shares the first copy. Plan this
I/O and lock time before applying a large migration.

Tests run against PostgreSQL 18.4 and the pinned SQLite engine. Older PostgreSQL
servers require capability/version review: virtual columns require 18, and
SET EXPRESSION requires 17. Unsupported native syntax fails the migration; there
is no silent emulation. Stored expression changes rewrite rows and PostgreSQL
discards their column statistics, so review post-migration ANALYZE needs.
[Native ALTER TABLE behavior](https://www.postgresql.org/docs/18/sql-altertable.html).

## Catalogs and imports

`inspectColumns` exposes `ColumnInfo.computed`; `db inspect` includes expression
and mode. `verifyColumns` and `verifySchema` compare computation metadata in
addition to existing column facts. PostgreSQL uses a single EXPLAIN projection
per computed table, including assignment casts, to compare native typed output.
This plans SQL without selecting rows; immutable constant functions may run during
planning. SQLite compares tokenized SQL and preserves precedence, comments and
quoted identifiers. Semantically equivalent rewrites are not always recognized.

`db import` emits `@Computed.sql` and a nonblocking `IMPORT.COMPUTED_SQL` review
note. SQL from one database is not evidence of portability to the other. Managed
Decimal coercion is unwrapped for declarations and emitted once on regeneration.
Import does not run application code or sample data values.
