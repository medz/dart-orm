# Single-engine migration validation

Captured 2026-09-15T14:19:28.276397+00:00. Dart 3.13.3,
macOS arm64, native SQLite through sqlite3 3.6.0, and a disposable PostgreSQL 18.4
instance. The instance and test directories were owned by this run and cleaned up.

Runtime source digest: `a3c1161cff2726a66456095a2cbf86f3154cc99aa0a38d860c3e333f466a332e`. SHA-256 over lexically sorted
Dart paths under `lib`/`bin` plus `pubspec.yaml`/`pubspec.lock`, each encoded as
UTF-8 path, NUL, file bytes, NUL. Runtime sources were unchanged during these runs.

| Validation | Result | Evidence |
| --- | --- | --- |
| Complete native suite with `ORM_TEST_POSTGRES` set | 845 passed, 2 failed, 11:51 | [Full log](migration-targets-full.log) |
| Migration target and PostgreSQL recovery suites after fixing fixture configuration | 21 passed, 00:19, exit 0 | [Follow-up](migration-targets-followup.log) |
| Consumer migration source roundtrip and standalone AOT bundle after deleting consumer sources/assets | Passed in full run | `migration_source_test.dart` in full log |
| Statically registered historical backfill in native AOT | Pause, concurrent resume, exactly-once updates, startup compatibility passed | [AOT log](migration-targets-backfill-aot.log) |
| Real Chrome JavaScript | 19 checks passed | [JS log](migration-targets-browser-js.log) |
| Real Chrome Dart WASM | 19 checks passed | [WASM log](migration-targets-browser-wasm.log) |
| Public registry CLI and example entrypoint | Target initialization/preservation/rejected switch; check/apply/verify/no replay passed | [CLI log](migration-targets-cli.log) |
| `dart analyze` and `git diff --check` | No issues | Final working tree |

The full run and follow-up are separate invocations. The two failures were real
process-exit tests in `migration_recovery_test.dart`: their test project used the
SQLite registry default for PostgreSQL migration files. The new target check
rejected them before execution. The fixture now initializes a PostgreSQL registry;
both concurrent-DDL and transaction-commit exit/recovery cases pass in the follow-up.
The follow-up also covers the final empty-history connection rejection and unused
empty-expression assertions. This is not a claim of a single all-green full run.

Commands (Dart binary from the verified SDK; local `DEVELOPER_DIR` points to the
installed CommandLineTools):

```sh
ORM_TEST_POSTGRES=<disposable local PostgreSQL> dart test --reporter expanded
ORM_TEST_POSTGRES=<disposable local PostgreSQL> dart test test/migration_target_test.dart test/migration_recovery_test.dart --reporter expanded
dart run tool/test_browser.dart
dart run tool/test_browser.dart --wasm
dart build cli --target test/support/native_backfill.dart --output .dart_tool/target-backfill-aot
.dart_tool/target-backfill-aot/bundle/bin/native_backfill
dart analyze
```

The CLI smoke initialized a temporary registry using
`dart run bin/orm.dart migration registry <directory> --dialect postgres`, rebuilt
it without changing its target, and verified a SQLite retarget failed without
changing its source. `example/migrate.dart check`, `apply`, `verify`, `apply` used
an isolated `ORM_SQLITE_PATH`; the final apply returned an empty list.

Covered boundaries:

- A migration has one engine and one step list. Engine identity is checksummed;
  mixed histories and mismatched connections fail before migration SQL.
- Empty histories retain a target. Registry rebuilding preserves it and neither
  rewrites fixed fingerprints nor accepts another engine.
- Only selected CHECK/computed SQL enters frozen history. Unused overrides cannot
  change the plan, fingerprint or emitted migration source.
- SQLite virtual-column indexes, stored/virtual transitions and materialization
  work without PostgreSQL restrictions. Replacing ordinary values with computed
  values requires explicit destructive-change review.
- PostgreSQL uses its own conversion expression, constraint operations, concurrent
  indexes and recovery logic. SQLite retains rebuild/foreign-key/rollback behavior.
- PostgreSQL execution checks server version before locks or journal changes.
  Rejection of a 17.x response is a driver-double unit check; real PostgreSQL
  execution was verified on 18.4, not on an installed 17.x server.

No Android/Apple-device/Flutter runtime was rerun for this correction. The Flutter
example's Dart migration history and shared runtime were updated; the earlier
Android capture applies to its recorded revision. There is no cross-engine data
transfer or distributed transaction guarantee. Reviewed SQL, deployment downtime
and database objects outside the modeled schema still require application review.
