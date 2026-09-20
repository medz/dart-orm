# SQLite in browsers and Flutter Web

`package:orm/sqlite.dart` selects the native isolate or browser worker internally.
Both execute through sqlite3's shared database/statement interfaces. Generated
models, selections, relationships, transactions, migrations and subscriptions use
one API.

```dart
import 'package:orm/sqlite.dart';
import 'schema.orm.dart';

final db = await sqlite(const SqliteOptions.persistent('app'));
// Apply the application's reviewed Dart migration history before queries.
final user = await db.users.create(email: 'seven@example.com');
await db.close();
```

Use `SqliteOptions.memory()` for an isolated in-memory database. For the same
persistent configuration on native platforms, provide `nativePath`:

```dart
final db = await sqlite(SqliteOptions.persistent(
  'app',
  nativePath: databaseFilePath,
));
```

The application owns its native directory choice; `nativePath` is unused on Web.
`journal` and `busyTimeout` configure native connections. Browser persistence uses
DELETE journaling, FULL synchronous mode and exclusive OPFS ownership; it does not
apply native WAL/busy-wait settings.
`SqliteOptions.file(path)` and `readOnly(path)` remain native file operations.
Browser persistence uses the explicit name, never a guessed basename of a native
path. Unsupported storage fails before opening a worker.

## Flutter Web

The ORM package declares its worker and SQLite WASM as Web-only Flutter assets.
A Flutter consumer needs no worker source, manual downloads, asset declarations or
URL configuration. `flutter run -d chrome`, `flutter build web` and
`flutter build web --wasm` use the same database configuration. The default worker
is compiled once by the package maintainer. Both application compilation modes
use that JavaScript worker with the same SQLite WASM engine.

See the runnable [Flutter example](https://github.com/medz/dart-orm/blob/main/example/flutter/README.md). This packaging
uses Flutter's platform asset filters, available since Flutter 3.41. The ORM stays
a pure Dart package without an SDK Flutter dependency.

Default resource resolution follows the document's HTML base, so a Flutter app
built with `--base-href /app/` also works when opened directly at `/app/notes/42`.
It does not resolve resource paths against the current route.

## Plain Dart and custom deployment

Copy the installed package's matching resources into your static files:

```sh
dart run orm web-assets            # default output: web/orm/
dart run orm web-assets public/orm # custom output directory
```

Plain Dart defaults to `orm/` under the HTML base. The command verifies the
packaged hashes before copying and retains older deployment assets. It needs no
worker compilation or WASM download. Serve JavaScript with a JavaScript MIME type
and WASM with `application/wasm`.

Advanced deployment can set `SqliteWebOptions` on `memory()` or `persistent()`:

```dart
final db = await sqlite(SqliteOptions.persistent(
  'app',
  web: SqliteWebOptions(assetBase: Uri.parse('static/database/')),
));
```

`assetBase` is the directory of the versioned files and must end with `/`.
Individual `worker` and `wasm` URI overrides resolve against the HTML base.
`worker` must be same-origin HTTP(S). WASM may use an explicitly configured CDN
with appropriate CORS and CSP. Flutter's custom `assetBase` is not automatically
read from private engine configuration: keep database resources same-origin or
provide these explicit overrides. CDN/CSP deployment has not been certified.

The client checks worker protocol/build identity before requesting database open.
The browser verifies the SQLite module's subresource integrity before it is
instantiated. A stale worker or wrong module fails explicitly. A custom compatible
SQLite build must supply its own SHA-256 `wasmIntegrity` value. Stock resources are
content-addressed; deploy them together with the app and retain resources needed
by older open pages. Offline caching remains the application's deployment policy.

For maintainers, `dart run tool/build_sqlite_web.dart` rebuilds the stock worker
and pins the official sqlite3 3.6.0 module. `--check` verifies source and artifact
fingerprints without rebuilding. The custom-worker entry remains
`package:orm/sqlite_web_worker.dart`; its Dart `main()` calls
`runSqliteWebWorker()`. Applications using the stock worker do not need it.

## Storage and connection ownership

An OPFS database lives under the origin-private `dart-orm/<name>` directory. The
underlying VFS persists `/database` and its rollback journal, and uses memory for
temporary files. The driver requests DELETE journaling and FULL synchronous mode,
and enables and verifies foreign keys before returning a connection. A memory
database requests MEMORY journaling. Requested modes are checked against SQLite.

OPFS requires a supporting browser and a secure context (localhost works for
development). There is no implicit fallback to non-persistent memory or IndexedDB.
The underlying sync access handles exclusively own the database. Opening another
worker/tab for the same name fails while the first owns it. Await `db.close()` to
release it before reopening. A single driver queues whole leases, so separate
queries cannot enter someone else's transaction. This implementation does not
coordinate a shared database service across tabs.

`openTimeout` defaults to 15 seconds. Failed startup terminates the failed worker;
normal close first closes statements, the database and OPFS handles, then terminates
the worker. Schema migrations run through the same owned connection. The browser
acceptance test reloads a page with a transaction still open, verifies recovery of
committed data and rollback of that transaction, then applies a versioned upgrade.

OPFS data remains subject to the browser's quota, eviction and user-clearing rules.
The sqlite3 3.6.0 WASM API is explicitly marked experimental, including the future
stability of VFS storage formats. This adapter's Chromium acceptance is not a
cross-browser production certification. The implementation follows the package's
[dedicated-worker OPFS API](https://pub.dev/documentation/sqlite3/latest/wasm/SimpleOpfsFileSystem-class.html).

## Numeric and temporal boundaries

JavaScript represents int and double with the same underlying number type and
cannot distinguish every 64-bit integer. See [Dart number semantics](https://dart.dev/resources/language/number-representation).
The worker protocol rejects untagged integer parameters outside
`-9007199254740991..9007199254740991`. Use BigInt for wider integers. SQLite int64
results beyond the safe range cross the worker boundary as exact BigInt values,
not rounded doubles. Generated int fields must remain in the safe range; decoding
an incompatible value fails. This bridge applies the same rule to JS and WASM
clients so their storage contract is consistent.

`Codecs.real` preserves floating-point intent automatically on web builds, including
integral doubles such as `1e20`. For raw SQL or custom encoders, `SqlReal(1e20)` is
an explicit floating parameter; SQLite binds it with the native double API.
SqlReal is also accepted by native SQLite/PostgreSQL drivers. Raw PostgreSQL SQL
still needs suitable SQL casts/context to establish parameter/result types.
Finite floating values retain their value through versioned keyset cursor tokens,
including a unique tie breaker when several rows have the same floating value.

Blobs use structured-clone typed arrays. BigInt uses tagged decimal text. Decimal
parameters and SQLite arithmetic use the same exact implementation and registered
functions as native SQLite. LocalDate, LocalTime and LocalDateTime remain explicit
calendar values. UTC DateTime encoding uses date/time components, and browser
decoding avoids a lossy total-microseconds JS number. Acceptance includes BC dates
and microseconds near DateTime's upper bound. Calling SDK arithmetic that loses
precision before passing a value to the ORM cannot be repaired by the driver.

## Capabilities and observable cost

Queries run in the worker, leaving the browser event loop responsive. Streaming
uses a real prepared cursor and fetches bounded batches through worker messages.
Closing or cancelling a stream releases its statement and lease. Ordinary get()
still materializes its complete result; use streaming/pagination for large reads.
Messages incur structured-clone and decoding costs; no zero-copy or throughput
claim is made.

Statement interruption is unavailable with this synchronous WASM API, so
`capabilities.cancellation` is false. Statement deadlines/cancellation and
transaction deadline/retry options that require interruption fail before execution.
This does not prevent ordinary transactions, savepoints, acquisition limits or
early cursor release. Do not treat worker termination as proof of a SQL rollback
or as a replacement for confirmed commit outcomes.

`watch()` merges known writes after commit and emits fresh snapshots. It does not
observe another origin, tab or independent database connection. Named SQL queries
retain their explicit `reads:` requirement. Same-origin persistence, browser
storage permission and database ownership are separate from reactive invalidation.

## Reproducible acceptance

```sh
dart run tool/test_browser.dart
dart run tool/test_browser.dart --wasm
dart run tool/test_flutter_web.dart /absolute/path/to/flutter
```

The runner verifies packaged resource fingerprints, copies the matching assets,
checks generated fixture freshness, compiles the client, starts a local asset
server, and launches Chrome
with a disposable profile. Set `CHROME_EXECUTABLE` to override its path. It writes
`report.js.json` or `report.wasm.json` under `.dart_tool/browser/` and fails if the
browser reports any failed check. Reports contain the actual browser, Dart SDK, compilation mode and engine
checksum. Consult [progress](https://github.com/medz/dart-orm/blob/main/doc/progress.md) for the revision and configurations
most recently verified.

Run these separately from the native full suite: concurrent Dart CLI invocations
can race while rewriting/codesigning the shared macOS native-asset cache. The
acceptance checks cover memory migration/catalog checks, FK and CHECK enforcement,
atomic constraint migration rollback, client defaults with explicit null and
prepared batch values, stored/virtual computed fields and expression migrations,
many-to-many payloads and pagination with measured query/row counts, generated
relations, transactions/savepoints/lifetime, cursors, subscriptions, numeric and
calendar codecs, unsupported interruption, event-loop responsiveness, startup
failures, exclusive OPFS ownership, reopening, page reload recovery and upgrades.
The plain Dart runs do not establish Flutter embedding. Neither runner measures
throughput or establishes Safari, Firefox, IndexedDB or multi-tab service support.

The unified-entry acceptance adds actual Flutter release builds in JS and WASM,
with and without cross-origin isolation headers. The app consumes the package's
unchanged asset declarations and default URI resolution from a nested route.
It also checks stale worker rejection and WASM integrity failure.

Hot reload retains application state. Flutter Web hot restart, which can abandon
live JS resources without closing them, is not certified by these release tests;
close the database or refresh the page when restarting a live OPFS session.
Multi-tab sharing, automatic storage fallback and cross-tab watch propagation
remain outside this driver. A second owner fails rather than bypassing OPFS locks.
