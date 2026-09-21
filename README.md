# Dart ORM

**Typed data. Plain Dart.**

Declare immutable Dart models, query exactly the fields you need, and keep your
schema and migrations in Dart. SQLite, PostgreSQL, MySQL and MariaDB share a typed
query API, with explicit database capabilities and transaction boundaries.

[Get started](#get-started) · [Guides](https://github.com/medz/dart-orm/blob/main/doc/README.md) ·
[API reference](https://pub.dev/documentation/orm/6.0.0-beta.3/) ·
[Examples](https://github.com/medz/dart-orm/tree/main/example) · [pub.dev](https://pub.dev/packages/orm/versions/6.0.0-beta.3)

> **6.0 beta:** a new implementation requiring Dart 3.13+. This is a breaking
> replacement for the Prisma-based 5.x client. Read the [release notes](https://github.com/medz/dart-orm/blob/main/CHANGELOG.md)
> before upgrading an existing application.

Upgrading from beta.2: replace annotated entities and hand-written row types with
`model(...)` and regenerate your clients. Keep existing migration history; table
and column names continue to identify the physical schema. See the
[beta.3 changes](https://github.com/medz/dart-orm/blob/main/CHANGELOG.md#600-beta3).

## Record schemas

Record schemas define each model and table together, without annotations:

```dart
final task = model('tasks', (
  id: identity(),
  title: text(),
  done: boolean(defaultValue: false),
));
```

Import `package:orm/schema.dart` in the definition. Generation produces the `Task`
row, `db.task` and a standalone migration snapshot. See [authoring](https://github.com/medz/dart-orm/blob/main/doc/authoring.md)
and the [complete company example](https://github.com/medz/dart-orm/blob/main/example/company/README.md).

## Get started

Create a Dart application and add the package:

```sh
dart create -t console my_app
cd my_app
dart pub add orm:6.0.0-beta.3
```

```sh
dart run orm init --database sqlite
```

The CLI creates `orm.config.dart`, a model, its generated client, and a migration
registry. The starter model in `lib/schema.dart` is ordinary Dart:

```dart
import 'package:orm/schema.dart';

final task = model('tasks', (
  id: identity(),
  title: text(),
  done: boolean(defaultValue: false),
));
```

Create and review the first migration, then apply it:

```sh
dart run orm migrate create 0001_initial
# Review migrations/m0001_initial.dart.
dart run orm migrate apply
```

Replace `bin/my_app.dart` with:

```dart
import 'package:my_app/schema.orm.dart';
import 'package:orm/sqlite.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.file('app.sqlite'));
  try {
    final Task task = await db.task.create(title: 'Ship something useful');

    final List<(int, String)> pending = await db.task
        .where((t) => t.done.eq(false))
        .orderBy((t) => [t.id.asc()])
        .select((t) => (t.id, t.title).row)
        .get();
    print(pending);

    await db.transaction((tx) async {
      await tx.task.byId(task.id).patch(done: .set(true));
    });
  } finally {
    await db.close();
  }
}
```

Run `dart run`. When your model changes, create and review another migration.
Use `dart run orm generate` when you only need to regenerate Dart code.

## Model once, choose your result

Full-row queries return your model class. A scalar selection returns its value;
`.row` returns a typed Record. Map selected values into a named Record or your
own DTO. Create and patch inputs distinguish omission, a value, SQL NULL and a
database default.

Use `get()` for a list, `first()` for a required first row, and `single()` when
exactly one row must exist. `firstOrNull()` and `singleOrNull()` explicitly allow
an empty result. Selecting a nullable column keeps its nullable Dart type.

Relationships use declared keys. Select nested results explicitly: to-one
relationships can join, and collections use parameter-aware batches. There are
no lazy property reads that quietly issue SQL. See [relationships](https://github.com/medz/dart-orm/blob/main/doc/relations.md)
and the [query cookbook](https://github.com/medz/dart-orm/blob/main/example/queries.dart).

Transactions use the provided `tx` session. Query subscriptions emit snapshots
after relevant committed writes. Inspect SQL without connecting, or use raw and
named SQL when a query needs database-specific features.

## Choose your database

| Database | Connection | Verified scope |
| --- | --- | --- |
| SQLite | `sqlite(SqliteOptions.file('app.sqlite'))` | Native Dart, Android Flutter, Chrome JS/WASM and Flutter Web |
| PostgreSQL | `postgres(PostgresOptions(url: url))` | PostgreSQL 18, including migrations |
| MySQL | `mysql(MysqlOptions(url: url))` | MySQL 8.4, including migrations |
| MariaDB | `mariadb(MariadbOptions(url: url))` | MariaDB 11.8, including migrations |

Import `package:orm/sqlite.dart`, `postgres.dart`, `mysql.dart` or `mariadb.dart`
for the matching connection API. Server connections verify TLS certificates by
default. `init --database` accepts `sqlite`, `postgres`, `mysql` and `mariadb`.

Each migration history belongs to one engine and stores only that engine's
reviewed steps and frozen schema. MySQL/MariaDB DDL uses recovery checkpoints
because it can commit implicitly. See [migrations](https://github.com/medz/dart-orm/blob/main/doc/migrations.md).

Capabilities are explicit. MySQL/MariaDB do not support cursor streaming or token
cancellation; their statement timeout discards the connection. Default Linux
SQLite lacks interruption. See [capabilities](https://github.com/medz/dart-orm/blob/main/doc/capabilities.md) for exact numeric
limits, database versions and platforms that have not been verified.

## Dart and Flutter, native and web

The SQLite entrypoint selects a native isolate or browser worker. For persistent
storage, use `SqliteOptions.persistent('app', nativePath: databasePath)`; native
apps provide their own filesystem path, while browsers use named OPFS storage.

Flutter Web bundles the SQLite worker and WASM assets automatically. Plain Dart
Web exports the same resources with `dart run orm web-assets`. No separate
`orm_flutter` package is needed. Start with the [Flutter example](https://github.com/medz/dart-orm/tree/main/example/flutter)
or the [SQLite Web guide](https://github.com/medz/dart-orm/blob/main/doc/sqlite-web.md).

## One package, independent libraries

Use the layer your application needs:

| Import | Purpose |
| --- | --- |
| `values.dart`, `schema_model.dart` | Domain values, codecs and physical schema metadata |
| `driver.dart`, `drivers/*.dart` | SQL contracts and database adapters |
| `runtime.dart` | Raw SQL sessions, transactions and cursor ownership |
| `sql.dart`, `orm.dart` | Typed SQL construction and model execution |
| `schema.dart`, `generate.dart`, `migrate.dart`, `cli.dart` | Declarations, generation, migration and project tooling |

Compile typed SQL offline, use a driver without model generation, or run saved
migrations without importing today's application models. See [API boundaries](https://github.com/medz/dart-orm/blob/main/doc/api.md).

## Go further

- [Model declarations and codecs](https://github.com/medz/dart-orm/blob/main/doc/authoring.md) · [Types](https://github.com/medz/dart-orm/blob/main/doc/types.md)
- [Queries and pagination](https://github.com/medz/dart-orm/blob/main/doc/queries.md) · [Relations](https://github.com/medz/dart-orm/blob/main/doc/relations.md)
- [Transactions and execution](https://github.com/medz/dart-orm/blob/main/doc/execution.md) · [Subscriptions](https://github.com/medz/dart-orm/blob/main/doc/watch.md)
- [CLI](https://github.com/medz/dart-orm/blob/main/doc/cli.md) · [build_runner](https://github.com/medz/dart-orm/blob/main/doc/generation.md) · [Existing databases](https://github.com/medz/dart-orm/blob/main/doc/importing.md)
- [SQL inspection](https://github.com/medz/dart-orm/blob/main/doc/observability.md) · [Named SQL](https://github.com/medz/dart-orm/blob/main/doc/named-sql.md)
- [Contributing and validation](https://github.com/medz/dart-orm/blob/main/CONTRIBUTING.md)

Licensed under the [BSD 3-Clause License](https://github.com/medz/dart-orm/blob/main/LICENSE).
