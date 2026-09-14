# Implementation status

The active goal is the complete ORM described in `research/new-dart-orm-design.md`.
This file records verified delivery, not planned capabilities presented as working.

## Completed

- Reset the `next` branch contents, preserving the design research and license.
- Establish one Dart 3.13 package and local-only commit policy.
- Typed scalar expressions, 2–6-field composable projections and dynamic field maps.
- Immutable filters, order, offset/limit, count/exists, basic aggregation and mutations.
- Parameter binding, table occurrence scope checking, explicit default/null changes.
- Native SQLite worker with verified foreign keys, journal mode and parameter limit.
- PostgreSQL driver with a single pool owner, TLS settings and explicit borrowed pools.
- Transaction lifecycle, rollback, savepoints, pending work checks and query observation.
- Analyzer-based record generator, scalar annotations, composite keys, indexes and FK validation.
- Generated table accessors, named create parameters, byId, typed patches and schema snapshots.
- Batched and nested relation projections, per-parent SQL window pagination, optional/required relations.
- Correlated relation any/none/every/count; UNKNOWN fails every, and empty sets satisfy it.
- Dialect DDL, cyclic PostgreSQL FK creation, immutable migration checksums and atomic history.
- Concurrent migration serialization, read-only planning, column inspection and column drift checks.
- Runnable generated-client example with migrations, transactions and relationship selection.
- Atomic upsert with declared unique targets and typed existing/incoming field expressions.
- Batch inserts with parameter-aware chunks, optional field shapes, returning and all-chunk rollback.
- Explicit alias joins/self joins, guarded outer-join projections, scalar/IN/EXISTS subqueries.
- SQL window expressions and pre-execution aggregate/grouping placement checks.
- CTEs with typed references to exported SQL expressions, mapped row decoding and nullable exports.
- Keyset pagination with unique tie breakers, mixed directions, explicit null ordering and versioned cursor transport.
- Actual generated-API negative type tests and checked codec calls after generic type erasure.
- Connection leases spanning transactions, with scoped lifetime and explicit discard.
- Portable schema snapshots; catalog checks for columns, defaults, keys and simple indexes.
- Existing-database baselines verify declared schema facts before recording immutable history.
- Unmodeled constraints, expression/partial indexes, triggers and policies are reported separately.
- Reviewable migration diffs, explicit renames/conversions, destructive-change gates and checksum chains.
- SQLite atomic copy/rebuild with preserved dependency SQL, foreign-key validation and state restoration.
- PostgreSQL constraint changes resolve actual catalog names, including baselined schemas.
- Migration CLI: create/check/plan/apply/status, table inspection, schema verification and baselines.
- Explicit SQLite read-only connections; CLI read operations never create a missing database.
- PostgreSQL recoverable autocommit steps with boolean pre/postconditions and immutable attempt checksums.
- Durable per-step progress, exact concurrent-index state checks, explicit INVALID-index repair and CLI visibility.
- Shared migration/baseline session locks use bounded try-lock polling without retaining waiting snapshots.
- Database cursors with demand-driven batches, per-batch relation loading and scoped stream cleanup.
- Real SQLite native interruption and PostgreSQL control-connection cancellation with awaited cleanup.
- Per-statement deadlines, poisoned-transaction protection and atomic cancellation between batch chunks.
- Explicit cancellation capabilities, borrowed-pool ownership and failed-control connection disposal.
- To-one JOIN strategy using declared uniqueness, with explicit join/batch choices and cardinality checks.
- Composite-key batch execution, tuple matching, parameter accounting and nested JOIN/window combinations.
- Joined optional/required projections preserve row presence, nullable values, CTE exports and cursor decoding.
- Constant schema codecs retain custom classes, extension IDs, nullable aliases and nested generic/record types.
- Portable enum text labels, generation-time codec matching and stable imports for separately declared domain types.
- JSON scalar decoding and explicit SQL-null/document-null distinction across SQLite and PostgreSQL.
- Typed query subscriptions with commit/savepoint boundaries, relevant-table filtering and declared FK delete effects.
- Dependency discovery across joins, subqueries, CTEs and batch relations; explicit raw/external-write notifications.
- Paused subscription coalescing, stale-read suppression, active-query cancellation and driver-wide subscription cleanup.
- Opt-in build_runner integration with explicit roots, shared generation/formatting and resolver-owned dependency tracking.
- Asset-based and real-process generation checks, imported metadata invalidation, upstream builder inputs and stale-output cleanup.

## Delivery sequence

1. Typed schema metadata, SQL expressions, projections, query and mutation execution.
2. Native SQLite worker and PostgreSQL drivers, explicit transactions and savepoints.
3. Record schema generator, typed table entry points and relationship declarations.
4. Batched relationship projections, root and per-parent pagination, nested relations.
5. Migration snapshots, dialect DDL, history/checksums, introspection and drift checks.
6. Advanced SQL, custom codecs, streaming, observation, Web adapter and capabilities.
7. CLI, examples, user documentation, real-database and platform acceptance checks.

## Validation

The research type proof was analyzed and ran with JIT and AOT; JavaScript compilation
also passed. These checks do not constitute a working ORM or browser validation.

Static analysis is clean. The complete suite passes 265 checks with native SQLite
and a disposable PostgreSQL 18.4 instance enabled. It exercises generation,
composite-key source validation, projections, relations, per-parent pagination,
transactions, migration rollback/history and the generated application client.
This includes a SQLite catalog regression for nullable non-rowid primary keys
and three independent CLI process workflows (SQLite lifecycle, SQLite baseline,
and PostgreSQL lifecycle, including autocommit plans/progress). The full suite
passes in one invocation. Thirteen recovery checks include two real process exits
at durable SQL/commit boundaries, INVALID indexes, lock deadlines and concurrent
runners; committed work is not replayed on resume.
`dart run example/main.dart` runs successfully against a real in-memory SQLite DB.
The generated SQLite example also compiles and runs as a native macOS AOT executable.
Thirty-seven streaming/execution checks cover native cursor fetches, pause/resume,
early exit, relation loading, deadlines, cancelled writes, failed control connections
and delayed cancellation races. A batch-cancellation regression was first reproduced
as a partial commit and now verifies rollback on both databases.
`test/support/native_execution.dart` additionally compiles and runs as a macOS AOT
executable, verifying joined records, nullable required values, absent relations,
cursor consumption, `sqlite3_interrupt`, subsequent SQL and committed query subscriptions.
The relationship fixture is generated from a record schema with nullable composite
foreign keys and self-relations. It verifies 1200-key batches, key deduplication,
per-parent windows, nested JOINs, whole-row absence and root pagination on both
backends. Generator checks compare committed client code and schema snapshots.
The domain-type fixture adds 18 real-database checks for extension IDs, custom
classes, enums, structured JSON, nullable document presence, relations, batches,
upsert, cursors and schema catalogs. JSON string scalars are decoded without a
second parse; SQL NULL and JSON null are separately represented, and required JSON
documents reject SQL NULL. Generator checks cover moved outputs, colliding domain names, nullable
aliases and invalid annotations. `test/support/codecs/native.dart` passes as a
macOS AOT program with domain values, relations and streamed cursors.
Forty-one subscription checks cover both backends, including independent SQLite
workers and PostgreSQL connections, transactional notification merging, savepoint
rollback, zero-row writes, multi-level cascade/SET NULL effects, joined CTEs and
batch relations. They also verify paused-listener cleanup, native cancellation,
read/invalidation races and re-reading after a real PostgreSQL commit whose
acknowledgement is deliberately lost. Subscriptions add no browser/Flutter
acceptance claim.
Eight asset-builder checks and one real consumer-process workflow verify the
standard build_runner path, prior-builder inputs, imported metadata invalidation,
error recovery, explicit root selection and deletion/recreation of generated
outputs. CLI and builder code/snapshots match. The generator formats in-process.
The standalone generation benchmark records 10/100/1000-model first builds,
unchanged builds, watch edits, static analysis and output sizes with pinned
environment metadata. On the recorded Apple M3 Max run, single-field watch edits
took 0.52/0.65/2.17 seconds. These are single observations with warm SDK/pub caches,
not latency percentiles, IDE completion measurements or runtime SQL benchmarks.

## Still required for the goal

- Union; advanced-query capability and edge-case review.
- Resumable long backfills, application schema-version gates and broader unmanaged-object catalog coverage.
- Existing-database declaration import and named SQL query generation.
- Configurable integer widths, exact-decimal query semantics and further native type coverage.
- Connection acquisition and total transaction deadlines, retry classification and further backend capability coverage.
- Browser worker/persistence adapter and real browser verification; native Flutter checks.
- User documentation, performance measurements and complete acceptance review.

To-one projections join by default when declared keys prove uniqueness; otherwise
they batch and check cardinality. Collections use explicit parameter-aware batches.
`verifyColumns` checks column names/types/nullability only. `verifySchema` additionally compares defaults,
keys and simple indexes; its `unmanaged` objects require separate review.
Transactional migration batches are atomic. PostgreSQL mixed migrations explicitly
use durable per-step checkpoints; SQLite rejects that autocommit mode. These are
implementation stages, not a reduction of the active goal.

The full suite includes 52 shared SQLite/PostgreSQL query checks, 20 generated
client/migration integration checks, 20 source generation checks, four codec
regressions, 19 migration evolution/catalog checks, 13 recovery checks, three CLI
workflows, 37 streaming/execution checks, 28 relation strategy checks and one
negative compilation suite covering 16 invalid API uses, plus 18 domain-codec
integration checks, 41 subscription checks, eight asset-builder checks and one
build_runner process workflow.

## Environment

Use the standalone SDK if the Flutter launcher tries to update its cache:
`/Users/seven/workspace/flutter/bin/cache/dart-sdk/bin/dart`.
