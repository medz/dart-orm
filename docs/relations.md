# Relationship queries

Generated relation getters describe a query. They do not read data until a
containing query executes. Select the exact related shape you need:

```dart
final cards = await db.posts.select((p) => (
  p.title,
  p.author.select((a) => (a.id, a.email)
    .map((id, email) => (id: id, email: email))).required(),
).map((title, author) => (title: title, author: author))).get();
```

## Navigation without foreign keys

Use `relatesTo()` for a read-only navigation edge when the database does not
enforce a foreign key. It uses the same checked key selectors and generated
query API as `references()`:

```dart
typedef Account = ({int tenant, int id, String? label});
typedef Entry = ({@Id() int id, int? tenant, int? owner});
final accounts = entity<Account>();
final entries = entity<Entry>();
final accountKey = accounts.primaryKey((a) => (a.tenant, a.id));
final ownerAccount = entries.key((e) => (e.tenant, e.owner))
    .relatesTo(accounts.key((a) => (a.tenant, a.id)), inverse: 'entries');
```

After generation, `e.ownerAccount.one()` returns an optional Account and
`a.entries.many()` returns a list of Entry records. Normal projections, filters,
correlated predicates, per-parent pagination, transactions, streams and watches
apply. Generated getter documentation identifies the unconstrained edge.

Matching rows may be missing, and lookup keys may be nonunique. `relatesTo()`
does not infer a unique constraint or an index. Only an independently declared
primary/unique key permits automatic to-one JOIN loading; otherwise `one()`
uses a batch and checks cardinality. `required()` still reports missing matches.
SQL equality does not match a composite key containing NULL. The key selectors
must retain matching Dart and storage types, column order and arity.

The edge itself exposes query operations. Create or change stored key values
through the normal table write API, using a transaction when needed. There is no
implicit connect, disconnect, cascade or existence validation, and `relatesTo()`
has no `onDelete` option. Deleting a target can leave stored references dangling.
`watch()` tracks the tables read by a selection, including joined or batched
targets, without inventing foreign-key write effects.

Adding, renaming or removing a query-only edge does not change the physical
schema snapshot or emit migration DDL. Replacing an existing `references()` with
`relatesTo()` does change the snapshot: removing that database constraint must
go through a reviewed migration. Switching back can fail on dangling data; repair
the data before retrying. Catalog import cannot discover unconstrained navigation
rules, so declare them explicitly in the imported schema. This API covers
same-database key equality, including self relations; it does not implement
cross-database queries or arbitrary relationship predicate declarations.

## Single relationships

`one()` returns an optional related result. `required()` checks that a related
row exists and reports `RELATION.MISSING` if it does not. Presence is checked
independently of the selected values: a present row whose selected nullable
column is NULL can still satisfy `required()`.

The default `ToOneStrategy.automatic` uses a LEFT JOIN when the relationship
keys cover a declared primary key, unique key or simple unique index on the
target. That proves at most one match, so joining does not multiply root rows
or change root pagination. Nested to-one projections use the same statement.

You can select the strategy explicitly:

```dart
p.author.one(strategy: .join);
p.author.required(strategy: .batch);
```

`.join` rejects keys that do not prove target uniqueness with
`RELATION.JOIN_KEY`. Without that proof, `.automatic` uses batch loading and
checks cardinality. More than one visible result produces
`RELATION.CARDINALITY`. The uniqueness proof uses the schema declaration, so
the actual database must enforce those declared constraints; use schema
verification when adopting an existing database.

Relation filters stay inside the JOIN condition and do not remove root rows.
`one()` represents a filtered-out target as null; `required()` reports it during
decoding. Selecting an all-null record still distinguishes a present record
from an absent relationship using a separate marker. That marker avoids user
column names, including SQLite's case-insensitive identifier collisions.

A proven unique match has at most one row. `take(0)` and `skip(1)` therefore
produce an absent joined relation. Ordering does not change that unique match.
To deliberately select one row from a collection, use explicit ordering and
`take(1).one(strategy: .batch)`.

Each generated getter produces a fresh table occurrence. Use fresh getter calls
when selecting differently filtered views of the same relationship:

```dart
final query = db.posts.select((p) => (
  p.author.where((a) => a.score.gt(10)).one(),
  p.author.where((a) => a.score.lte(10)).one(),
).map((high, low) => (high: high, low: low)));
```

Reusing the identical edge with identical predicates deduplicates its JOIN.
Reusing one edge with conflicting predicates produces `RELATION.ALIAS`; use
fresh getters or select a batch strategy for the separate view.

## Collections and composite keys

`many()` uses batch loading and always returns a typed list. Empty relationships
are empty lists, and an empty root result performs no child queries.

```dart
final users = await db.users.orderBy((u) => [u.id.asc()]).take(20)
  .select((u) => (u.id, u.posts
    .orderBy((p) => [p.createdAt.desc(), p.id.desc()])
    .take(3).select((p) => p.title).many())
    .map((id, titles) => (id: id, titles: titles)))
  .get();
```

There is one root statement plus statements per relation and parameter chunk,
not per parent. Duplicate parent keys share a lookup. A composite key with any
NULL component does not match through SQL equality and is excluded from child
lookup batches. Composite matches preserve tuple identity, so equal IDs in
different tenants do not mix.

Chunk capacity includes all bound parameters: key width, filters, projections,
nested joins and per-parent window bounds. Large composite batches use row-value
IN rather than deep OR trees. SQLite uses a VALUES subquery; PostgreSQL uses a
row-constructor list so column types determine parameter types. See the
[SQLite row-value rules](https://www.sqlite.org/rowvalue.html) and
[PostgreSQL VALUES type rules](https://www.postgresql.org/docs/current/queries-values.html).

Collection `take/skip` applies per parent using SQL window partitioning. It
requires explicit ordering and window-function capability. The ORM does not
fetch every child and discard excess rows in Dart. A collection's selected
to-one relationships can join into that same child statement. Collections below
a joined parent load in subsequent batches using the joined parent keys.

`any/none/every/count` compile to correlated SQL and do not materialize related
objects. `every` is true for an empty collection; a predicate returning SQL
UNKNOWN counts as unsatisfied. Use `any` as well when an empty relationship
should be excluded.

`compile()` exposes the root SQL, including selected to-one JOINs. It does not
pretend to contain the later collection statements. `onQuery` reports every
executed statement and fetched row count. Streaming uses these same strategies
per root batch; see [execution](execution.md).

Multiple statements can observe different snapshots under PostgreSQL Read
Committed. Use an explicit Repeatable Read transaction when root and collection
queries must share a snapshot. A JOIN-only selection is one statement.
