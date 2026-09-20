# API and mental model

Start with an immutable Dart class, generate its client, choose a database entrypoint,
and use the generated table getters. Each query belongs to that database view.
Migrations have a separate, fixed history for the chosen engine.

## Imports

SQLite uses `sqlite.dart` on native platforms and the web. `SqliteOptions.memory()`
is portable. `persistent(name, nativePath: ...)` uses the native path or the named
browser database. Flutter bundles its browser resources automatically; see
[SQLite Web setup](sqlite-web.md). Platform transports are internal.

| Module or use | Import | Purpose |
| --- | --- | --- |
| Values | `package:orm/values.dart` | Codecs, decimal/temporal/domain value contracts |
| Driver contracts | `package:orm/driver.dart` | SQL commands, raw results, connections and capabilities |
| Database adapters | `package:orm/drivers/sqlite.dart`, `postgres.dart`, `mysql.dart`, `mariadb.dart` under `drivers/` | Raw drivers without ORM models |
| Raw SQL execution | `package:orm/runtime.dart` | `SqlDatabase`, sessions, transactions, cursors and observations |
| Physical schema | `package:orm/schema_model.dart` | Columns, keys, constraints and indexes without execution |
| Typed SQL | `package:orm/sql.dart` | Query construction, typed projections and `SqlBuilder` without a connection runtime |
| ORM execution | `package:orm/orm.dart` | `Database` binds typed queries to `SqlDatabase` and adds subscriptions |
| Schema declaration | `package:orm/schema.dart` | Model annotations, entities, keys and relations |
| Application convenience | Generated `schema.orm.dart` plus `package:orm/sqlite.dart`, `postgres.dart`, `mysql.dart` or `mariadb.dart` | Model types, table getters and the chosen adapter |
| Migration or snapshot | `package:orm/migrate.dart` | Physical history, steps, checksums and execution against `SqlDatabase` |
| Project CLI | `package:orm/cli.dart` | `OrmConfig`, static history and unified project commands |
| Migration-only executable | `package:orm/migrate_cli.dart` | Programmatic commands with a static history and raw connection factory |
| Generation scripts | `package:orm/generate.dart` | Analyze declarations and write derived Dart files |
| build_runner configuration | `package:orm/builder.dart` | Builder factories only |

Generated clients export their declared model classes (or explicit Record aliases), but not `entity()` declaration
values or unrelated application helpers. Types used inside rows, such as a custom
ID or enum, remain owned by their defining library. Import that library when
constructing those values. Use import prefixes for multiple generated clients.

These are real dependency boundaries within one package. `sql.dart` does not
import the connection runtime or ORM, and `runtime.dart` does not import the
query builder. `migrate.dart` uses raw sessions and physical metadata without
model declarations or generated query code. None of these runtime/schema imports
pull in the analyzer, build system or a concrete database adapter. `sqlite.dart`
selects its platform implementation; each server engine has its own options.
The single package still declares tooling dependencies for its CLI and builders;
`pub get` resolves them. This import boundary avoids runtime initialization and
compilation dependencies, not the dependency-download cost of one package.

For raw SQL, construct `SqlDatabase(await SqliteDriver.open(options))` from
`runtime.dart` and `drivers/sqlite.dart`. Add typed execution later with
`Database.fromSql(raw)`; it uses the same runtime rather than another pool.
`db.sql` exposes that runtime to migrations and catalog operations.

For offline compilation, import `sql.dart` and a generated client:

```dart
final command = SqlBuilder(SqlDialect.postgres)
    .users.where((u) => u.email.eq('seven@example.com'))
    .select((u) => u.id)
    .compile();
// command.sql and separately bound command.parameters; no connection opened.
```

Executing an unbound builder fails with `QUERY.UNBOUND`. Generated table getters
and named SQL bindings target `QueryContext`, which both `SqlBuilder` and the ORM
implement. Field and result types remain static; SQL capabilities and a missing
named-query engine variant are checked against the chosen context before I/O.

## Three kinds of Dart files

`schema.dart` is the current declaration. `schema.orm.dart` and
`schema.snapshot.dart` are reproducible outputs; regenerate them after editing the
declaration. `migrations/m0001_*.dart` is reviewed history. It contains its own frozen
physical schema and fixed fingerprint, independent of the latest models.

Generation validates the structure and types. A migration history selects SQLite,
PostgreSQL, MySQL or MariaDB and validates that engine's capabilities. A SQLite-only declaration
may use a virtual indexed column; PostgreSQL restrictions should not prevent its
generation. The selected engine still rejects unsupported DDL before applying it.
Changing a connection URL does not convert a migration history.

## Shape, identity and selection

The declared class is the complete row type. A `User` and an unrelated class with
identical fields remain different Dart types. Record projections remain
structural. Two tables can use the same class or Record shape while remaining
distinct SQL sources. `table.alias()` creates a new occurrence for joins
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

The root `SqlDatabase` owns its driver; `Database` uses that runtime. `session` borrows one connection; `transaction`
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
