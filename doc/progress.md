# Implementation status

## Completed refactor

The entry APIs, explicit exports, internal module structure, public comments and
guides now form independent Dart libraries. There are no `part` or `part of`
directives in the package, examples, tools or tests. Typed declarations,
engine-specific Dart migration histories and independently usable layers remain
the foundation.

- Implementation files are grouped under values, schema, query, runtime, ORM,
  drivers, generation, migration and CLI responsibilities. Public entrypoints
  explicitly select their exports; internal compiler and runtime bridges stay
  outside the public namespace and generated API reference.
- `first()` requires a row. `firstOrNull()` and `singleOrNull()` explicitly permit
  an empty result, including write-returning queries. A selected SQL NULL remains
  a valid result. Cardinality checks on writes happen after execution; use a
  transaction when an error must roll back the write.
- Schema declarations and physical metadata have separate exports. MySQL and
  MariaDB have separate driver entrypoints. Existing connection factories remain
  the direct way to open each engine.
- Public API comments explain ownership, errors and engine boundaries. Dartdoc
  categories connect API pages to guides, with canonical library ownership and
  CI checks for broken links and ambiguous exports.
- Archived exploration artifacts are removed. Benchmark and Flutter report
  defaults use ignored `.dart_tool/benchmarks/` and `.dart_tool/flutter/` paths.

## Published baseline

`6.0.0-beta.1` is the released baseline at `5e4854df`, merged through
[PR #486](https://github.com/medz/dart-orm/pull/486). Its release CI passed 1141 native
tests with 41 capability skips and Chrome JS/WASM checks. SQLite, PostgreSQL,
MySQL 8.4 and MariaDB 11.8 formed the real-database scope. Flutter Web release
configurations and Android APK upgrade/restart were checked separately.

The [package release](https://pub.dev/packages/orm/versions/6.0.0-beta.1) remains
immutable. Unpublished refactoring does not change that archive. Platform and
engine restrictions remain documented in [capabilities](https://github.com/medz/dart-orm/blob/main/doc/capabilities.md).

## Refactor validation

Validated locally with Dart 3.13.3, Flutter 3.47.4 and Chrome 153:

- Package analysis and formatting passed; the Flutter example also passed
  `flutter analyze`. AST checks reject `part` directives and enforce layer
  boundaries. Public namespace checks verify explicit exports.
- The complete native test run used real SQLite, PostgreSQL 18, MySQL 8.4 and
  MariaDB 11.8: 1209 passed, 8 capability skips and 2 failures. Both failures were
  the SQLite/PostgreSQL executions of an old upsert fixture expecting nullable
  `first()`. After migrating it to `firstOrNull()`, the complete database,
  cardinality, migration, export and layer suites passed again: 114 tests, zero
  failures. These are separate runs, not a single all-green full-suite run.
- The native run includes generation, CLI, migration recovery, transactions and
  database integration suites. The dedicated cardinality suite covers empty
  results, selected NULLs, limits, write-returning behavior and rollback.
- Chrome JS and WASM each passed 21 browser scenarios. Flutter Web passed the
  same 21 scenarios in JS, WASM without isolation and WASM with isolation. These
  include OPFS persistence, reload recovery, nested-route asset resolution,
  transactions, worker responsiveness and real Flutter frame progress.
- The main example ran successfully. The query cookbook passed all 9 checks on
  both SQLite and PostgreSQL. Committed SQLite worker/WASM fingerprints match
  the refactored source.
- `dart doc --validate-links` generated 21 public libraries with zero warnings
  and zero errors. The generated index was checked for canonical API ownership
  and absence of internal compiler/session helpers.
- Publication dry-run inspected the package archive, excluding generated docs,
  local caches, repository test tools and removed artifacts. After committing,
  `dart pub publish --dry-run` passed with zero warnings.

Android, iOS, native macOS/Windows/Linux Flutter applications and non-Chrome
browsers were not rerun for this refactor. Earlier Android release evidence
belongs to the published baseline. Local logs and browser reports live under
ignored `.dart_tool/` directories; they are not published package contents.

This refactor is a local, unreleased change. The beta.1 archive above is unchanged.

See [validation](https://github.com/medz/dart-orm/blob/main/doc/acceptance.md) and [contributing](https://github.com/medz/dart-orm/blob/main/doc/contributing.md) for commands.
