# Upgrade from beta.6 to beta.7

`6.0.0-beta.7` requires Dart 3.13 or newer and changes the beta query and write
API. Install the version, regenerate application clients and snapshots, then
analyze the application:

```sh
dart pub add orm:6.0.0-beta.7
dart run orm generate
dart analyze
```

For build_runner projects, use `dart run build_runner build` instead of the CLI
generation command. Keep reviewed migration files and their fingerprints
unchanged. This API upgrade does not itself rename tables or authorize schema
changes. Review a new migration only when the physical schema changes.
The [beta.6 guide](https://github.com/medz/dart-orm/blob/orm-v6.0.0-beta.6/README.md)
remains available for applications staying on that version.

## Imports and database setup

Engine factories now return an owning `SqlDatabase`. Add the model view
explicitly; both views share the same runtime and closing either root closes it:

```dart
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:my_app/models.orm.dart';

final db = Database.fromSql(await sqlite(const SqliteOptions.file('app.sqlite')));
try {
  final titles = await db.task.select((t) => t.title).get();
  print(titles);
} finally {
  await db.close();
}
```

Apply `Database.fromSql` to PostgreSQL, MySQL and MariaDB factories too.
PostgreSQL's factory remains synchronous and its pool connects lazily.
Replace `runtime.dart` imports with `sql.dart` and `drivers/<engine>.dart`
with the matching public `<engine>.dart`. Import `values.dart`, `driver.dart`
and `schema_model.dart` when using their types directly. `select` is an extension
from `sql.dart`; every library calling it must import that module. Neither
`orm.dart` nor a generated client re-exports it.

## Ordinary writes and advanced plans

Generated `create` returns `Future<Model>`; `patch` returns `Future<int>`.
`insert`, `insertMany`, `update` and `delete` now also execute directly and return
`Future<int>`. Remove their ordinary `.execute()` terminal:

```dart
await db.task.byId(id).patch(done: true);
await db.task.byId(id).delete();
```

Use immutable generated inputs to pass write data between functions. Named
literal fields distinguish omission from explicit null. Replace old `Change`
inputs and handwritten generated-model assignment callbacks with these inputs:

```dart
final request = taskPatch(title: 'Reviewed');
final policy = taskPatch(done: true);
final patch = taskPatch.overlay([request, policy]);
if (!taskPatch.isEmpty(patch)) {
  await db.task.byId(id).update(patch);
}
```

The factory's `.values(...)` accepts `WriteValue` intents: `.set(value)`,
`.keep()`, `.databaseDefault()` and `.expression((fields) => expression)`.
Overlay layers apply in order; the last supplied intent wins, while `.keep()`
preserves an earlier intent. `taskInsert.overlay(base, patches)` preserves
insert-only fields. No model field is reserved for execution controls; pass
options to typed-input operations or use a plan.

For inert write descriptions, SQL inspection, RETURNING or replay, use `.plan`:

```dart
final insert = db.task.plan.insert(taskInsert(title: 'Draft'));
final prepared = insert.prepare();
print(prepared.compile().sql);
await prepared.execute();

final title = await db.task.byId(id).plan
    .update(taskPatch(title: 'Published'))
    .returning().select((t) => t.title).single();
```

Plan construction evaluates no input callbacks or client defaults. Each plan
terminal prepares fresh values; explicit `prepare()` freezes them for replay.
RETURNING selections require native RETURNING support. For full insert readback,
`plan.insert(input).row()` can use a transactional primary-key readback on
engines without native RETURNING. See [write boundaries](api.md#preparing-and-executing)
for validation order, byte ownership and failure behavior.

## Named results and CTEs

`Selection<Result>` remains the type for arbitrary result assembly, including
nested relationships. Declare a reusable named shape in a model source:

```dart
@Projection()
final class TaskCard({required final int id, required final String title});
```

Generation adds `taskCard(...)` for `Selection` slots and `taskCard.sql(...)`
for scalar SQL expressions. Annotated named-record typedefs are supported too.
Use `Projection<Result, ResultFields>` for helpers whose named SQL fields must
remain available to CTEs and set operations. Typing such a helper as
`Selection<Result>` erases those named fields without changing its decoded result.

```dart
final cards = await db.task
    .select((t) => taskCard(id: t.id, title: t.title)).get();
final searchable = db.task
    .select((t) => taskCard.sql(id: t.id, title: t.title))
    .asCte('task_cards');
final matches = await searchable
    .where((c) => c.title.contains('Draft')).get();
```

`asCte` now returns a query directly: change `cte.query.where(...)` to
`cte.where(...)`, and likewise for `select`, `orderBy` and read terminals.
Existing scalar and positional SQL selections still export expressions through
`ref(...)`. A Dart mapper or nested relationship result does not become a named
SQL output field. All composed queries must belong to the same database or
transaction view. Use the callback's `tx` throughout a transaction.

## License

Beta.7 is the first release whose project-owned code uses the MIT License,
copyright © 2022–2026 Seven Du. Beta.6 and earlier releases and historical tags
retain their original licenses.
