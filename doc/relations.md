# Relationship queries

Declare relation members in your model's `relations` Record. Forward references
own the foreign key; reverse references belong to the model exposing them:

```dart
final Model user = model('users', (id: identity(), email: text()),
  relations: (u) => (posts: referencedBy(() => post),));

final post = model('posts', (id: identity(), title: text(), authorId: integer()),
  relations: (p) => (author: references(p.authorId, () => user),));
```

See [schema declarations](https://github.com/medz/dart-orm/blob/main/doc/authoring.md#keys-and-relationships)
for self references, composite keys and multiple references between the same models.

Generated relation getters describe a query. They do not read data until a
containing query executes. Select the exact related shape you need:

```dart
final cards = await db.post.select((p) => (
  p.title,
  p.author.select((a) => (a.id, a.email)
    .map((id, email) => (id: id, email: email))).required(),
).map((title, author) => (title: title, author: author))).get();
```

## Filtering parents through relationships

Use `where` to build the relationship's filter, then choose the SQL operation:

| Expression | Meaning for the filtered related rows |
| --- | --- |
| `relation.any()` | At least one row exists. |
| `relation.none()` | No row exists. |
| `relation.every(predicate)` | Every row makes `predicate` SQL TRUE. |
| `relation.count()` | Number of rows, returned as an SQL integer expression. |

These operations compile to correlated `EXISTS`, `NOT EXISTS` or `COUNT`
subqueries inside the containing statement. They do not load related objects or
issue extra statements. Collection loading with `many()` has separate query costs.

```dart
final authors = db.user.where((u) => u.posts
  .where((p) => p.title.like('%Dart%')).any());

final withoutDrafts = db.user.where((u) => u.posts
  .where((p) => p.title.eq('Draft')).none());

final frequentAuthors = db.user.where((u) => u.posts
  .where((p) => p.title.like('%Dart%')).count().gte(3));
```

The placement of `where` determines what it filters:

```dart
// Only users with a matching post; load all posts for each selected user.
final authors = await db.user
  .where((u) => u.posts.where((p) => p.title.like('%Dart%')).any())
  .select((u) => (u.email, u.posts.many()).row).get();

// Keep every user; include only matching posts in each user's list.
final users = await db.user.select((u) => (u.email, u.posts
  .where((p) => p.title.like('%Dart%')).many()).row).get();
```

An empty filtered list in the second query does not remove its user. To both
filter users and restrict loaded posts, declare the predicate in both places.
Filters never propagate implicitly between the root and its selections.

### One matching child or independent matches

Conditions inside one relationship filter must match the same child. Separate
existence tests may match different children:

```dart
// One post must contain both words.
db.user.where((u) => u.posts.where((p) =>
  p.title.like('%Dart%').and(p.title.like('%SQL%'))).any());

// One post contains Dart; another post may satisfy SQL.
db.user.where((u) => u.posts.where((p) => p.title.like('%Dart%')).any()
  .and(u.posts.where((p) => p.title.like('%SQL%')).any()));
```

Repeated `where` calls combine with AND and return new descriptions. An existing
relationship variable remains unchanged when a filtered copy is created. Fresh
getter calls create independent SQL occurrences, including self references and
multiple edges to the same table. Do not nest the same occurrence inside itself;
this reports `QUERY.ALIAS`. Fields captured from an unrelated query report
`QUERY.SCOPE` before execution. A correlated predicate may reference its enclosing
SQL query's fields. A batch-loaded selection runs in a separate statement and
cannot capture root fields beyond its declared relationship keys.

### Every, empty relationships and NULL

`every(predicate)` is true for an empty relationship. Require at least one row
separately when that matters:

```dart
db.user.where((u) => u.posts.any()
  .and(u.posts.every((p) => p.title.ne(''))));
```

SQL FALSE and SQL NULL both fail `every`. In contrast, `where` keeps only rows
whose condition is SQL TRUE. For example, with a nullable `tag` field,
`posts.every((p) => p.tag.eq('ready'))` fails if any tag is NULL. The expression
`posts.where((p) => p.tag.ne('ready')).none()` does not detect that NULL row.
Use `isNull()` or `isNotNull()` when NULL needs an explicit meaning.

Earlier filters define the set being checked: `posts.where(A).every(B)` means
all posts matching A must also satisfy B. It is true when no posts match A.
A nullable foreign key, or any NULL component of a composite foreign key, has no
matching related row; `any()` is false, `none()` and `every(...)` are true, and
`count()` is zero. Composite relationships compare all key columns together,
so matching IDs in different tenants remain separate.

### Nested and many-to-many predicates

Nest the same filtering pattern at each edge. With the association model below,
this selects users with an owner membership in the Core team:

```dart
db.user.where((u) => u.memberships.where((m) =>
  m.role.eq(MembershipRole.owner)
    .and(m.team.where((t) => t.name.eq('Core')).any())).any());
```

The association's business fields and the target's fields are checked in their
own scopes. A self reference such as `employee.manager` uses the same pattern;
no extra JOIN or object loading is required. Filtered counts can be nested too:
`team.memberships.where(...).count().gte(2)` remains a scalar SQL expression.

Use these terminal operations before relationship `take` or `skip`; pagination
reports `RELATION.AGGREGATE`. Ordering does not affect existence or counts.
Aggregate/window functions directly inside a relationship's WHERE report
`QUERY.AGGREGATE`; use a separate scalar subquery or a related `count()` for
aggregate conditions.

## Updating and deleting through relationship filters

The same root `where` works for reads, updates and deletes. Each operation uses
one statement containing the relationship subqueries:

```dart
final matched = db.post.where((p) => p.author
  .where((a) => a.email.like('%@example.com')).any());

final posts = await matched.get();
final changed = await matched.update((p) => [p.title.set('Archived')]).execute();
final removed = await matched.delete().execute();
```

Each execution evaluates the predicate against the database at that time. A read
followed by a write is not a frozen set of row IDs; use an explicit transaction
and the appropriate isolation or locking strategy when concurrent changes matter.
Only the root table is mutated. Foreign-key actions still follow the schema;
the ORM does not update related objects automatically.

Mutations accept a table and WHERE. Root JOINs, ordering, `take`/`skip`, grouping,
HAVING, DISTINCT, UNION and CTEs report `MUTATION.QUERY`. For a joined or paginated
write, explicitly select complete primary keys and mutate by those keys inside
a transaction. Include every component of a composite key. Mutation RETURNING
cannot load relationships; read them separately if needed.

MySQL rejects a typed UPDATE/DELETE when a subquery reads the mutation's own
physical table, including self references and a nested relation that returns to
the target table. Compilation reports `CAPABILITY.MUTATION_SELF_REFERENCE`
before execution. Ordinary filters through other tables still work. Select keys
in an explicit transaction, then mutate by those keys when this restriction
applies. SQLite, PostgreSQL and MariaDB support these self-referencing predicates.
See [MySQL's subquery restrictions](https://dev.mysql.com/doc/refman/8.4/en/subquery-restrictions.html).
The ORM does not automatically split the operation or force subquery materialization.

## Navigation without foreign keys

Use `references(..., constraint: false)` for read-only navigation when the
database does not enforce a foreign key:

```dart
final Model account = model('accounts', (
  tenant: integer(), id: integer(), label: text().nullable(),
), primaryKey: (a) => (a.tenant, a.id),
   relations: (a) => (entries: referencedBy(() => entry),));

final entry = model('entries', (
  id: identity(), tenant: integer().nullable(), owner: integer().nullable(),
), relations: (e) => (
  ownerAccount: references((e.tenant, e.owner), () => account, constraint: false),
));
```

`e.ownerAccount.one()` returns an optional `Account`; `a.entries.many()` returns
`Entry` rows. These members support the same projections, filters, pagination,
transactions, streams and subscriptions as constrained references.

Matching rows may be missing, and lookup keys may be nonunique. No unique
constraint or index is inferred. A declared primary/unique key permits automatic
to-one JOIN loading; otherwise `one()` uses a batch and checks cardinality.
`required()` reports missing matches. SQL equality does not match a composite key
containing NULL. Source and target keys must have matching types and codecs.

Write stored key values through the ordinary table API. A read-only relationship
provides no cascade, automatic connect/disconnect or existence check. Deleting a
target can leave dangling references. `watch()` tracks the tables read by the
selection without introducing foreign-key write effects.

Adding or renaming read-only navigation does not alter the physical snapshot.
Changing a constrained reference to `constraint: false` removes its foreign key
and requires a reviewed migration. Adding the constraint back can fail on dangling
data. Catalog import cannot discover these navigation rules; declare them yourself.
Relationships support same-database key equality, including self references.

## Many-to-many with business fields

An association model can carry a role, joining time or other data belonging to
the relationship:

```dart
enum MembershipRole { owner, member }

final team = model('teams', (id: identity(), name: text()),
  relations: (t) => (memberships: referencedBy(() => membership),));
final user = model('users', (id: identity(), name: text()),
  relations: (u) => (memberships: referencedBy(() => membership),));
final Model membership = model(
  'memberships',
  (
    teamId: integer(), userId: integer(),
    role: enumeration(MembershipRole.values, defaultValue: MembershipRole.member),
    joinedAt: dateTime(),
  ),
  primaryKey: (m) => (m.teamId, m.userId),
  relations: (m) => (
    team: references(m.teamId, () => team, onDelete: .cascade),
    user: references(m.userId, () => user, onDelete: .cascade),
  ),
  indexes: (m) => [index((m.userId, m.teamId), name: 'memberships_user_team')],
);
```

The navigation is `user.memberships → membership.team` or
`team.memberships → membership.user`. Select the relationship's payload together with the opposite endpoint:

```dart
final cards = await db.user.select((u) => (
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
  await tx.membership.create(teamId: 10, userId: 1,
      role: .set(MembershipRole.owner), joinedAt: DateTime.now());
  await tx.membership.byId(teamId: 20, userId: 1)
      .patch(role: .set(MembershipRole.member));
});
await db.membership.byId(teamId: 10, userId: 1).delete().execute();
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

Collection loading batches parent keys instead of issuing a query for each parent.
Within one parameter batch, the membership-card example uses one root statement
and one child statement; the child joins the team name. An empty root result needs
no child statement. A nested collection adds another loading stage, and parameter
limits can split a stage into multiple statements.

Use [query inspection and observations](https://github.com/medz/dart-orm/blob/main/doc/observability.md)
to see the actual statements and row counts for your selection. For a complete
association model, see the [company example](https://github.com/medz/dart-orm/blob/main/example/company/README.md).

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
final query = db.post.select((p) => (
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
final users = await db.user.orderBy((u) => [u.id.asc()]).take(20)
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

`compile()` exposes the root SQL, including selected to-one JOINs. It does not
pretend to contain the later collection statements. `inspect()` also describes
conditional child SQL templates, output/key slots, joins and batch capacity;
see [plans and observations](https://github.com/medz/dart-orm/blob/main/doc/observability.md). `onQuery` reports every
executed statement and fetched row count. Streaming uses these same strategies
per root batch; see [execution](https://github.com/medz/dart-orm/blob/main/doc/execution.md).

Multiple statements can observe different snapshots under PostgreSQL Read
Committed. Use an explicit Repeatable Read transaction when root and collection
queries must share a snapshot. A JOIN-only selection is one statement.
