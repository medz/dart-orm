# Unified SQLite refactor validation

Captured 2026-09-16 on Dart 3.13.3, Flutter 3.47.4 and Chrome 153. The
[machine-readable summary](sqlite-refactor.json) records the handwritten runtime
fingerprint and final packaged asset hashes.

The SQLite entrypoint now selects native or browser transport internally. Both
use the same sqlite3 statement configuration, execution and cursor implementation.
The public Web-only driver entry has been removed. Flutter consumes package-owned
assets by default; ordinary Dart Web apps export them with `orm web-assets`.
Resources have content-hash filenames, a startup protocol/build handshake and
WASM subresource integrity verification.

| Validation | Result |
| --- | --- |
| Complete native suite, real SQLite and PostgreSQL 18.4 enabled | **875 passed in 09:12**, exit 0 |
| Final focused native persistence/close/export checks | **5 passed**, exit 0 |
| Plain Dart JS / Dart WASM in Chrome | **21 / 21 passed** |
| Flutter release JS, no isolation headers | **21 passed** |
| Flutter release WASM, no isolation headers | **21 passed**, actual WASM confirmed |
| Flutter release WASM, isolation headers | **21 passed**, actual WASM confirmed |
| Repository Flutter example, `build web --wasm` | Passed |
| Android arm64 debug asset bundle | Built; SQLite Web assets absent |
| CLI Web asset export and packaged fingerprint checks | Passed |
| Static analysis and whitespace diff check | Passed |

The complete native run covers the shared executor and new persistent-path/close
behavior. Final packaging removed the unused worker source-map reference; focused
native checks and all Web configurations were then rerun against those artifacts.
The negative Web scenario separately rejects an old protocol, a different build
with the current protocol, a wrong WASM integrity value, and native file storage.

Flutter tests consume unchanged package asset declarations and default connection
configuration. They start on `/nested/detail/42` with `<base href="/nested/">`,
retain the Flutter widget tree, and assert animation ticks advance during a long
worker SQL query. The captured checks also verify typed relationships and
projections, transactions/savepoints, bounded cursors, commit notifications,
numeric/temporal precision, exclusive OPFS ownership, page reload with an open
transaction, data recovery and subsequent migrations.

Evidence:

- [Native full run](sqlite-refactor-native.log) and [focused checks](sqlite-refactor-focused.log).
- [Plain Dart JS](sqlite-refactor-browser-js.json) and [Dart WASM](sqlite-refactor-browser-wasm.json).
- [Three Flutter Web configurations](sqlite-refactor-flutter-web.json), including
  actual compilation mode, isolation state and asset request paths.
- [Asset verification](sqlite-refactor-assets-check.log), [CLI export](sqlite-refactor-web-assets.log),
  [analysis](sqlite-refactor-analyze.log) and [example build](sqlite-refactor-flutter-example.log).

Reproduce from the repository root, with a cached/installed Flutter SDK:

```sh
dart run tool/build_sqlite_web.dart --check
dart run tool/test_browser.dart
dart run tool/test_browser.dart --wasm
dart run tool/test_flutter_web.dart /absolute/path/to/flutter
dart run orm web-assets
ORM_TEST_POSTGRES=postgresql://postgres@127.0.0.1:65439/postgres dart test
```

On this host, `DEVELOPER_DIR=/Library/Developer/CommandLineTools` selects the
available command-line toolchain. Native-asset Dart commands were run sequentially.
The temporary PostgreSQL instance was stopped and removed; browser profiles and
local servers were disposed by the runners.

The Android result establishes asset filtering, not APK installation or execution.
Android/Apple runtime, Safari/Firefox, Flutter hot restart with an open connection,
CDN/CSP hosting, multi-tab database sharing, offline upgrade deployment and
throughput remain outside this capture. The material-icon font warning in Flutter
release output does not fail compilation. No new performance claim is made.
