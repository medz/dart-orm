# Flutter Web integration research

The recommendation below has since been implemented; see [current setup](../doc/sqlite-web.md)
and [refactor validation](validation/sqlite-refactor.md). The measurements in this
research note describe the earlier probe.

Date: 2026-09-16. Recommendation: retain `sqlite3` as the engine, share its
`CommonDatabase` interfaces, and make browser resource packaging an ORM product
responsibility. Flutter applications should not author a worker or assemble
SQLite WASM URLs for the normal setup. This is a researched direction with a
working packaging probe, not a released initialization API.

## What sqlite3 already provides

`sqlite3` 3.6.0 supports native and browser execution, including Flutter Web.
Native code imports `sqlite3.dart`; browser code imports `wasm.dart` and loads a
compatible SQLite WASM module. Both implement the database and statement
interfaces in `common.dart`. The ORM should reuse those interfaces wherever
execution logic is identical. The package also supplies the memory, IndexedDB and
OPFS file systems; there is no reason to reimplement those in the ORM.
[Source](https://pub.dev/packages/sqlite3/versions/3.6.0).

The package exposes synchronous database operations. An async initialization
method does not move subsequent SQL off the UI thread. Its `VfsWorker` provides
file access to a separate database worker; it is not an async SQL client with ORM
transactions, cursor ownership and query notifications. Native isolate messaging
and browser worker messaging therefore remain small internal responsibilities.
[VfsWorker](https://pub.dev/documentation/sqlite3/latest/wasm/VfsWorker-class.html).

Flutter's `compute()` executes on the main thread on Web. It cannot replace this
database worker. SQL execution in a worker also does not eliminate main-thread
row decoding and widget work, so bounded result sets and streaming still matter.
[Flutter isolates](https://docs.flutter.dev/perf/isolates).

## Packaging options

| Option | Application work and cost | Decision |
| --- | --- | --- |
| Package-owned, precompiled JS worker and SQLite WASM | Flutter bundles declared assets; no application worker compilation | Preferred normal Flutter path |
| Flutter asset transformer | Automatic compilation during run/build; adds compiler invocation and dependency tracking | Optional source-build/custom-worker path; not needed for the stock worker |
| ORM setup command copies matched artifacts to `web/` | One explicit setup step and stale-file checks | Useful for plain Dart deployments or explicit web-root layouts |
| Add `sqlite_async` | Reuses an asynchronous SQLite layer; still needs worker/WASM resources | Does not itself solve this packaging problem; do not add it solely for Flutter Web |

Flutter automatically bundles assets declared by dependencies. Since Flutter
3.41, entries can specify `platforms: [web]`. A probe confirmed that the ORM
package can retain its pure Dart dependencies while adding this metadata:

```yaml
flutter:
  assets:
    - path: assets/web/
      platforms: [web]
```

The Flutter consumer needs no matching asset declaration. Standalone `dart pub
get --offline` also succeeds for that modified package without a Flutter SDK
dependency. An Android-only sentinel is excluded from the probe's Web output;
native application packaging was not rebuilt in this research.
[Package assets and platform filters](https://docs.flutter.dev/ui/assets/assets-and-images).

The release process would compile the ORM's worker once and package it with the
tested SQLite module. Application schema and migration definitions stay in the
application's Dart compilation; they are not inputs to the stock worker build.
Worker and engine assets currently total 924,659 bytes, or 414,884 bytes when
individually gzip-compressed. These are artifact sizes, not measured network
transfer or application startup costs. Package downloads would still include
these files even when a consumer does not build for Web.

Flutter's asset transformer protocol is a Dart executable accepting input/output
paths, and current tooling can track an emitted dependency file. This is viable
when a source-built worker is actually needed. Current Dart hook documentation
supports native `CodeAsset` output, not a general Web resource bundler; introducing
a hook alone would not provide the proposed integration.
[Asset transformers](https://docs.flutter.dev/ui/assets/asset-transformation),
[Dart hooks](https://dart.dev/tools/hooks).

`sqlite_async` already solves asynchronous database execution, but its documented
Web setup still supplies worker and WASM URIs. Adopting it would additionally need
a separate review of its transaction, cursor and custom-function contracts against
the ORM's requirements. This research makes no comparative performance claim.
[sqlite_async Web setup](https://pub.dev/packages/sqlite_async#web).

## Runtime boundaries to keep explicit internally

1. **A single SQLite product entry.** Internally select native opening/transport
   or Web opening/transport. Keep SQLite and PostgreSQL configuration separate.
   Storage policy remains meaningful: a browser database name is not an OS file
   path. Do not guess a native application directory inside the pure Dart core.
2. **Resolve assets at the application base.** The probe loads package resources
   under `/nested/assets/packages/orm/assets/web/`, starting directly at
   `/nested/detail/42`. `document.baseURI` resolves to `/nested/`, whereas
   `Uri.base` includes the current route. Current `SqliteWebDriver.open` resolves
   relative WASM paths with `Uri.base`, so the future default resolver must supply
   correct absolute URLs. The probe does that without changing the driver.
3. **Separate worker and engine URLs for advanced deployment.** Flutter's
   `assetBase` can move assets to a CDN, while a direct Worker URL must satisfy the
   document's same-origin constraint. Default to same-origin resources; allow
   explicit URL overrides. A CDN/blob bootstrap path needs its own CORS/CSP tests
   and must not silently inject a service worker.
4. **Publish matched artifacts.** Add protocol/build identity to the startup
   handshake and use versioned/content-addressed filenames. Fail clearly when
   app, worker or SQLite module versions disagree. Deployment must retain assets
   used by still-open older application versions. This is not implemented yet.
5. **Storage capability is independent of Flutter rendering.** Current
   `SimpleOpfsFileSystem` works in a dedicated worker, owns two persistent files,
   and holds exclusive access. The probe verifies it without cross-origin
   isolation headers. Do not force COOP/COEP just to use this storage path, and do
   not silently fall back from persistent storage to memory.
6. **Multiple tabs need a separate design.** The present second-owner rejection
   remains real. Replacing the worker with `SharedWorker` does not suffice because
   this VFS requires a dedicated worker. Connection sharing, change notifications,
   upgrades and worker lifetime would have to be handled together.

References: [Flutter bootstrap and assetBase](https://docs.flutter.dev/platform-integration/web/initialization),
[Worker URL restrictions](https://developer.mozilla.org/en-US/docs/Web/API/Worker/Worker),
[SimpleOpfsFileSystem](https://pub.dev/documentation/sqlite3/latest/wasm/SimpleOpfsFileSystem-class.html).

Flutter's JS/WASM application compilation is independent of SQLite's WASM engine.
Both application modes can use the same JS database worker. `flutter build web
--wasm` also emits a JS fallback; a successful build alone does not prove the page
actually used WASM. The probe records `dart.tool.dart2wasm` at runtime and tests
with and without the isolation headers used for multithreaded Flutter rendering.
[Flutter WASM](https://docs.flutter.dev/platform-integration/web/wasm).

## Actual Flutter probe

The original probe, now evolved into the [acceptance runner](../tool/test_flutter_web.dart), copies the current ORM
library into a disposable package, adds platform-filtered assets, compiles the
existing worker and creates a real Flutter widget application. It reuses the 20
browser acceptance scenarios, changing only resource resolution, the reload URL,
and reporting. The long SQL scenario additionally asserts that Flutter animation
ticks advance while SQL executes. It starts after the first Flutter frame and
keeps the widget tree mounted throughout the checks.

```sh
dart run tool/build_sqlite_web.dart --check
dart run tool/test_flutter_web.dart /absolute/path/to/flutter
```

On this host, commands use `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.
The current runner rebuilds its own `.dart_tool/flutter_web_test/` directory, needs cached
Flutter/pub dependencies for offline resolution, serves local renderer assets,
and uses disposable Chrome profiles. It does not modify the shipping pubspec.

| Flutter release build | Actual Dart WASM | crossOriginIsolated | Result |
| --- | --- | --- | --- |
| JS | false | false | 20 checks passed |
| WASM | true | false | 20 checks passed |
| WASM | true | true | 20 checks passed |

Environment: Flutter 3.47.4, Dart 3.13.3, Chrome 153, sqlite3 3.6.0.
[Captured evidence](validation/flutter-web-probe.json) includes SDK revisions,
engine/worker hashes, resource requests, execution-mode flags and checks.
The checks include typed relationships/projections, transactions/savepoints,
subscriptions, streaming, precision, OPFS close/reopen, interrupted-transaction
recovery across page reload, and migration upgrades.

This establishes release-build feasibility on Chromium with same-origin assets,
including nested deployment. It does not establish Flutter hot-restart lifecycle,
Safari/Firefox operation, JS fallback selection from a WASM build, CDN/CSP support,
iframe storage, multi-tab coordination, offline cache updates, sustained frame
performance, or mobile/desktop packaging. The shipping Flutter example remains
native-only; production initialization and automatic asset delivery remain work
to implement after this research.
