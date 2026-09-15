# Named SQL queries

Declare parameters and results as Dart records, keep complex SQL in files, and
generate a typed database method. This path uses the same Query, Selection,
connection, transaction and cursor implementation as generated tables.

```dart
import 'package:orm/schema.dart';

typedef AuthorStats = ({String author, int postCount, int points});
final authorStats = sqlQuery<AuthorStats, ({int minimum, String? author})>(
  sqlite: 'stats.sqlite.sql',
  postgres: 'stats.postgres.sql',
);
```

The SQLite file:

```sql
SELECT author, COUNT(*) AS post_count, SUM(points) AS points
FROM posts
WHERE points >= :minimum AND (:author IS NULL OR author = :author)
GROUP BY author;
```

Use `SUM(points)::bigint AS points` in the PostgreSQL file when the result is
intended to fit Dart's signed integer range. The files may differ or both dialects
may reference the same file. Paths are relative to the declaring Dart library.

```sh
dart run orm queries generate lib/queries.dart
dart run orm queries check --manifest lib/queries.queries.json --sqlite app.db
dart run orm queries check --manifest lib/queries.queries.json \
  --postgres-env DATABASE_URL --database-schema public
```

Generation writes `queries.queries.dart` and `queries.queries.json`. It works
offline, analyzes source types and codecs, and verifies that every dialect's
parameter names match the declared record. Commit both outputs with the SQL and
source declaration. `queries check` first re-analyzes the source and compares both
outputs; stale SQL, declarations or edited generated code require regeneration.

Import the generated file to use the method:

```dart
final stats = await db.authorStats(minimum: 2, author: 'a').single();
final names = await db.authorStats(minimum: 0)
    .where((s) => s.points.gt(10))
    .orderBy((s) => [s.author.asc()])
    .select((s) => s.author)
    .get(); // List<String>

await db.transaction((tx) async {
  final rows = await tx.authorStats(minimum: 0).get();
  // This query uses the transaction's connection and sees its pending writes.
});
```

Non-null parameter fields generate required named arguments. Nullable parameters
default to SQL NULL. Use `()` for no parameters. The result must be a public,
non-generic named-record typedef in the declaring file. Parameters may use such a
typedef or an inline named record. Enums and `@UseCodec` use the ordinary generator's
type and codec analysis. Result names use snake_case by default; `@ColumnName`
selects an explicit SQL alias. Query declarations do not accept identity, default,
index, integer-width or decimal-precision column metadata.

A declaration containing only `postgres:` generates an extension on
`Database<Postgres>`, so SQLite code cannot call it. A declaration containing both
targets works on either backend. Database checks validate only the selected target;
run both commands when shipping both files.

## What the checks establish

SQLite compiles `EXPLAIN SELECT <declared columns> FROM (<source>)`. PostgreSQL
uses SQL `PREPARE` for that projection, reads the prepared statement's native
result types, then deallocates it on the same leased connection. Neither path
executes the application SELECT. Missing tables, missing declared aliases and
invalid SQL fail. PostgreSQL also checks storage-type families against the declared
codecs. Its checker is verified against PostgreSQL 18.4, including the
`pg_prepared_statements.result_types` catalog column. These paths follow the
[PostgreSQL PREPARE lifecycle](https://www.postgresql.org/docs/current/sql-prepare.html),
[prepared-statement metadata](https://www.postgresql.org/docs/current/view-pg-prepared-statements.html),
and [SQLite EXPLAIN behavior](https://www.sqlite.org/lang_explain.html). The checker
does not parse SQLite's version-dependent EXPLAIN output.

These checks do not infer expression nullability, integer range, decimal scale,
enum labels or custom codec correctness. Integer declarations can accept native
NUMERIC metadata, but a fractional or out-of-range value still fails integer
decoding. SQLite expression values may change storage class between rows; their
types are checked by the result codecs at runtime. Declare nullable fields for
nullable SQL expressions. The report explicitly records `nullabilityChecked: false`.
Only emitted projections are checked; source columns not selected by the record
may remain in the SQL.

Generation itself performs lexical parameter scanning, not full SQL parsing.
Native structure checks belong in development/CI against the intended schema.
They prove acceptance at check time; they do not certify a future migrated schema
or persist an approval flag in runtime code.

## Composition and execution

The generated result is an ordinary immutable Query with a fixed SQL CTE source.
Typed filtering, projections, CTEs, subqueries, grouping/windows and streaming
remain available. The SQL source has no inferred key or cardinality: use `take(1)`
for a scalar subquery and supply normal outer ordering/limits. Keyset pagination
cannot invent a unique key for a SQL result. Generated table mutations are rejected
for this CTE source. This declaration path supports SELECT/WITH/VALUES queries;
use the existing mutation APIs or parameterized `Database.execute` for writes.

As with table queries, select SQL expressions before UNION, then map the result:

```dart
final a = db.authorStats(minimum: 0, author: 'a').select((s) => s.author);
final b = db.authorStats(minimum: 0, author: 'b').select((s) => s.author);
final authors = await a.unionAll(b).get();
```

Native SQL can call functions with side effects. The query wrapper does not prove
purity. Such SQL retains the database's ordinary execution and transaction rules.
SQL paths and text are application code; user input belongs in bound parameters.
`:name` is the sole placeholder syntax. Repeated names bind once. Quoted strings,
identifiers, comments, PostgreSQL casts and dollar-quoted text are preserved.
PostgreSQL backslashes in strings require explicit `E'...'` or dollar quoting.
Only one statement is accepted, with an optional terminal semicolon. Internal CTE
names use `_orm_sql_<query_name>`; avoid that namespace in application SQL.

Physical dependencies are opaque to the ORM. `watch()` therefore requires explicit
tables, including dependencies hidden in views/functions:

```dart
db.authorStats(minimum: 0).watch(reads: [postsSchema]);
```

The subscription follows the same committed-invalidation rules as other queries.
SQL source ordering alone does not establish the ordering of an outer query.

## Incremental generation

```yaml
targets:
  $default:
    builders:
      orm:queries:
        enabled: true
        generate_for:
          - lib/queries.dart
```

Run `dart run build_runner watch`. Both the Dart library and referenced SQL assets
participate in dependency tracking. Imported enum/codec declarations are tracked
by the analyzer resolver. A SQL parameter mismatch fails the build; fixing the
file restores output. This builder is independent of `orm:orm`, and a library may
contain both entity and named-query declarations when both builders target it.

The native fixtures cover both dialects, transactions, cursor reads, typed temporal
and Decimal parameters, raw-SQL subscriptions, failed structure checks and absence
of expression evaluation during checking. A compiled macOS executable exercises
the generated SQLite runtime without the analyzer. Browser, Flutter and query
throughput acceptance are separate work.
