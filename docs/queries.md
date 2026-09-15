# Queries

`select` chooses SQL expressions and decodes their values. A scalar expression
returns its Dart type; `(u.id, u.email).map(...)` constructs a named Record or DTO
after reading the selected columns. `(u.id, u.email).row` returns a positional
`(int, String)` Record with no custom mapping. SQL records support 2–6 fields.

`query.map(...)` maps the already selected Dart result. It does not create SQL
columns, and its properties are not usable in SQL filters or ordering.

Run the [cookbook](../example/queries.dart) with `dart run example/queries.dart`.
It checks nine combined query/schema scenarios on an in-memory SQLite database.
Set `ORM_EXAMPLE_POSTGRES` to a disposable local PostgreSQL URL to run the same
checks there. That example explicitly disables TLS for local development, creates
a uniquely named schema and removes only that schema in `finally`.

## Filters, results and ordering

Build a query with normal Dart control flow. Builder calls return new query
values; terminal calls execute them:

```dart
var query = db.users.where((u) => u.email.like('%@example.com'));
if (minimumScore != null) {
  query = query.where((u) => u.score.gte(minimumScore));
}
final emails = await query.orderBy((u) => [u.id.asc()])
    .take(20).select((u) => u.email).get(); // List<String>
```

Use `.eq`, `.and` and `.or` to construct SQL predicates. `.isNull()` and
`.isNotNull()` test SQL NULL; `.eq(null)` is available only on a nullable field.
An empty `isIn([])` is false. Other NULL-containing membership expressions retain
SQL's three-valued logic, not Dart collection semantics. Values are bound as
parameters. `like` treats `%` and `_` as SQL wildcards.

`get()` returns a list, `first()` returns the first value or null, and `single()`
requires exactly one result. `count()` and `exists()` issue dedicated SQL. Add
explicit ordering when the first row or page must be deterministic. Use
[keyset cursors](#keyset-pagination) for changing large datasets;
`skip`/`take` provide offset/limit pagination.

## Keyset pagination

Choose distinct root-table columns with a declared unique tie breaker. Nullable
columns require explicit NULL ordering:

```dart
final first = await db.users
    .orderBy((u) => [u.nickname.asc(nulls: .last), u.id.asc()])
    .take(20).get();
if (first.isNotEmpty) {
  final last = first.last;
  final token = db.users.cursorToken((u) => [
    u.nickname.cursor(last.nickname, nulls: .last), u.id.cursor(last.id),
  ]);
  final next = await db.users.seekToken(token,
    orderBy: (u) => [u.nickname.asc(nulls: .last), u.id.asc()],
  ).take(20).get();
}
```

`seekAfter` accepts the same typed cursor terms directly. `cursorToken` transports
their values losslessly and `seekToken` validates the format version, table,
ordering and codecs. Keep the original filters when constructing subsequent
pages. A cursor is pagination input, not an authorization token or a frozen
snapshot. Joins, grouping, DISTINCT, CTE/set results, offset and non-column
ordering do not have the required table-key proof and are rejected.

## Join and order by related fields

Use a typed alias when a related field participates in root ordering or a flat
projection. This example uses the [generated example schema](../example/schema.dart):

```dart
final author = usersTable.alias();
final rows = await db.posts
    .join(author, on: (p, a) => p.authorId.equals(a.id))
    .orderBy((p) => [author.fields.email.asc(), p.id.asc()])
    .select((p) => (p.title, author.fields.email).row)
    .get(); // List<(String, String)>
```

For `leftJoin`, wrap a possibly absent selection with
`author.optional(author.fields.email)` and compose it with `.map(...)`; an
unguarded non-null field is rejected before SQL. `author.isPresent` can test
the joined row's presence independently of its nullable values. Aliases cannot
be reused across unrelated query scopes or referenced before their join.

To order by a collection count, use
`db.users.orderBy((u) => [u.posts.count().desc(), u.id.asc()])`. This compiles a
correlated count without loading posts. Normal nested results still use
[relationship selections](relations.md) and their explicit loading strategies.

## Grouping, subqueries, CTEs and windows

```dart
final totals = db.posts.groupBy((p) => [p.authorId])
    .having((p) => p.id.count().gt(1))
    .select((p) => (p.authorId, p.id.count()).row)
    .asCte('author_totals');
final active = await totals.query
    .orderBy((c) => [c.ref((p) => p.authorId).asc()]).get();

final ranks = await db.posts.orderBy((p) => [p.id.asc()])
    .select((p) => (p.id, rowNumber(
      partitionBy: [p.authorId], orderBy: [p.createdAt.desc(), p.id.desc()],
    )).row).get();
```

Aggregates in `where`, ungrouped selected columns and invalid window placement
are rejected before execution. Window functions preserve row count; group
aggregates combine rows. A CTE exports its selected SQL expressions through
`ref`, including when the Dart result is mapped to a DTO. An arbitrary DTO
property or unselected expression is not an exported SQL column.

Use `field.isInQuery(selectedQuery)`, `selectedQuery.existsExpression()` and
`selectedQuery.scalar()` for nested SQL.
A scalar subquery must have a provable single-row bound, such as an ungrouped
aggregate or `take(1)`; a missing row produces null. Inner predicates may refer
to the outer query's fields through an explicitly captured expression. Queries
from different database/transaction objects cannot be combined.

For SQL beyond these typed operations, use parameterized raw expressions or
[checked named SQL](named-sql.md). Raw fragments are trusted SQL supplied by the
application; do not interpolate user input into them.

## UNION and UNION ALL

Combine scalar expressions or SQL records with matching types:

```dart
final names = db.users.select((u) => u.email)
    .union(db.posts.select((p) => p.title));
final List<String> result = await names.get();

final rows = db.users.select((u) => (u.id, u.email).row)
    .unionAll(db.posts.select((p) => (p.id, p.title).row))
    .orderBy((row) => [
      row.ref((u) => u.id).asc(),
      row.ref((u) => u.email).asc(),
    ]);

final List<({int id, String label})> cards = await rows.take(20)
    .map((row) => (id: row.$1, label: row.$2))
    .get();
```

`union` removes duplicate **stored SQL rows**; `unionAll` keeps them. Neither
promises operand order. Use a final `orderBy` when order matters. SQL equality,
collations and NULL rules determine duplicates, independently of Dart `==`.
These semantics follow [PostgreSQL set operations](https://www.postgresql.org/docs/current/queries-union.html)
and [SQLite compound SELECT](https://www.sqlite.org/lang_select.html#compound_select_statements).

Different Dart result types are rejected by the analyzer. Before execution, the
ORM additionally requires matching positional columns, codec identities and
nullability. Custom codecs must reuse the same instance. Different mappings to
the same Dart type are not interchangeable. Nullable wrappers around a shared
codec remain compatible; nullable and required columns must be explicitly
aligned, for example with `alias.nullable(alias.fields.id)` in outer joins.

Each operand must belong to the same `Database` object or transaction session.
Combining a root query with a transaction query is rejected. Values remain bound
parameters; PostgreSQL standalone `value(...)` expressions carry explicit SQL
types so parameters in projections do not default to text.

### Map after the set operation

Arbitrary Dart mappers and loaded relationships are not SQL set columns:

```dart
// Rejected: these mappers have different behavior despite both returning String.
final upper = db.users.select((u) => u.email.map((v) => v.toUpperCase()));
final lower = db.posts.select((p) => p.title.map((v) => v.toLowerCase()));
// upper.union(lower) throws QUERY.UNION_SELECTION.
```

Whole generated entities are Record/DTO mappings, so explicitly select their SQL
fields with `.row` before combining them. Map the result afterward. For a SQL
transformation, use an expression such as `u.email.upper()` before `union`.
Putting a Dart-mapped query in a CTE does not bypass this rule. The ORM never runs
a Dart mapper while planning SQL or guesses its behavior from its return type.

## Scope and composition

Operand filters, grouping, ordering and limits apply to that operand. Filters,
ordering and limits after the set operation apply to the combined rows. Each
operand is a derived table, which preserves its local clauses on both backends.
The complete union executes as one SQL statement.

`UnionFields.ref(...)` uses an expression exported by the **left** operand. An
unselected column, incompatible codec or unsafe nullable reference fails before
SQL execution. DTO property names are not exported SQL columns.

```dart
final recent = db.users.orderBy((u) => [u.id.desc()]).take(10)
    .select((u) => u.email)
    .unionAll(db.posts.orderBy((p) => [p.id.desc()]).take(10)
        .select((p) => p.title));

final filtered = recent.where((row) => row.ref((u) => u.email).like('a%'));
final cte = filtered.asCte('recent_names');
final selected = cte.query.select((c) => c.ref((row) => row.ref((u) => u.email)));
await for (final name in selected.stream(batchSize: 64)) {
  print(name);
}
```

Nested sets preserve association: `a.unionAll(b).union(c)` differs from
`a.unionAll(b.union(c))`. Each nesting adds an exported-expression scope, so
references follow that nesting. CTEs can wrap sets, supply operands and be joined
through typed aliases. Scalar sets also support `isInQuery` and, with `take(1)`,
`scalar()`. `count`, `exists`, aggregation, `stream` and `watch` reuse normal query
execution. Subscriptions collect table dependencies from both operands, including
nested CTEs and SQL subqueries; existing raw-SQL notification rules still apply.

Set results do not have declared primary/unique keys. Mutations and keyset cursor
pagination are therefore rejected; offset/limit pagination and database cursor
streaming are supported. `INTERSECT` and `EXCEPT` do not yet have typed methods.

## Aggregate numeric results

PostgreSQL returns `SUM(BIGINT)` and integer `AVG` as NUMERIC. Integer results are
parsed exactly, with overflow or fractional values rejected rather than rounded
through a double. On `int`/`double` expressions, `average()` returns an approximate
`double?`. On `Decimal` expressions, `average(scale: ..., rounding: ...)` returns
an exact `Decimal?` rounded once to the requested scale, including when the total
would overflow. See [decimal arithmetic and averages](decimals.md).
