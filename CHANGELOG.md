## 6.0.0-beta.1

First beta of the new Dart-native ORM. Requires Dart 3.13 or newer.

This is a breaking replacement for the Prisma-based 5.x client. Prisma schema
files, generated clients, engine binaries and the separate `orm_flutter` adapters
are not used by this implementation. Existing applications need an explicit
model/API migration; updating the dependency alone is not sufficient.

- Declare immutable Dart models once and generate typed create, patch, query,
  relationship and projection APIs.
- Use schema metadata, database drivers, raw sessions, typed SQL, ORM execution
  and migrations as independent libraries in one package.
- Connect to SQLite, PostgreSQL, MySQL and MariaDB using native Dart adapters.
- Use one SQLite entrypoint for native Dart, Flutter and the browser. Flutter Web
  bundles the worker and WASM assets automatically.
- Keep snapshots and immutable, single-engine migration histories in Dart source,
  including catalog verification, reviewed renames and resumable backfills.
- Initialize, generate and manage migrations with typed `orm.config.dart` and
  the `dart run orm` CLI. Optional build_runner outputs Dart source only.
- Add typed selections, explicit relation loading, transactions, query
  subscriptions, SQL inspection and capability-checked execution controls.

See [database and platform boundaries](doc/capabilities.md) before adopting the
beta. MySQL/MariaDB DDL is non-atomic. Cancellation and streaming depend on the
selected driver; the default Linux SQLite asset does not expose interruption.

Earlier 5.x releases remain available in the
[release archive](https://github.com/medz/dart-orm/releases/tag/orm-v5.3.4).
