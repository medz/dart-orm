# Choose an entrypoint

Annotate ordinary DTO classes, generate their typed client, choose a database entrypoint,
and use the generated table getters. Each query belongs to that database view.
Migrations have a separate, fixed history for the chosen engine.

Import the generated client, the engine, and the capabilities your application uses:

```dart
import 'package:my_app/models.orm.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';

Future<void> main() async {
  final engine = await sqlite(const SqliteOptions.file('app.sqlite'));
  final db = Database.fromSql(engine);
  try {
    final List<String> titles = await db.task
        .where((t) => t.done.eq(.value(false)))
        .select((t) => t.title)
        .get();
    print(titles);
  } finally {
    await db.close();
  }
}
```

The engine factory returns an owning `SqlDatabase`. `Database.fromSql(engine)` adds
a typed model view over the same runtime and connection resources; closing either
root view closes those resources. PostgreSQL's
`postgres(options)` creates a lazy pool synchronously; it first connects when
an operation acquires a connection. The other connection helpers return futures
that complete after opening and validating their connection.

## Imports

SQLite uses `sqlite.dart` on native platforms and the web. `SqliteOptions.memory()`
is portable. `persistent(name, nativePath: ...)` uses the native path or the named
browser database. Flutter bundles its browser resources automatically; see
[SQLite Web setup](https://github.com/medz/dart-orm/blob/main/doc/sqlite-web.md). Platform transports are internal.

| Module or use | Import | Purpose |
| --- | --- | --- |
| Values | `package:orm/values.dart` | Codecs, decimal/temporal/domain value contracts |
| Driver contracts | `package:orm/driver.dart` | SQL commands, raw results, connections and capabilities |
| Engine adapters | `package:orm/sqlite.dart`, `postgres.dart`, `mysql.dart`, `mariadb.dart` | Engine factory, driver, options and backend marker |
| SQL | `package:orm/sql.dart` | `SqlDatabase`, typed expressions, queries, selections, SQL descriptions, sessions and observations |
| Physical schema | `package:orm/schema_model.dart` | Columns, keys, constraints and indexes |
| Models | `package:orm/orm.dart` | `Database`, model queries, typed writes and subscriptions |
| Declarations | `package:orm/schema.dart` | `@Model`, `@Projection`, column, key and relation annotations |
| Migration or snapshot | `package:orm/migrate.dart` | Frozen history, steps, checksums and execution against `SqlDatabase` |
| Project configuration | `package:orm/config.dart` | `defineConfig` with direct model/output/history paths and a lazy connection factory |
| Package CLI | `package:orm/cli.dart` | `runOrmCli(arguments)` loads runnable project configuration |
| Migration-only executable | `package:orm/migrate_cli.dart` | Programmatic commands with a static history and raw connection factory |
| Generation scripts | `package:orm/generate.dart` | Analyze declarations and write derived Dart files |
| build_runner configuration | `package:orm/builder.dart` | Builder factories only |

Generated clients import and re-export the original annotated DTO classes and add
typed table getters. They do not define replacement row classes. Unrelated
application helpers remain in their source libraries. Types used inside rows,
such as a custom ID or enum, remain owned by their defining library. Import that library when
constructing those values. Use import prefixes for multiple generated clients.

Each shared type has one public owner. Import `values.dart` for codecs and domain
values, `driver.dart` for execution options and dialects, and `schema_model.dart`
for physical metadata. Generated files import their dependencies explicitly.
`select` is the `SelectQuery` extension from `sql.dart`; import it in every
library that selects query results, including ordinary generated model queries.
Importing only `orm.dart` and a generated client does not bring `select` into
scope. Neither library re-exports the SQL module.
The retired `runtime.dart` and `drivers/` facades have no compatibility aliases.

The SQL layer does not depend on model queries or generation. Migrations use raw
sessions and physical metadata without current model declarations. Runtime
libraries do not import analyzer/build tooling or choose a concrete adapter.
The single package still resolves its tooling dependencies during `pub get`.
Import public paths; `lib/src/` is implementation detail.

For raw SQL, use `final engine = await sqlite(options)` and import `sql.dart`
for `engine.raw(...)`, `engine.query(...)` and streaming. Add the optional model
view with `Database.fromSql(engine)`. `db.sql` exposes that same runtime to
migrations and catalogs. This does not open a second pool.

For offline compilation, import `sql.dart` and a generated client:

```dart
final command = SqlBuilder(SqlDialect.postgres)
    .user.where((u) => u.email.eq(.value('seven@example.com')))
    .select((u) => u.id)
    .compile();
// command.sql and separately bound command.parameters; no connection opened.
```

Executing an unbound builder fails with `QUERY.UNBOUND`. Generated table getters target `QueryContext`, implemented by `SqlBuilder` and
the ORM. Raw `Sql` descriptions are independent of a context: compile with
`statement.compile(capabilities)`, or execute with `db.raw(statement)` and
`db.query(statement.returns(resultShape))`. Types remain static; missing engine
variants fail before I/O. See [raw SQL](https://github.com/medz/dart-orm/blob/main/doc/raw-sql.md).

## Three kinds of Dart files

`models.dart` contains the current DTO declarations. `models.orm.dart` and
`models.snapshot.dart` are reproducible outputs; regenerate them after editing the
declaration. `migrations/m0001_*.dart` is reviewed history. It contains its own frozen
physical schema and fixed fingerprint, independent of the latest models.

Generation validates the structure and types. A migration history selects SQLite,
PostgreSQL, MySQL or MariaDB and validates that engine's capabilities. A SQLite-only declaration
may use a virtual indexed column; PostgreSQL restrictions should not prevent its
generation. The selected engine still rejects unsupported DDL before applying it.
Changing a connection URL does not convert a migration history.

## Shape, identity and selection

Each original annotated class is its complete row type. A `User` and an unrelated class with
identical fields remain different Dart types. Record projections remain
structural. Two models can declare identical field shapes while keeping distinct row types
and SQL table identities. `table.alias()` creates a new occurrence for joins
and self joins. Capturing a field from an unrelated query is a scope error.

`select((u) => u.email)` returns `List<String>` from `get()`. `.row` composes SQL
expressions into a positional Record; `.map(...)` shapes decoded values into a
named Record or DTO. A Dart mapper does not become a SQL expression. Runtime
`fields({...})` selection deliberately returns `Map<String, Object?>`.

`alias.optional(selection)` checks that alias's presence. It does not prove another
left-joined alias exists. Give each optional alias its own guard, or use nullable
expressions. Relationships follow the same rule: `one()` can be absent, `required()`
checks presence, and `many()` loads a collection. [Relationship execution](https://github.com/medz/dart-orm/blob/main/doc/relations.md)
documents joins, batched queries and consistency boundaries.

## Preparing and executing

`where`, `select`, `orderBy`, `take`, `skip` and `map` return new descriptions.
Repeated `where` adds predicates; `orderBy`, `take` and `skip` replace their own
settings. `compile()`/`inspect()` perform no I/O. A stream acquires a cursor when
listened to. Choose the read operation by the expected result:

| Operation | Empty result | One row | Multiple rows |
| --- | --- | --- | --- |
| `get()` | Empty list | List of one | List of all |
| `first()` | Cardinality error | The row | First row |
| `firstOrNull()` | null | The row | First row |
| `single()` | Cardinality error | The row | Cardinality error |
| `singleOrNull()` | null | The row | Cardinality error |

A selected SQL NULL still counts as a row. Strict reads return that null when
their result type allows it. Use a Record projection if an optional scalar read
must distinguish an absent row from a row containing null.

Generated `create(...)` accepts literal field values and immediately returns a
complete model. Omitted optional values use their declared defaults; explicit
null remains distinct from omission. `patch(...)` updates named literal fields
and returns the affected-row count. `update(input)`, `insert(input)`,
`insertMany(inputs)` and `delete()` also execute and return `Future<int>`.
Await these methods directly:

```dart
await db.user.byId(id).patch(nickname: null);
await db.user.byId(id).delete();
```

Named `create` and `patch` accept only model fields. For execution options use
typed inputs with `update(input, options: ...)`, `insert(input, options: ...)`,
or the advanced `plan` path. No model field name is reserved for those controls.
Typed insert and patch inputs are immutable data that can be passed between
functions or combined before executing:

```dart
final request = userPatch(nickname: null);
final policy = userPatch.values(score: .expression((u) => u.score.plus(1)));
final patch = userPatch.overlay([request, policy]);
if (!userPatch.isEmpty(patch)) {
  await db.user.byId(id).update(patch);
}
```

Use `.plan` for inert write descriptions, RETURNING and explicit preparation.
Constructing a plan or an insert/update/delete description evaluates no input
expressions or client defaults and executes no SQL:

```dart
final insert = db.user.plan.insert(userInsert(email: 'new@example.com'));
final prepared = insert.prepare();
print(prepared.compile().sql);
await prepared.execute();

final nickname = await db.user.byId(id).plan
    .update(userPatch(nickname: null))
    .returning().select((u) => u.nickname)
    .single(options: options);
```

`overlay` applies layers in order; a later supplied value wins and `.keep()`
leaves the earlier intent intact. Use the generated factory's `.values(...)`
for `WriteValue.set`, `.keep`, `.databaseDefault`, and `.expression` intents.
`userInsert.overlay(base, patches)` preserves insert-only fields such as a
generated identity. Input objects expose data fields without composition methods.

Each terminal on a planned write prepares fresh assignments and defaults. Explicit
`prepare()` validates and freezes a core `Mutation` or `BatchInsert`; repeated
execution of that prepared object reuses its values and retains conflict clauses,
SQL inspection and native RETURNING. Structural, scope and known capability
checks precede default factories. Known query shape, session ownership and
execution options are checked before input callbacks. An invalid expression AST
produced by a callback can only be rejected after it runs. Dart callback, codec
and factory effects cannot be rolled back. Cancellation and expired sessions
reject before preparation at execution terminals; explicit `prepare()` has no
execution options and freezes values when called.

Byte storage (`Uint8List`) is copied once when an encoded parameter is bound.
Prepared writes and their compiled parameters expose that read-only snapshot,
including through its buffer views; attempts to modify it throw
`UnsupportedError`. Generated literal inputs, expression callbacks and client
defaults bind during preparation. An expression built beforehand with `value(...)`
already owns its snapshot. Other mutable storage returned by a custom codec remains
caller-owned and must stay stable for every replay; preparation does not deep-copy
application objects. `Codecs.bytes` itself retains its normal encode/decode ownership.

`insert.row()` returns a complete model using native RETURNING or a transactional
primary-key readback. `write.returning().select(selection).get()` requires native
RETURNING. The whole write executes before cardinality checks; an empty update
is an error. `plan.insertMany(inputs).prepare().returning(selection)` exposes batch
RETURNING. An owned batch transaction decodes results before committing.

RETURNING can combine scalar subqueries and relationship `count`/`any` expressions
with the changed row in one statement, preserving the selected Dart result type:

```dart
final ({int id, String? nickname, int posts, bool published}) changed =
    await db.user.byId(id).plan
        .update(userPatch(nickname: 'Reviewed'))
        .returning()
        .select((u) => (
          u.id,
          u.nickname,
          u.posts.count(),
          u.posts.where((p) => p.title.eq(.value('Published'))).any(),
        ).map((id, nickname, posts, published) => (
          id: id, nickname: nickname, posts: posts, published: published,
        )))
        .single();
```

This example uses the generated [user/post schema](https://github.com/medz/dart-orm/blob/main/example/schema.dart).
Related row selections (`one`/`many`) need a subsequent query; top-level aggregate
and window functions are rejected. Subqueries follow the engine's native
RETURNING visibility rules. In particular, [SQLite](https://www.sqlite.org/lang_returning.html#self_referential_subqueries_are_indeterminate) does not define results for
self-referential subqueries that read rows changed by the same statement. Use an
explicit transaction with a subsequent SELECT when that result must be defined.

**Unreleased:** prepared batches support SQLite/PostgreSQL conflict updates with
one explicit update rule shared by every input row:

```dart
final BatchInsert<EmployeeFields> upsert = tx.employee.plan
    .insertMany(inputs)
    .prepare()
    .onConflictUpdate(
      target: (e) => [e.email],
      set: (existing, incoming) => [
        existing.name.setExpression(incoming.name),
        existing.departmentId.setExpression(incoming.departmentId),
      ],
    );
final BatchReturning<Employee> returning = upsert.returning(employeeTable.selectRow);
final List<Employee> employees = await returning.get();
```

The [directory sync example](https://github.com/medz/dart-orm/blob/main/example/company/sync.dart)
shows the complete business function. Only listed fields change on conflict;
generated IDs and other stored fields are retained. Copying an incoming field
copies its proposed insert value, including an insert default when omitted.
It does not interpret omission as “keep the existing value.” For per-row patch
policies, form groups with the same update rule or keep separate writes.
Nullable incoming fields distinguish explicit NULL from declared database defaults.

Preparation freezes client defaults once per input row. Adding the conflict rule,
compiling and replaying the prepared batch do not resample them. All chunks are
compiled and their parameter budgets checked before the first statement runs;
conflict and RETURNING parameters count toward each chunk's limit. The chunks
share one transaction; a failed later statement rolls earlier changes back and
prevents a caught SQL error from committing a partial batch.

Each chunk is a separate native statement. PostgreSQL rejects updating the same
row twice within one statement; separate chunks can update it again. SQLite can
process repeated keys within one statement. Changing parameter limits or input
column shapes can therefore change repeated-key outcomes. There is no cross-chunk
deduplication or application-side check that reproduces database equality,
collation or unique-index rules. Supply nonconflicting keys under those rules
when behavior must be independent of chunking.

RETURNING order is not an input-row mapping. `execute()` sums native affected-row
counts rather than normalizing them across engines or counting distinct keys.
MySQL/MariaDB targeted conflicts and drivers without RETURNING reject these
respective operations before I/O; no fallback is implied. SQLite also rejects an
upsert row whose insert columns all use database defaults, because its
`DEFAULT VALUES` form cannot carry ON CONFLICT. An empty valid batch does no I/O,
but still validates the requested conflict and RETURNING capabilities.

**Unreleased:** SQLite/PostgreSQL insert plans can describe duplicate suppression
without freezing values first:

```dart
final claim = db.purchaseOrder.plan.insert(input)
    .onConflictDoNothing(target: (o) => [o.customerId, o.requestKey]);
final claimed = await claim.execute() == 1;
// Alternatively, execute once and receive the newly inserted model or null:
// final order = await claim.returning().singleOrNull();
```

The target must match a declared primary or unique key. Omit it only when any
unique conflict should skip the insert. Construction runs no callbacks; terminals
validate the target and engine before client defaults. Defaults still run if the
database later skips a conflicting row. A skipped insert affects zero rows and
RETURNING yields no row; neither path loads the existing record. `row()` is not
available on this optional insert. Use an explicit transaction to combine a claim
with other writes, as in the [order example](https://github.com/medz/dart-orm/tree/main/example/orders).

`Query` is a read description. Generated complete-model queries retain typed
`patch(...)`, `update(input)`, `delete()` and their advanced `plan`. Selections,
mapping, grouping, DISTINCT and compound
queries expose read operations. Handwritten assignment writes remain available
through `db.table(userTable).where(...).update((u) => [...])`. Unsupported ordered,
limited or joined writes still fail at preparation.

Named result declarations compose across reads and relationships. Put the
declaration in a model library importing `schema.dart`:

```dart
@Projection()
final class UserCard({required final int id, required final String email});
```

After generation, import the generated client and `sql.dart` in application code:

```dart
import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:my_app/models.orm.dart';

Selection<UserCard> person(UserFields u) =>
    userCard(id: u.id, email: u.email);

Projection<UserCard, UserCardFields> personSql(UserFields u) =>
    userCard.sql(id: u.id, email: u.email);

Future<({List<UserCard> all, List<UserCard> matching})> readPeople(
  Database<Backend> db,
  String search,
) async {
  final cards = await db.user.select(person).get();
  final searchable = db.user.select(personSql).asCte('people');
  final matching = await searchable
      .where((p) => p.email.contains(search))
      .get();
  return (all: cards, matching: matching);
}
```

The generated callable shape accepts `Selection` values, including nested
relationships. Its `.sql(...)` form accepts only scalar `Expr` slots and exports
named fields through CTE/UNION. A mapped Dart result cannot claim SQL fields.
Use `Selection<Result>` for ordinary reusable helpers and
`Projection<Result, ResultFields>` when callers need named SQL output fields.
Annotating a flat helper as `Selection<Result>` erases those named fields; it
still decodes the same result. SQL composition continues to validate descriptor
identity, codecs, nullability, scope and session before execution.
Each slot has declaration identity; identical underlying expressions do not
merge named output slots. See [defaults](https://github.com/medz/dart-orm/blob/main/doc/defaults.md) and [execution](https://github.com/medz/dart-orm/blob/main/doc/execution.md).

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
  final user = await tx.user.create(email: 'seven@example.com');
  await tx.post.create(authorId: user.id,
  title: 'First post',
  createdAt: DateTime.now());
});
```

Catching ordinary typed SELECT/RETURNING mapper, codec or cardinality errors
inside an explicit transaction leaves it usable. Let an error escape when the
transaction must roll back. Driver failures, interrupted batch statements and
raw result-decoding failures retain their failure policy; a caught failure in
those categories may prevent commit.

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
