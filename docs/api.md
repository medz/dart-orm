# API and mental model

Start with a Record declaration, generate its client, choose a database entrypoint,
and use the generated table getters. Each query belongs to that database view.
Migrations have a separate, fixed history for the chosen engine.

## Imports

SQLite uses `sqlite.dart` on native platforms and the web. `SqliteOptions.memory()`
is portable. `persistent(name, nativePath: ...)` uses the native path or the named
browser database. Flutter bundles its browser resources automatically; see
[SQLite Web setup](sqlite-web.md). Platform transports are internal.

| File being written | Import | Purpose |
| --- | --- | --- |
| Schema declaration | `package:orm/schema.dart` | Record annotations, entities, keys and relations |
| Application | Generated `schema.orm.dart` plus `package:orm/sqlite.dart`, or `postgres.dart` | Row aliases, table getters, driver configuration and the portable query API |
| Shared queries/codecs without a driver | `package:orm/orm.dart` | Portable runtime, typed SQL, codecs and explicit driver/manual-table extension interfaces |
| Migration or snapshot | `package:orm/migrate.dart` | Historical schema primitives, steps, checksums and migration execution |
| Project migration CLI | `package:orm/migrate_cli.dart` | Statically imported history and project-owned connection configuration |
| Generation scripts | `package:orm/generate.dart` | Analyze declarations and write derived Dart files |
| build_runner configuration | `package:orm/builder.dart` | Builder factories only |

Generated clients export their Record row aliases, but not `entity()` declaration
values or unrelated application helpers. Types used inside rows, such as a custom
ID or enum, remain owned by their defining library. Import that library when
constructing those values. Use import prefixes for multiple generated clients.

Runtime/schema/migration imports do not pull in the analyzer, build system or a
native database driver. `sqlite.dart` selects its platform implementation;
PostgreSQL retains its own entrypoint and connection options.
The single package still declares tooling dependencies for its CLI and builders;
`pub get` resolves them. This import boundary avoids runtime initialization and
compilation dependencies, not the dependency-download cost of one package.

## Three kinds of Dart files

`schema.dart` is the current declaration. `schema.orm.dart` and
`schema.snapshot.dart` are reproducible outputs; regenerate them after editing the
declaration. `migrations/m0001_*.dart` is reviewed history. It contains its own frozen
physical schema and fixed fingerprint, independent of the latest models.

Generation validates the structure and types. A migration history selects SQLite
or PostgreSQL and validates that engine's capabilities. A SQLite-only declaration
may use a virtual indexed column; PostgreSQL restrictions should not prevent its
generation. The selected engine still rejects unsupported DDL before applying it.
Changing a connection URL does not convert a migration history.

## Shape, identity and selection

The Record is a Dart value. Two tables can have the same Record shape while
remaining distinct SQL sources. `table.alias()` creates a new occurrence for joins
and self joins. Capturing a field from an unrelated query is a scope error.

`select((u) => u.email)` returns `List<String>` from `get()`. `.row` composes SQL
expressions into a positional Record; `.map(...)` shapes decoded values into a
named Record or DTO. A Dart mapper does not become a SQL expression. Runtime
`fields({...})` selection deliberately returns `Map<String, Object?>`.

`alias.optional(selection)` checks that alias's presence. It does not prove another
left-joined alias exists. Give each optional alias its own guard, or use nullable
expressions. Relationships follow the same rule: `one()` can be absent, `required()`
checks presence, and `many()` loads a collection. [Relationship execution](relations.md)
documents joins, batched queries and consistency boundaries.

## Preparing and executing

`where`, `select`, `orderBy`, `take`, `skip` and `map` return new descriptions.
Repeated `where` adds predicates; `orderBy`, `take` and `skip` replace their own
settings. `compile()`/`inspect()` perform no I/O. `get()`/`first()`/`single()` execute
reads; a stream acquires a cursor when listened to.

Generated `create(...)` and `patch(...)` execute immediately. `insert(...)`,
`insertMany(...)`, `update(...)` and `delete()` prepare mutations; call `execute()`
or `returning(...).get()`. Prepared inserts evaluate client defaults once when
constructed. Re-executing the prepared insert reuses those values.

`Change.keep()` omits an assignment, `.set(null)` writes SQL NULL to a nullable
field, and `.defaultValue()` requests the database default. An empty update is an
error. `RETURNING` returns scalar SQL projections; query relationships afterward.
For statement deadlines or cancellation, use the prepared mutation's execution
options. [Defaults](defaults.md) and [execution](execution.md) specify the limits.

## Connection and transaction ownership

The root Database owns its driver. `session` borrows one connection; `transaction`
borrows one connection and commits or rolls back the callback's writes. Only use
the callback's `tx` to construct that transaction's queries. Subqueries, CTEs and
UNION operands must all use the same view. Use `savepoint` for a recoverable nested
unit; borrowed views expire at callback completion.

Pass `tx` into helper functions. Calling the captured root `db` separately inside
the callback requests separate work: a pool may run it outside the transaction,
and a single-connection SQLite driver may wait on the callback's own lease.
Composition checks reject mixed query descriptions; they do not rewrite unrelated
root calls into transaction calls.

```dart
await db.transaction((tx) async {
  final user = await tx.users.create(email: 'seven@example.com');
  await tx.posts.create(
    authorId: user.id,
    title: 'First post',
    createdAt: DateTime.now(),
  );
});
```

Await every operation before returning from the callback. Batch inserts use one
transaction across chunks. A normal query with batched relationships reuses its
connection but does not automatically create a snapshot transaction. Choose an
appropriate explicit transaction when a consistent multi-query snapshot matters.
Query observations expose actual SQL and transaction statements.

Raw SQL remains explicit: bind values in `SqlCommand` or typed `sql` expressions,
declare affected/read tables for subscriptions, and use reviewed migration steps
for schema changes. The ORM does not infer an object graph, external writes,
automatic transaction replay or destructive renames.

Custom codecs, manual Table definitions and Driver implementations are explicit
extension contracts. Their authors supply the correct storage mapping and native
behavior. Dart types cannot prove that a live external schema still matches those
definitions; use catalog verification when that boundary matters.
