# API and correctness refactor validation

Captured 2026-09-16 on macOS arm64. Dart 3.13.3 stable, sqlite3 package 3.6.0,
PostgreSQL 18.4 (Homebrew), and real headless Chrome 153. The PostgreSQL instance,
browser profiles and usage database were created for this run and cleaned up.

Runtime source SHA-256:
`8344748e7f2dbc2e22a54f330510250c953e35ac67e7e92d238ec3dafb3d37f7`.
The digest covers lexically sorted Dart paths under `lib`/`bin` and
`pubspec.yaml`/`pubspec.lock`: UTF-8 path, NUL, file bytes, NUL. These files were
unchanged during the final native/browser/usage runs. Implementation commits are
`5b6feed` and `ef7438d`; final test harness, browser regression and documentation
changes are recorded in the subsequent local commit.

| Check | Result | Evidence |
| --- | --- | --- |
| Complete native suite, PostgreSQL enabled | **872 passed, 10:41, exit 0** | [Full native log](api-audit-native.log) |
| Real Chrome JavaScript | **20 checks, passed, exit 0** | [JS log](api-audit-browser-js.log) |
| Real Chrome Dart WASM | **20 checks, passed, exit 0** | [WASM log](api-audit-browser-wasm.log) |
| README application example and persistent SQLite migration CLI | check/apply/verify/repeat apply passed; no replay | [Usage log](api-audit-usage.log) |
| Static analysis | No issues | `dart analyze` |
| Whitespace validation | Clean | `git diff --check` |

The full native invocation includes existing regression suites plus 25 new test
cases: query/transaction boundaries, export/dependency contracts, schema/name
validation, both native computed-key contracts, and generation diagnostics.
It also runs real process-exit recovery, consumer source generation, build_runner
watch/recovery, historical fingerprints and an AOT migration bundle after deleting
the consumer's Dart sources and migration assets.

Both browser runs add a new scenario for mixed transaction/root subqueries and
CTEs, independent left-join presence guards, valid nested optional decoding and
rejected writes with unchanged data. Their remaining scenarios cover the existing
generated API, codecs, relations, transactions, cursors, observation and OPFS
reload/recovery. The report independently records compilation mode and the pinned
SQLite WASM digest:
`13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4`.

The README Dart block was executed directly, changing only its relative import
to reach the generated example client. It returned `[seven@example.com]` using
the generated `User` export. A fresh temporary file then passed the example
migration entrypoint's check/apply/verify/apply sequence; the second apply returned
an empty list. Historical definitions retained their recorded fingerprints.

## Reproduction

```sh
ORM_TEST_POSTGRES=<disposable local PostgreSQL> dart test --reporter expanded
dart run tool/test_browser.dart
dart run tool/test_browser.dart --wasm
dart run example/migrate.dart check
ORM_SQLITE_PATH=<new disposable file> dart run example/migrate.dart apply
ORM_SQLITE_PATH=<same file> dart run example/migrate.dart verify
ORM_SQLITE_PATH=<same file> dart run example/migrate.dart apply
dart analyze
git diff --check
```

Native runs use the standalone SDK and the installed CommandLineTools through
`DEVELOPER_DIR`. Run native tests and browser acceptance sequentially because
macOS native-asset startup can rewrite/code-sign a shared output. Disposable
consumer fixtures copy existing content-addressed SQLite downloads; sqlite3's
normal hook rechecks the published hash before reusing them. This avoids repeated
network downloads without replacing the native driver or AOT bundle path.

## Limits

This is the final clean full invocation, not a combination of earlier failing
and passing runs. An interrupted earlier attempt and the fixes it prompted are
described in [the audit](../api-correctness-audit.md). After the final native run,
only brace formatting in the test cache-copy helper and documentation/evidence
changed; no runtime, generator, schema or migration behavior changed.

Android, Apple platforms and runtime/generation performance measurements were not
rerun. Their earlier captures stay tied to their recorded sources. Browser proof
is Chrome JS/WASM, not every browser. The native suite is SQLite and PostgreSQL
18.4, not every server version or custom build. Raw SQL, custom codecs/drivers and
unmanaged database objects retain their documented application-owned contracts.
No push or package publication was performed.
