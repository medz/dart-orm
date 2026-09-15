# Design acceptance map

This is a requirement/evidence index for
[`new-dart-orm-design.md`](../research/new-dart-orm-design.md), not a declaration
that the goal is complete. A passing suite proves its checked scenarios; it does
not close an item whose required evidence is missing. Current run results and
platform limits are recorded in [progress](progress.md).

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
| §12: inspectable query structure and execution phases | `plan_test`, `observation_test` and real JS/WASM teams scenario: non-executing SQL/column/key/join/batch descriptions, composite parameter capacity, real acquisition waits/cancellation, decode/stream/RETURNING scopes and observer exception isolation; [measurement limits](observability.md) |
| §13.3: runtime cost comparison | `tool/benchmark_runtime.dart`, captured `research/benchmarks/runtime.json` and [method/results](performance.md): same Driver/SQL/parameters/shape, four read workloads, 200 samples per lane, concurrent throughput, byte/row counts, acquisition distributions, live heap and selected allocation traces; native JIT with actual echo calibration of controlled TCP latency, not a remote deployment or total-allocation-byte census |
| §13.3: editor protocol measurements | `tool/benchmark_editor.dart`, `research/benchmarks/editor.json` and [method/results](generation.md#editor-completion-diagnostics-and-rename): real generated APIs at 10/100/1000 models, 300 warm samples across five completion probes, twelve exact-code/range diagnostic checks, language-symbol rename edits and final consumer analysis; excludes GUI rendering and the mixed-session rename issue described there |

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

## Open implementation and acceptance gates

| Gate from the design | Evidence still required |
| --- | --- |
| §§5, 10–11: remaining type/catalog capability review | Verify supported types against imported precision, defaults, native representation and migration behavior. Timezone conversions and remaining temporal operations are open in [types](types.md). Unsupported extensions must stay explicit. |
| §13.2–13.3: authoring/editing costs | Build/watch/analyze and actual LSP completion/diagnostic measurements now cover 10/100/1000 models. The identical-API Record/primary-class/table authoring comparison remains open, including generated API refactor propagation, complex constraints and error locations. Record field rename is unavailable in the checked SDK; mixed-session rename after error recovery remains unverified. No claim of superiority over class/table declarations. |
| §§11–12: native Flutter | An actual Flutter application exercising background SQLite, persistence, older-schema upgrade and watch delivery. Standalone macOS JIT/AOT and Chrome are different evidence. |
| §§3, 12–13: whole-product acceptance | Run the documented onboarding, generated CRUD/relations, persistent migration/recovery and compatibility workflow on final source. Reconcile this map and every pending item in progress before completing the goal. |

## Extension boundaries in the design

Design §12 explicitly places PostgreSQL-specific JSON/array/COPY/locking and
SQLite FTS expansion behind real demand. HTTP/serverless transports require
their own session/capability verification. These are not silently provided by a
native driver or raw-SQL escape hatch. Distributed transactions, synchronization,
arbitrary object-graph tracking and a general optimizer remain separately scoped
in the design. These boundaries do not excuse the open common ORM gates above.
