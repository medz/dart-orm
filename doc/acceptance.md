# Validation guide

Use the repository checks to verify the API and database behavior after a change.
A test name below identifies a scenario to exercise, not a claim that the current
checkout has passed it. [Progress](https://github.com/medz/dart-orm/blob/main/doc/progress.md) records completed validation;
[capabilities](https://github.com/medz/dart-orm/blob/main/doc/capabilities.md) states database and platform limits.

## Start with the public workflow

From a disposable consumer project, initialize a database, generate its client,
create and review the first migration, then apply and verify it. Run a typed
projection and a transaction through generated table getters. Change a model,
regenerate, and ensure the analyzer catches stale result or input types. The
[CLI guide](https://github.com/medz/dart-orm/blob/main/doc/cli.md) and [quickstart](https://github.com/medz/dart-orm/blob/main/README.md#get-started) provide the commands.

Verify independent imports as well: values and schema metadata need no connection;
typed SQL can compile offline; a raw driver and runtime work without generated
models; saved migrations do not import current application models. The
`layer_boundaries_test`, `runtime_test` and `sql_builder_test` suites exercise
these contracts.

## Choose regression suites by behavior

All names below refer to files under `test/` with the `_test.dart` suffix.

| Changed behavior | Representative suites |
| --- | --- |
| Model declarations and generated types | `generator`, `generator_dialects`, `nominal_generation`, `types`, `generated_database`, `nominal_database` |
| Build/watch and project commands | `builder`, `cli`, `cli_workflow`, `named_sql_generation`, `import_cli`, `migration_plan_cli` |
| Projections, mapping and query scope | `database`, `selection`, `query_boundary`, `union`, `plan` |
| Keys, relationships and batched loading | `relation`, `many_to_many`, `unconstrained_relation` |
| Values and custom codecs | `integer`, `custom_codec`, `temporal`, `temporal_precision`, `decimal`, `decimal_division`, `decimal_average` |
| Defaults, generated values and constraints | `client_default`, `computed`, `check` |
| Sessions, transactions and failure recovery | `transaction`, `retry`, `acquisition`, `stream`, `session_connection`, `runtime_lifecycle_review` |
| Subscriptions and execution observations | `watch`, `observation` |
| Migration history, catalog and recovery | `migration`, `migration_target`, `migration_recovery`, `backfill`, `schema_version`, `import` |
| MySQL and MariaDB behavior | `mysql_driver`, `mysql_database`, `mysql_import`, `mysql_transaction_boundary`, `mysql_migration` |

Use real database URLs to enable the server suites. Tests create their own tables
or schemas; MySQL/MariaDB recovery tests require permission to create isolated
databases. See [contributing](https://github.com/medz/dart-orm/blob/main/doc/contributing.md) for environment variables and the
complete native command. Capability-dependent skips must be reported separately
from passes, especially when the SQLite build cannot interrupt running SQL.

## Verify browser and Flutter behavior

From the repository root:

```sh
dart run tool/test_browser.dart
dart run tool/test_browser.dart --wasm
dart run tool/test_flutter_web.dart /absolute/path/to/flutter
```

Browser checks exercise packaged resource identity, generated queries, memory and
OPFS storage, reopen/upgrade, constraints, transactions, cursors, subscriptions,
value transport and explicit rejection of unsupported interruption. They use real
Chrome and record JS/WASM mode. The Flutter Web runner also verifies release
packaging, nested routes and configurations with and without isolation headers.

For Android, follow the [APK upgrade and restart workflow](https://github.com/medz/dart-orm/blob/main/doc/flutter.md). Browser,
Android and native server validation are separate: one passing target does not
establish another. Keep SDK, database, browser/device, source revision and report
paths with the validation result. Reports are local outputs under `.dart_tool/`.

## Check documentation and packaging

After static analysis, run `dart doc --validate-links` to generate the actual API
site when changing categories, exports or documentation links. Inspect library
navigation, public type signatures and links in the generated pages. Documentation
must expose usable public APIs without presenting internal helpers as supported
entrypoints.

Run `dart pub publish --dry-run` to inspect the package archive. Handwritten
`doc/`, examples and runtime resources belong in the package; generated `doc/api/`,
local validation output and repository-only tools do not. Verify the published
version separately when making an actual release.

## Measure performance separately

Use [runtime benchmarks](https://github.com/medz/dart-orm/blob/main/doc/performance.md), [generation/editor measurements](https://github.com/medz/dart-orm/blob/main/doc/generation.md)
and the [decimal cost probe](https://github.com/medz/dart-orm/blob/main/doc/decimals.md#verify-precision-and-measure-cost) for
performance work. Preserve result semantics, transaction boundaries and exact
query volume when comparing revisions. Correctness tests, allocation traces and
latency measurements answer different questions and should have separate results.
