# Flutter integration

Use `package:orm/sqlite.dart` for both native Flutter and Flutter Web. SQLite runs
in a background isolate on native platforms and a worker in the browser. Generated
models, queries, transactions and saved Dart migrations use the same public API.

## Open and own a database

Choose the storage location at the application boundary, then pass the database
or transaction session to the code that needs it:

```dart
import 'package:orm/sqlite.dart';

Future<Database<Sqlite>> openDatabase({String? nativePath}) => sqlite(
  SqliteOptions.persistent('notes', nativePath: nativePath),
);
```

Supply an application-owned file path on native platforms. The ORM does not choose
a documents directory or require a Flutter path plugin. The
[Android example](https://github.com/medz/dart-orm/blob/main/example/flutter/README.md) obtains its private files directory
through a small platform channel; applications can use their existing directory
provider. The browser uses the persistent name for origin-private file storage
(OPFS) and does not use the native path.

Use `SqliteOptions.memory()` for temporary databases. A database handle owns its
connection and worker; keep it at the appropriate application or feature lifetime,
then await `close()` when that owner shuts down. Do not open a new handle for each
widget rebuild or retain a transaction session after its callback returns.

## Bundle migrations

Statically import the saved migration registry and apply its checked history
before issuing application queries:

```dart
import 'package:orm/migrate.dart';
import 'migrations/migrations.g.dart';

await Migrator(db.sql).apply(migrationHistory.checked);
```

Migration definitions and recorded fingerprints compile into the application.
They do not load JSON assets or import current model classes. Keep previously
shipped migration files immutable and add a reviewed migration for each physical
schema change. See [migrations](https://github.com/medz/dart-orm/blob/main/doc/migrations.md) for version compatibility, catalog
verification and recovery rules.

## Build for the web

Flutter Web bundles the package's matching worker and WASM resources automatically.
There is no separate ORM plugin or application asset declaration to maintain.
Normal Flutter commands work:

```sh
flutter run -d chrome
flutter build web
flutter build web --wasm
```

Serve the result from a secure browser context. Persistent storage requires OPFS
and an exclusive owner; unsupported storage fails explicitly. Deployment base
paths, content security policy, advanced resource overrides and browser limits are
covered in [SQLite Web](https://github.com/medz/dart-orm/blob/main/doc/sqlite-web.md).

Hot reload retains application state. Flutter Web hot restart can abandon live
JavaScript resources without releasing the database. Close a live OPFS session
or refresh the page when restarting. Query subscriptions cover known committed
writes; another tab or independent connection needs [explicit invalidation](https://github.com/medz/dart-orm/blob/main/doc/watch.md).

## Upgrades and lifecycle

Apply saved migrations when opening the application database. Test upgrades using
an existing database with representative data, including a process restart after
migration. Close the database when its application owner shuts down; do not open
another instance for each widget rebuild.

The [Flutter example](https://github.com/medz/dart-orm/blob/main/example/flutter/README.md)
includes upgrade and restart instructions. See
[capabilities](https://github.com/medz/dart-orm/blob/main/doc/capabilities.md) for
platform support and driver limits.
