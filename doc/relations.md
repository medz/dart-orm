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

## Many-to-many with business fields

An explicit association table gives each membership its own role and joining time.
The [teams example](https://github.com/medz/dart-orm/blob/main/example/teams/schema.dart) uses two foreign keys and a
composite primary key, with no artificial membership ID:

```dart
enum MembershipRole { owner, member }
typedef Membership = ({
  int teamId,
  int userId,
  @Default.sql("'member'") MembershipRole role,
  DateTime joinedAt,
});
final memberships = entity<Membership>();
final membershipKey = memberships.primaryKey((m) => (m.teamId, m.userId));
final team = memberships.key((m) => m.teamId)
    .references(teams.key((t) => t.id), inverse: 'memberships', onDelete: .cascade);
final user = memberships.key((m) => m.userId)
    .references(users.key((u) => u.id), inverse: 'memberships', onDelete: .cascade);
```

`teams` and `users` are separately declared entities. The resulting navigation is
`user.memberships → membership.team`, or `team.memberships → membership.user`.
Select the relationship's payload together with the opposite endpoint:

```dart
final cards = await db.users.select((u) => (
  u.name,
  u.memberships.orderBy((m) => [m.joinedAt.desc(), m.teamId.desc()]).take(2)
    .select((m) => (m.team.select((t) => t.name).required(), m.role)
      .map((team, role) => (team: team, role: role))).many(),
).map((name, teams) => (name: name, teams: teams))).get();
```

This returns a typed list of user names and membership cards. Each membership's
role belongs to that association; two users sharing a team can have different
roles. An empty relationship returns `[]`. Use a deterministic tie breaker with
per-parent pagination. Root pagination is independent of the membership limits.

Create and update memberships through their ordinary generated table API:

```dart
await db.transaction((tx) async {
  await tx.memberships.create(teamId: 10, userId: 1,
      role: .set(MembershipRole.owner), joinedAt: DateTime.now());
  await tx.memberships.byId(teamId: 20, userId: 1)
      .patch(role: .set(MembershipRole.member));
});
await db.memberships.byId(teamId: 10, userId: 1).delete().execute();
```

The composite key rejects duplicate memberships. Both endpoints must already
exist, or be created earlier in the same transaction. Unlinking deletes only the
association. Deleting an endpoint follows the declared cascade, removing its
memberships while retaining opposite endpoints. Composite-key `onConflictUpdate`
can change a role while leaving the original joining time unchanged. There are
no hidden object-graph saves or implicit writes through a navigation getter.

The example declares one index beginning with `user_id` for reverse traversal;
its primary key already begins with `team_id`. Additional ordering indexes depend
on measured query patterns, not an index added automatically for every relation.

Real SQLite/PostgreSQL checks establish these statement counts for the fixture,
within the available parameter capacity:

| Selection | SQL statements | Rows returned by each statement |
| --- | --- | --- |
| Four users, latest two memberships each, joined team names | 2 | 4, 5 |
| Three teams, second member per team, joined user names | 2 | 3, 2 |
| Four users, all memberships/teams, each team's complete roster | 3 | 4, 6, 6 |
| Membership counts, every-member predicate and team-existence predicate | 1 | 4 |
| Empty root result with a membership selection | 1 | 0 |

Parameter chunking adds statements: with a deliberately limited five-parameter
driver, a member-role filter and per-user limit execute one root plus two child
statements. Roster lookups deduplicate shared team keys. These checks establish
returned volume and statement counts, not throughput, physical database page reads
or optimizer cost. Snapshot-consistency rules below still apply to multi-statement
loads. `watch()` observes committed association and selected endpoint changes.

Run the self-contained SQLite example:

```sh
dart run bin/orm.dart generate example/teams/schema.dart
dart run example/teams/main.dart
```

It prints the selected records, SQL statement count and returned row counts. The
same generated schema is exercised against PostgreSQL by `many_to_many_test.dart`.

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
pretend to contain the later collection statements. `inspect()` also describes
conditional child SQL templates, output/key slots, joins and batch capacity;
see [plans and observations](https://github.com/medz/dart-orm/blob/main/doc/observability.md). `onQuery` reports every
executed statement and fetched row count. Streaming uses these same strategies
per root batch; see [execution](https://github.com/medz/dart-orm/blob/main/doc/execution.md).

Multiple statements can observe different snapshots under PostgreSQL Read
Committed. Use an explicit Repeatable Read transaction when root and collection
queries must share a snapshot. A JOIN-only selection is one statement.
