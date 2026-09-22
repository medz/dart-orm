# Queries

`select` chooses SQL expressions and decodes their values. A scalar expression
returns its Dart type; `(u.id, u.email).map(...)` constructs a named Record or DTO
after reading the selected columns. `(u.id, u.email).row` returns a positional
`(int, String)` Record with no custom mapping. SQL records support 2–6 fields.

`query.map(...)` maps the already selected Dart result. It does not create SQL
columns, and its properties are not usable in SQL filters or ordering.

Run the [cookbook](https://github.com/medz/dart-orm/blob/main/example/queries.dart) with `dart run example/queries.dart`.
It checks nine combined query/schema scenarios on an in-memory SQLite database.
Set `ORM_EXAMPLE_POSTGRES` to a disposable local PostgreSQL URL to run the same
checks there. That example explicitly disables TLS for local development, creates
a uniquely named schema and removes only that schema in `finally`.

## Filters, results and ordering

Build a query with normal Dart control flow. Builder calls return new query
values; terminal calls execute them:

```dart
var query = db.user.where((u) => u.email.like('%@example.com'));
if (minimumScore != null) {
  query = query.where((u) => u.score.gte(minimumScore));
}
final emails = await query.orderBy((u) => [u.id.asc()])
    .take(20).select((u) => u.email).get(); // List<String>
```

Use comparisons with `allOf` and `anyOf` to construct SQL predicates. `.isNull()` and
`.isNotNull()` test SQL NULL; `.eq(null)` is available only on a nullable field.
An empty `isIn([])` is false. Other NULL-containing membership expressions retain
SQL's three-valued logic, not Dart collection semantics. Values are bound as
parameters.

### Nullable text and literal matching

Text operations accept both `String` and `String?` expressions:

```dart
final matches = db.user.where((u) => u.nickname.contains('50%_off!'));
final names = await matches.select((u) => u.nickname).get(); // List<String?>
await matches.update((u) => [u.score.increment(1)]).execute();

final prefixes = db.user.where((u) => u.email.startsWith('sales_'));
final suffixes = db.user.where((u) => u.email.endsWith('@example.com'));
final patterns = db.user.where((u) => u.nickname.like('A_%'));
```

| Method | Meaning of its argument |
| --- | --- |
| `contains(text)` | Literal text anywhere in the value |
| `startsWith(text)` | Literal prefix |
| `endsWith(text)` | Literal suffix |
| `like(pattern)` | SQL pattern: `%` matches any sequence and `_` one character |

Literal searches escape `%`, `_` and `!`, bind the resulting pattern, and emit
`ESCAPE '!'`. Quotes, backslashes and Unicode stay bound data. `like` passes its
bound pattern through using the database's native pattern and escape rules.
Empty literal searches match every non-NULL string, including an empty string.
These are database operations: collation, case sensitivity and Unicode behavior
follow the selected engine and column configuration.

All four methods return `Expr<bool?>`. A NULL input produces SQL NULL, so it does
not pass `where`; negating the predicate still does not include NULL values.
Include `.isNull()` explicitly when those rows should match. `lower()` and
`upper()` also preserve NULL and the expression's Dart nullability:

```dart
final List<String> emails = await db.user.select((u) => u.email.lower()).get();
final List<String?> nicknames = await db.user
    .select((u) => u.nickname.upper()).get();
```

These derived text values use the standard text codec. A source field's custom
or mapped decoder is not reapplied to the SQL conversion result, and SQL NULL
remains null even when the source decoder maps it to a sentinel string.

### Choosing a result operation

Choose the terminal operation that expresses the expected result count:

| Operation | Empty result | Multiple results |
| --- | --- | --- |
| `get()` | Empty list | All selected rows |
| `first()` | Throws | First selected value |
| `firstOrNull()` | `null` | First selected value |
| `single()` | Throws | Throws |
| `singleOrNull()` | `null` | Throws |

A nullable scalar selection can itself contain `null`; a nullable terminal does
not distinguish that value from an absent row. Select a Record containing a
non-null key when the distinction matters. `count()` and `exists()` issue
dedicated SQL. Add explicit ordering when the first row or page must be
deterministic. Use [keyset cursors](#keyset-pagination) for changing large
datasets; `skip`/`take` provide offset/limit pagination.

## Boolean condition groups

Use `allOf` for AND, `anyOf` for OR, and `.not()` to negate an expression.
Nested groups preserve their parentheses in SQL. Dart's `&&`, `||` and `!`
operate on Dart booleans and do not construct SQL expressions.

```dart
final query = db.user.where((u) => allOf([
  if (minimumScore != null) u.score.gte(minimumScore),
  anyOf([
    for (final email in permittedEmails) u.email.eq(email),
  ]),
  anyOf([u.nickname.eq('blocked').not(), u.nickname.isNull()]),
]));
```

The input iterable is consumed once when the group is built; changing a source
list afterward does not change the query. `allOf([])` is TRUE and `anyOf([])` is
FALSE. An empty list of permitted alternatives therefore matches no rows. When
an empty input should omit an optional filter, omit that group explicitly with a
Dart collection `if` instead. An empty outer `allOf` imposes no restriction;
check required user input before using it for an update or delete.

Repeated `.where(...)` calls combine complete predicates with AND. An OR group
in an earlier call keeps its parentheses. Builder calls return new query values.

Predicates retain SQL NULL semantics: NOT UNKNOWN is UNKNOWN, and WHERE keeps
only TRUE. To include null nicknames while excluding a value, combine the negated
comparison with `isNull()` as above. The same groups work in JOIN conditions,
relation filters, HAVING, and table WHERE predicates for updates and deletes;
their existing scope, aggregate, and mutation restrictions still apply.

## Keyset pagination

Choose distinct root-table columns with a declared unique tie breaker. Nullable
columns require explicit NULL ordering:

```dart
final first = await db.user
    .orderBy((u) => [u.nickname.asc(nulls: .last), u.id.asc()])
    .take(20).get();
if (first.isNotEmpty) {
  final last = first.last;
  final token = db.user.cursorToken((u) => [
    u.nickname.cursor(last.nickname, nulls: .last), u.id.cursor(last.id),
  ]);
  final next = await db.user.seekToken(token,
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
projection. This example uses the [generated example schema](https://github.com/medz/dart-orm/blob/main/example/schema.dart):

```dart
final author = usersTable.alias();
final rows = await db.post
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
`db.user.orderBy((u) => [u.posts.count().desc(), u.id.asc()])`. This compiles a
correlated count without loading posts. Normal nested results still use
[relationship selections](https://github.com/medz/dart-orm/blob/main/doc/relations.md) and their explicit loading strategies.

## Grouping, subqueries, CTEs and windows

```dart
final totals = db.post.groupBy((p) => [p.authorId])
    .having((p) => p.id.count().gt(1))
    .select((p) => (p.authorId, p.id.count()).row)
    .asCte('author_totals');
final active = await totals.query
    .orderBy((c) => [c.ref((p) => p.authorId).asc()]).get();

final ranks = await db.post.orderBy((p) => [p.id.asc()])
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
[typed raw SQL](https://github.com/medz/dart-orm/blob/main/doc/raw-sql.md). Raw fragments are trusted SQL supplied by the
application; do not interpolate user input into them.

## UNION and UNION ALL

Combine scalar expressions or SQL records with matching types:

```dart
final names = db.user.select((u) => u.email)
    .union(db.post.select((p) => p.title));
final List<String> result = await names.get();

final rows = db.user.select((u) => (u.id, u.email).row)
    .unionAll(db.post.select((p) => (p.id, p.title).row))
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
final upper = db.user.select((u) => u.email.map((v) => v.toUpperCase()));
final lower = db.post.select((p) => p.title.map((v) => v.toLowerCase()));
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
final recent = db.user.orderBy((u) => [u.id.desc()]).take(10)
    .select((u) => u.email)
    .unionAll(db.post.orderBy((p) => [p.id.desc()]).take(10)
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
would overflow. See [decimal arithmetic and averages](https://github.com/medz/dart-orm/blob/main/doc/decimals.md).
