# Standalone ORM acceptance

Captured on 2026-09-19. Initial runtime source: `7a54553933ae1d768576a54a4234b00b6bfcf97e`.
Final runtime and refreshed Web assets: `3aef4e7905f6997ff2fa9c181709bdddbdcc64ad`.
The refreshed browser reports pin the latter revision. Android reports retain the
initial revision. Later changes affect server drivers, operation capability
validation, test portability and Web asset fingerprints; Android was not rerun.
Validation commits add reports without changing runtime.

## Actual environments

Dart 3.13.3 and Flutter 3.47.4 stable on macOS arm64; SQLite 3.53.4;
PostgreSQL 18.4; MySQL 8.4.11 and MariaDB 11.8.9 in separate disposable containers.
MySQL/MariaDB tests require TLS with their fixture certificates. Flutter and
plain Dart browser tests use actual Chrome 153, not simulated DOM APIs.

## Results and scope

| Validation | Evidence |
| --- | --- |
| Native full regression, first invocation | 1119 passed, 5 failed in 11:50. Failures were two older CLI JSON expectations and three new temporary-metadata regressions. [Structured record](standalone-native.json). |
| Final session/transaction regression | 282 passed. Real SQLite/PostgreSQL session ownership, escaped connections, swallowed SQL failures, pending work, cursor cleanup, transaction/retry/acquisition/watch paths; MySQL/MariaDB transaction boundaries included. |
| Final CLI/import/migration/SQL regression | 71 passed. All four engines initialize and create Dart history; SQLite lifecycle and SQLite/PostgreSQL adoption use real consumers; MySQL/MariaDB test actual DDL/backfill recovery and metadata shadowing. |
| PostgreSQL review regression | 176 passed, including four new real TCP-proxy regressions for explicit/default timeout, cancellation before PID discovery and a shared PID/application deadline. All four new cases failed before the fix. |
| MySQL version boundary | 40 driver/migration-target checks passed. MySQL driver and migration support now both require 8.4+; older migration targets fail before locks, journals or DDL. |
| Static checks | Root Dart analysis and Flutter example analysis: no issues. Formatting and diff whitespace checks pass. |
| Plain Dart Web | JS and WASM each pass 21 scenarios. [Reports](standalone-browser.json). |
| Flutter Web release | JS, WASM without isolation and WASM with isolation each pass 21 scenarios. Assets are bundled automatically; nested routes, reload recovery, migrations and animation progress during SQL are checked. [Reports](standalone-flutter-web.json). |
| Flutter Android arm64 API 35 | Legacy debug installation: 4 checks; release AOT APK upgrade: 17; new-process reopen: 11. Host checks distinct process IDs, retained database path/data/history and APK version codes. [Report](standalone-flutter.json), [screenshot](standalone-flutter-android.png). |
| Native packaging | Both Android APKs contain arm64 `libsqlite3.so` and zero SQLite Web worker/WASM assets. |

The initial full run and subsequent targeted runs are separate invocations. They
are not combined into a claimed all-green full run. The PR's GitHub CI check runs
formatting, analysis, resource fingerprints, the complete native suite with all
four engines enabled, and Chrome JS/WASM. Passing that check and Codex review of
the final head are required before merge; the PR records their results.

## Correctness findings resolved before platform capture

Independent review corrected MySQL/MariaDB registry parsing and non-atomic plan
reporting, temporary migration metadata shadowing, and borrowed-session ownership
and error tracking. A caught raw PostgreSQL error cannot make an aborted
transaction report success. Borrowed connections and cursors cannot escape their
session/savepoint; unawaited accepted work drains before the boundary completes.
MySQL/MariaDB migration failures and uncertain commits use durable checkpoints and
catalog verification rather than assuming that DDL rolls back.

## Codex review correction

The first external Codex review found an unbounded first PostgreSQL backend PID
lookup. The timer and cancellation listener now start before that lookup; an
interruption without a PID discards the connection before sending application SQL.
The cached PID path retains cancellation and reuse, and uncertain errors after a
statement starts are not reclassified as confirmed interruption. A real PostgreSQL
TCP proxy reproduces the original hang and verifies the correction.

The second Codex review found that MySQL/MariaDB statement deadlines were
implemented by the driver but rejected by the runtime cancellation gate.
`Capabilities.statementTimeout` now distinguishes connection-discard deadlines
from token cancellation. The raw runtime and ORM accept per-operation timeouts;
transaction deadlines and retries still require actual interruption. All 140
driver, typed database and transaction-boundary regressions pass against real
MySQL/MariaDB, including unknown-outcome messaging and caught-timeout failure.

## Linux CI portability corrections

The first Linux CI run revealed test assumptions hidden by macOS: borrowed
PostgreSQL fixtures omitted URL passwords, an import fixture used `compile exe`
without bundling native assets, and interruption tests assumed every SQLite build
exports `sqlite3_interrupt`. These are corrected without substituting another
SQLite library or changing the runtime capability contract. The PostgreSQL temporal
and acquisition regression run passes 48 checks after the fixture correction.
Linux arm64 passes 21 focused checks and two real AOT bundles, with 23 explicit
capability skips (8 interruption scenarios and 15 bounded retries). The same
focused suites on macOS/PostgreSQL pass 84 checks, with four inverse unsupported-
capability checks skipped. These platform runs use the unchanged `46265f83` runtime
plus the portability test fixtures. [Structured record](standalone-native.json).

CLI workflows kept progressing in the original run; repeated independent Dart
starts made the full run longer than local acceptance. CI now permits 45 minutes
without removing checks. Canceled earlier runs are not passing acceptance evidence.

The complete Linux run on `326f41e8` then reported 1129 passed, 17 failed and
25 skipped. All remaining failures were interruption assumptions in transaction,
acquisition and watch tests. Their correction preserves ordinary COMMIT failure,
unknown acknowledgement, acquisition and subscription checks; it only skips actual
interruption scenarios and explicitly verifies unsupported controls before SQL.
The corrected three suites pass 41 tests with 14 capability skips on Linux, and
108 tests with four inverse-capability skips on macOS/PostgreSQL.
Runtime and Web assets remain identical to `3aef4e79`. The final PR run, not this
failed attempt, is the complete merge gate.

The subsequent complete native Linux run on `e933576a` succeeds: **1136 passed,
41 capability skips, zero failures**. Its Chrome JS report also passes all 21
scenarios, but the runner exits unsuccessfully when profile deletion races with
exiting Chrome child processes. Runner cleanup is corrected with bounded retries,
and browser checks run as a separate CI job so their outcome is visible early.
The cleanup correction passes five deterministic regressions and five real Chrome
runs on macOS: Dart JS/WASM and Flutter Web JS/WASM with and without isolation
each pass 21 scenarios, including successful runner exit and profile deletion.
The final workflow must pass both jobs before merge.

## Explicit boundaries

MySQL/MariaDB provide exact values, storage, comparison and MIN/MAX within their
physical limits. Typed arithmetic, SUM, decimal set operations and explicit
precision narrowing that can silently lose digits are rejected; see the
[reproductions](../mysql-precision-boundaries.md) and [driver contract](../../doc/mysql.md).
Their initial adapters own a single queued connection and do not support streaming
or cancellation. Runtime leases add a cleanup ROLLBACK round trip. DDL remains
non-atomic and uses the [engine-specific recovery workflow](../../doc/mysql-migrations.md).

The default Linux native asset in `sqlite3` 3.6.0 hides `sqlite3_interrupt`.
Statement cancellation, execution deadlines and bounded retries are rejected
before SQL; ordinary database operations and streaming remain supported. Tests
check that refusal explicitly and skip only scenarios requiring interruption.
Native executables must use `dart build cli` and ship the whole bundle.

Chrome and an Android emulator do not certify Safari, Firefox, physical devices,
iOS or macOS Flutter. Timer/animation progress establishes worker separation,
not a frame-rate or throughput improvement. Historical benchmarks and validation
files retain their original source revisions; this change makes no new performance
claim. No package was published.
