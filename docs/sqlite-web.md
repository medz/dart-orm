# SQLite in browsers

`package:orm/sqlite_web.dart` opens SQLite WASM in a long-lived dedicated worker.
Generated models, queries, selections, relationships, transactions, migrations and
subscriptions use the same runtime as native SQLite.

```dart
import 'package:orm/sqlite_web.dart';
import 'schema.orm.dart';

final db = await sqliteWeb(SqliteWebOptions.opfs(
  name: 'app',
  wasm: Uri.parse('/sqlite3.wasm'),
  worker: Uri.parse('/database_worker.js'),
));
final user = await db.users.create(email: 'seven@example.com');
await db.close();
```

Use the migration runner before application queries, with reviewed migrations
bundled in the application. For an isolated in-memory database, use
`SqliteWebOptions.memory(wasm: ..., worker: ...)`.

The worker entry point is ordinary Dart:

```dart
import 'package:orm/sqlite_web_worker.dart';
void main() => runSqliteWebWorker();
```

Compile it with `dart compile js -O2 web/database_worker.dart -o
web/database_worker.js`. Serve that script and the matching sqlite3 WASM asset
from the application. The WASM response must have `application/wasm` content type.
Use the package's official asset, not an unrelated SQLite WASM build. The tested
asset is from [sqlite3 3.6.0](https://pub.dev/packages/sqlite3/versions/3.6.0), with
SHA-256 `13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4`.

The browser client works when compiled to JavaScript or Dart WASM; the database
worker is a separately compiled JavaScript worker in both cases. A cross-platform
application should choose its platform entry point through Dart conditional
imports/exports. Importing the native `sqlite.dart` FFI entry point into a web
build is not supported. Keep generated schema imports on `orm.dart`.

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
```

The runner validates/downloads the pinned WASM asset, checks generated fixture
freshness, compiles current source, starts a local asset server, and launches Chrome
with a disposable profile. Set `CHROME_EXECUTABLE` to override its path. It writes
`report.js.json` or `report.wasm.json` under `.dart_tool/browser/` and fails if the
browser reports any failed check. Reports contain the actual browser, Dart SDK,
compilation mode and engine checksum. The captured results are in
`research/validation/browser.json`.

Run these separately from the native full suite: concurrent Dart CLI invocations
can race while rewriting/codesigning the shared macOS native-asset cache. The
acceptance checks cover memory migration/catalog checks, FK and CHECK enforcement,
atomic constraint migration rollback, client defaults with explicit null and
prepared batch values, stored/virtual computed fields and expression migrations,
many-to-many payloads and pagination with measured query/row counts, generated
relations, transactions/savepoints/lifetime, cursors, subscriptions, numeric and
calendar codecs, unsupported interruption, event-loop responsiveness, startup
failures, exclusive OPFS ownership, reopening, page reload recovery and upgrades.
They do not measure throughput or establish Safari, Firefox, Flutter embedding,
IndexedDB or multi-tab database-service support.
