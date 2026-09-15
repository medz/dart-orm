# Design acceptance map

The common ORM lifecycle in
[`new-dart-orm-design.md`](../research/new-dart-orm-design.md) is implemented and
accepted within the [reviewed capability boundaries](capabilities.md). The final
native run passed 835 tests with both databases enabled; the documented usage
run and static analysis also passed. This map identifies the checked scenarios
and separately captured platforms, rather than certifying every database feature
or deployment target. Historical measurements remain pinned to their source.

## Implementation with direct test coverage

| Design requirement | Current evidence |
| --- | --- |
| §§2, 4–5: Record declarations, separate table identity, restricted selectors, static input/result types | `lib/schema.dart`, `lib/src/generate/`; `generator_test`, `types_test`, generated fixtures and `generated_database_test` |
| §§4–5: compound keys, physical names, indexes, FK navigation, domain codecs | Generator, `relation_test`, `integer_test`, `custom_codec_test`, catalog/import tests |
| §§5, 10–11: temporal column precision | `temporal_precision_test`: generated declarations and SQL coercion, epoch ties, finite ranges, defaults/computed values, rounded relation keys, import/catalog drift and reviewed migration rollback; real JS/WASM worker scenario; [semantics](types.md#temporal-precision) |
| §4.2: explicit navigation without database FKs | `relatesTo`; `unconstrained_relation_test` checks missing/duplicate targets, composite/self/inverse edges, no FK/index/cascade, watch and constraint transitions; generator/type negatives |
| §12 declaration table: general CHECK constraints | `check_test`, generator/CLI tests and browser scenario: declaration, native enforcement/NULL, catalog/import, drift, add/change/remove/rename and atomic rollback; limits in [checks](checks.md) |
| §§4.3, 5, 8: client-generated values separate from database defaults | `client_default_test`, generator/type negatives and browser scenario: typed factories, omission/value/null/DEFAULT, batches, conflicts, preparation/reuse and rollback; snapshots/imports exclude client code; [defaults](defaults.md) |
| §§4.3, 5, 8: database computed/read-only columns | `computed_test`, generator/type negatives, CLI and browser scenario: stored/virtual declaration, read-only fields, CRUD/relations, catalog/import, expression/type/add/drop/materialization/rename and atomic rollback; [native limits](computed.md) |
| §6: scalar, positional/named Record and DTO projections; dynamic fields and lazy immutable queries | `database_test`, `generated_database_test`, `union_test`; mappings execute after rows arrive |
| §6: joins, grouping/HAVING, subqueries, CTEs, windows and UNION | `union_test`, `relation_test`, `watch_test`, decimal/temporal query suites; exported-column and scope checks |
| §6: named SQL with typed parameters/results and database structure checking | `named_sql_test`, `named_sql_generation_test`, real CLI/build_runner workflows |
| §§6–7: stable cursors, optional/required to-one, batched lists and per-parent limits | `database_test`, `relation_test`, cursor checks in numeric/temporal suites; actual query counts and nullable presence |
| §§4.2, 7, 12: many-to-many business records | `example/teams`, `many_to_many_test`, generated-type negatives and browser scenario: two FKs, composite membership keys, role/time payloads, bidirectional and nested projections, per-parent limits, parameter chunks, transaction/upsert/cascade/watch and actual query/row counts; [usage](relations.md#many-to-many-with-business-fields) |
| §8: create/patch/delete, absent versus NULL/default, atomic expression writes, batch/upsert/returning | Generated client and `database_test`; later-chunk failure rolls back earlier chunks |
| §9: explicit sessions, savepoints, lifetime, cancellation, unknown commits, retries and acquisition limits | `transaction_test`, `retry_test`, `acquisition_test`, `stream_test`; real database interruption and state readback |
| §10: reviewed snapshots/diffs, explicit rename/conversion, history, baseline/drift and recoverable migrations | `migration_test`, `migration_recovery_test`, `backfill_test`, `schema_version_test`, import and CLI suites |
| §11: distinct PostgreSQL/native SQLite configuration and connection ownership | `lib/postgres.dart`, `lib/sqlite.dart`; native suites exercise both backends, capability rejection, borrowed pools and disposal |
| §§11–12: worker/persistence, real cursor streaming and commit-driven observation | Native `stream_test`/`watch_test`; real JS and Dart WASM browser reports include OPFS reload recovery and upgrade |
| §§11–12: native Flutter | `example/flutter`, `tool/test_flutter.dart` and [Android capture](flutter.md): version 1 debug APK → version 2 AOT release APK → independent process restart; 4/17/11 assertions cover background SQLite, persistence, live migration/catalog, generated CRUD/relations, rollback/watch and cancellation/reuse |
| §12: inspectable query structure and execution phases | `plan_test`, `observation_test` and real JS/WASM teams scenario: non-executing SQL/column/key/join/batch descriptions, composite parameter capacity, real acquisition waits/cancellation, decode/stream/RETURNING scopes and observer exception isolation; [measurement limits](observability.md) |
| §13.3: runtime cost comparison | `tool/benchmark_runtime.dart`, captured `research/benchmarks/runtime.json` and [method/results](performance.md): same Driver/SQL/parameters/shape, four read workloads, 200 samples per lane, concurrent throughput, byte/row counts, acquisition distributions, live heap and selected allocation traces; native JIT with actual echo calibration of controlled TCP latency, not a remote deployment or total-allocation-byte census |
| §13.3: editor protocol measurements | `tool/benchmark_editor.dart`, `research/benchmarks/editor.json` and [method/results](generation.md#editor-completion-diagnostics-and-rename): real generated APIs at 10/100/1000 models, 300 warm samples across five completion probes, twelve exact-code/range diagnostic checks, language-symbol rename edits and final consumer analysis; the subsequent `research/validation/editor-recovery.json` records a same-session timeout at ten models and a successful restart path, without claiming GUI or general IDE reliability |
| §13.2: declaration-form experiment | `tool/compare_authoring.dart`, `research/benchmarks/authoring.json` and [scope/results](authoring.md): actual Record/primary-class/table inputs for User/Post/Profile/Follow, identical canonical schema/client/snapshot for base/type-edit/rename variants, six stale-consumer failures and repaired analyses, complex constraints, schema LSP edits and fourteen original-source error locations; experimental class/table adapters emit Record rows and do not implement nominal object materialization |

The filenames in this table refer to `test/<name>.dart` unless another location
is shown. The browser report is
[`research/validation/browser.json`](../research/validation/browser.json), with
commands and limits in [SQLite web](sqlite-web.md).

The subsequent [selection cost capture](../research/benchmarks/runtime-selection.json)
uses runtime `d0a8c9a`. Exact SQL, parameters and result/transport volumes match the
baseline. It records fewer selected List allocations, without establishing a
latency or throughput gain; the [comparison](performance.md#direct-selection-decoding)
also documents the PostgreSQL protocol lifecycle tradeoff. `selection_test` adds
direct coverage for deferred/ordered mapping, repeated fields, all typed arities,
streaming, failures and dynamic field snapshots on both native backends.

## Final lifecycle audit

| Design §3 scenario / acceptance gate | Verification |
| --- | --- |
| Add a defaulted field without rewriting existing create calls | Generated type/default tests and actual Android v1 → v2 migration preserve rows and populate the new field |
| Select emails only, returning `List<String>` | Native projection/plan tests and executable cookbook scalar selection |
| Root pagination plus each parent's latest three titles | Native relation checks, `three_posts` runtime workload and browser generated-relation scenario; actual SQL counts and parameter chunks |
| Create a parent and children in one transaction | README and teams examples, native generated tests and actual Android relation write |
| Clear a nullable field and increment atomically | Generated patch/expression-write tests, NULL/default negative type checks and transaction suites |
| Separate Dart rename from physical column rename | Generated snapshot/authoring tests, CLI migration diff and real migration/recovery tests; Record field rename remains manual |
| Switch SQLite memory/file/worker storage | Native persistence and read-only tests, Chrome JS/WASM OPFS reload/upgrade, Android APK upgrade/restart |
| Keep database-specific configuration and ownership explicit | Separate typed driver inputs, wrong-backend compilation failures, borrowed PostgreSQL pools and cancellation/acquisition tests; unimplemented transports are not certified |
| Process large results and release sessions | Real SQLite/PostgreSQL cursors, batching, early stream cancellation and post-failure connection reuse; browser stream/release scenario |
| Check version, migration state and live structure before deployment | CLI/import/baseline tests, application-version tests, durable backfill and nontransactional recovery, Android bundled migration checks |
| Review query, type and unmanaged catalog coverage | [Capability review](capabilities.md); final native suite includes real triggers and complete policy/RLS metadata checks |
| Run documented onboarding and complex query usage | [Usage capture](../research/validation/usage.json): dependencies, generation, both existing examples, nine cookbook checks on each backend, migration-chain validation and clean analysis |

The [Dart migration acceptance](../research/validation/dart-migrations.json) records
the replacement of JSON artifacts with Dart snapshots, fixed history and static
registration. Its full native run passed 837 tests and found one old fixture path;
the correction and final generator changes pass a 76-test follow-up. The record
retains both logs instead of claiming a single all-green full invocation. AOT
checks execute compiled history without consumer source files and resume historical
backfills. The original [835-test capture](../research/validation/native.json)
remains a historical baseline.

Current Chrome JS/WASM and Android APK captures use the Dart workflow source.
Android proves the native Flutter lane on its recorded emulator, including compiled
migration definitions, upgrade and process restart; it does not certify Apple
platforms or every server type/scenario. See [Flutter scope](flutter.md) and
[browser scope](sqlite-web.md) for the exact assertions.

## Extension boundaries in the design

Design §12 explicitly places PostgreSQL-specific JSON/array/COPY/locking and
SQLite FTS expansion behind real demand. HTTP/serverless transports require
their own session/capability verification. These are not silently provided by a
native driver or raw-SQL escape hatch. Distributed transactions, synchronization,
arbitrary object-graph tracking and a general optimizer remain separately scoped
in the design. Calendar SQL arithmetic, timezone-rule conversion and additional
native types also remain explicit extensions, as recorded in the capability
review. They are not presented as working APIs or hidden behind silent fallbacks.
