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

Hot reload retains application state. Release tests do not establish that Flutter
Web hot restart always releases abandoned JS resources. Close a live OPFS session
or refresh the page when restarting. Query subscriptions cover known committed
writes; another tab or independent connection needs [explicit invalidation](https://github.com/medz/dart-orm/blob/main/doc/watch.md).

## Verify upgrades and lifecycle

The repository [Flutter example](https://github.com/medz/dart-orm/blob/main/example/flutter/README.md) includes native and
browser runners. Its Android workflow installs a legacy debug APK, upgrades it to
a release AOT APK with retained application data, then force-stops and reopens it
in another process. Assertions cover fixed migration history, preserved rows,
new defaults and relationships, generated writes, rollback, subscriptions,
read-only reopening, worker progress and supported cancellation.

Run `tool/test_flutter.dart` with a dedicated emulator and the two built APKs as
shown in the example instructions. It refuses an existing acceptance installation
and writes reports, logs and a screenshot under `.dart_tool/flutter/`. The
Web runner is `dart run tool/test_flutter_web.dart /absolute/path/to/flutter`.

Animation and timer progress while SQL is running checks worker separation. It
is not a frame-rate measurement. Emulator process restart does not simulate
power loss, and Android checks do not certify iOS, macOS Flutter or physical
devices. [Progress](https://github.com/medz/dart-orm/blob/main/doc/progress.md) records the tested revision and current validation
status; [capabilities](https://github.com/medz/dart-orm/blob/main/doc/capabilities.md) describes driver-specific limits.
