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
- Transaction-wide deadlines/cancellation with native SQL interruption, callback expiry and awaited cleanup.
- SQLite actual transaction-state reporting, automatic rollback recovery and invalidated-savepoint protection.
- Conservative server failure classification distinguishing known commit rejection from unknown outcome.
- Opt-in transaction replay and SQLite COMMIT-only retry with shared attempt/time budgets and cancellable backoff.
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
- SQL UNION/UNION ALL with typed 2–6-field SQL records, scalar operands and post-query mapping.
- Positional column/codec/nullability validation, scoped branch clauses, CTE exports, streams and set subscriptions.
- PostgreSQL typed standalone parameter projections and exact integer aggregate decoding.
- CTEs with typed references to exported SQL expressions, mapped row decoding and nullable exports.
- Keyset pagination with unique tie breakers, mixed directions, explicit null ordering and versioned cursor transport.
- Actual generated-API negative type tests and checked codec calls after generic type erasure.
- Connection leases spanning transactions, with scoped lifetime and explicit discard.
- Portable schema snapshots; catalog checks for columns, defaults, keys and simple indexes.
- Existing-database baselines verify declared schema facts before recording immutable history.
- Read-only catalog import drafts Record declarations, physical-name maps and review reports, followed by the normal generator/baseline workflow.
- Import preserves supported defaults, identities, composite/unique keys, indexes and named inverse relations; unsupported structures have explicit issues.
- Signed 16/32/64-bit integer column metadata, native PostgreSQL types and verified SQLite range constraints, independent of value/aggregate codecs.
- Width-aware generation, catalog import, immutable snapshots, rename/type migrations, identity sequences and historical backfills.
- Read-only application startup version checks with explicit compatibility ranges, full history validation and recovery-state rejection.
- Unmodeled constraints, expression/partial indexes, triggers and policies are reported separately.
- Reviewable migration diffs, explicit renames/conversions, destructive-change gates and checksum chains.
- SQLite atomic copy/rebuild with preserved dependency SQL, foreign-key validation and state restoration.
- PostgreSQL constraint changes resolve actual catalog names, including baselined schemas.
- Migration CLI: create/check/plan/apply/status, table inspection, schema verification and baselines.
- Explicit SQLite read-only connections; CLI read operations never create a missing database.
- PostgreSQL recoverable autocommit steps with boolean pre/postconditions and immutable attempt checksums.
- Durable per-step progress, exact concurrent-index state checks, explicit INVALID-index repair and CLI visibility.
- Historical-schema backfills on both databases with bounded primary-key batches, atomic data/cursor commits and completion proofs.
- Shared batch budgets, lossless composite cursors, competing-runner recovery and committed subscription notifications.
- Shared migration/baseline session locks use bounded try-lock polling without retaining waiting snapshots.
- Database cursors with demand-driven batches, per-batch relation loading and scoped stream cleanup.
- Real SQLite native interruption and PostgreSQL control-connection cancellation with awaited cleanup.
- Cancellable, bounded connection acquisition with monotonic entry checks and safe late-lease draining.
- Independent PostgreSQL pool/connection deadlines, with acquisition settings propagated through queries, mutations, batches, streams and watches.
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

Static analysis is clean. The complete suite passes 506 checks with native SQLite
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

Thirty-two set-query checks cover both backends, including repeated positional
columns, nested set association, operand-local CTE names/order/limits, final DTO
mapping, outer-join nullability, shared domain codecs, all built-in constant types,
SQL NULL versus JSON null, scalar subqueries, native streams and committed changes
from either operand. Negative compilation includes mismatched scalar and Record
operand types. The native macOS AOT integration also verifies typed UNION Record
streaming. Whole generated entity/Dart-mapped projections must explicitly select
SQL `.row` fields before UNION; arbitrary mapper equivalence is never inferred.

Connection acquisition is verified with twenty shared SQLite/PostgreSQL checks,
three additional PostgreSQL checks (initialization, connection versus queue limits,
and native pool timeout classification), and a controlled event-loop starvation
regression using the native SQLite driver. Timed-out mutations, batch transactions,
sessions and queries never execute after their late leases arrive. Stream
cancellation, watch recovery, pool PID reuse, resource draining and application
error propagation are checked. macOS AOT also verifies that an expired queued
write never runs after the held lease is released. Acquisition controls remain distinct from transaction-wide execution deadlines.

Forty-one transaction-control checks cover SQLite and PostgreSQL plus actual
concurrent connections and failure-injecting driver wrappers. They verify idle
and CPU-bound callbacks, active reads/writes/cursor fetches, paused streams,
borrowed sessions, savepoint cleanup, expired connection acquisition, native
BEGIN/COMMIT lock waits, automatic rollback, deferred constraint rejection,
known COMMIT acknowledgement races, lost acknowledgements and failed rollback.
PostgreSQL serialization failures and deadlocks are produced by real competing
transactions. SQLSTATE 40003 at COMMIT remains conservatively unknown. Native
macOS AOT verifies transaction expiry and automatic rollback across a savepoint.
Twenty-nine retry checks verify explicit opt-in, exact attempt limits, acquisition
and execution time budgets, cancelled backoff, fresh transaction views, discarded
failed-attempt notifications, unknown commits and failed rollback. Actual competing
PostgreSQL connections produce serialization/deadlock conflicts; SQLite workers
produce WAL busy-snapshot and DELETE-journal COMMIT conflicts. Both callback replay
and COMMIT-only retry share one finite budget. The acquisition timer preserves its
own error class rather than inferring the source from an elapsed clock.
`test/support/native_retry.dart` compiles and runs as a macOS AOT executable against
two SQLite workers, verifying snapshot replay and COMMIT retry without replaying
the successful callback.

Nineteen application-version checks cover both databases: exact latest and explicit
inclusive ranges, unversioned databases, rejected downgrades, old checksum changes,
missing history, baselines, separate catalog drift, borrowed sessions and invalid
ranges. PostgreSQL checks use a real partially completed recoverable migration,
repair/resume and concurrent checkpoint creation during a consistent read snapshot.
The caller's history list is frozen before asynchronous reads. A read-only SQLite
file accepts a compatible version without applying migrations. The native macOS
AOT execution fixture also checks accepted and rejected schema versions.

Fifty-six backfill checks cover both databases: bounded pause/resume, unchanged
historical JSON/checksums, atomic cursor/data rollback, failed completion proofs,
compatible and incompatible concurrent writes, competing runners and lost COMMIT
acknowledgements. Four actual child-process exits at data-write and commit boundaries
verify that committed chunks are retained and uncommitted chunks are repeated only
after rollback. Native integer, bigint, text, finite real, boolean, timestamp and
binary keys survive resume, including composite keys under a reduced parameter
limit. Additional checks cover ordinary migration grouping, SQLite rebuild/FK
restoration, old checkpoint-table upgrades, invalid cursors, temporary-object
shadowing, PostgreSQL row security and inherited duplicate keys. Independent CLI
processes inspect plans, pause, report progress and finish backfills on both
databases. Committed chunks notify typed subscriptions, and completion probes
reject floating-point truthiness. `test/support/native_backfill.dart` compiles and
runs as a macOS AOT executable, verifying historical declarations, bounded runs,
concurrent SQLite workers and the application startup version gate. The existing
native execution acceptance fixture also passes after this change. These are
correctness checks, not backfill throughput or online availability measurements.

Seventeen catalog-import checks verify both databases, including physical/Dart
name collisions and escaped identifiers, identities/defaults, composite/self
relations, unique indexes, read-only SQLite, scoped sessions, excluded unsupported
types and generated expressions, nullable primary keys, virtual/shadow tables,
PostgreSQL inheritance and specialized index semantics. Draft declarations pass
the real analyzer/generator and produce matching schema snapshots. An imported
client runs against PostgreSQL, and the SQLite client compiles and runs as a macOS
AOT executable; both preserve existing rows and execute typed relationship queries,
defaulted writes and SET DEFAULT deletes after a verified baseline. Two additional
CLI workflows independently import, generate, baseline and verify real databases,
reject existing output files, preserve missing SQLite files and retain blocking
issues in review reports. The generator no longer emits invalid empty patch
parameters for models containing only generated fields. Physical import currently
uses the exact supported storage mappings documented in `docs/importing.md`;
NUMERIC is not guessed to contain only integers, and broader native types remain
part of the active goal.

Twenty integer-width checks cover native signed boundaries, nullable/defaulted
columns, exact native 64-bit values, wider aggregate results, mixed-width UNIONs,
relations, transported cursors, generated/imported snapshots and historical
backfills. Reviewed widening/narrowing migrations run on both databases; overflowing
existing rows roll back structure and history together. Physical renames and
identity-width changes preserve generation, including the PostgreSQL sequence
type. SQLite checks distinguish emitted range constraints from quoted defaults,
comments and weaker expressions. Analyzer tests reject invalid or repeated widths
and retain integer-backed domain codec types. The new generated fixture is checked
for deterministic source and snapshot output. `test/support/integers/native.dart`
compiles and runs as a macOS AOT executable, verifying boundaries, wider sums,
relations, overflow rejection and catalog checks. No browser numeric claim is added.

## Still required for the goal

- Advanced-query capability and edge-case review.
- Broader unmanaged-object catalog coverage.
- Named SQL query generation.
- Exact-decimal query semantics and further native type coverage.
- Further backend capability coverage.
- Browser worker/persistence adapter and real browser verification; native Flutter checks.
- User documentation, performance measurements and complete acceptance review.

To-one projections join by default when declared keys prove uniqueness; otherwise
they batch and check cardinality. Collections use explicit parameter-aware batches.
`verifyColumns` checks column names/types/nullability only. `verifySchema` additionally compares defaults,
keys and simple indexes; its `unmanaged` objects require separate review.
Ordinary migration batches are atomic. Explicit backfills use durable per-step
checkpoints and short data transactions on both databases. General recoverable
autocommit SQL remains PostgreSQL-only; SQLite rejects `CheckedSql`. These are
implementation stages, not a reduction of the active goal.

The full suite includes 52 shared SQLite/PostgreSQL query checks, 20 generated
client/migration integration checks, 20 source generation checks, five codec
regressions, 19 migration evolution/catalog checks, 13 recovery checks, three CLI
workflows, 37 streaming/execution checks, 28 relation strategy checks and one
negative compilation suite covering 19 invalid API uses, plus 18 domain-codec
integration checks, 41 subscription checks, eight asset-builder checks and one
build_runner process workflow, plus 32 real-database set-query checks and 24 acquisition checks, plus 41 transaction-control checks, 29 retry checks, 19 application-version checks, 56 backfill checks, 17 catalog-import checks, two import CLI workflows and 20 integer-width checks.

## Environment

Use the standalone SDK if the Flutter launcher tries to update its cache:
`/Users/seven/workspace/flutter/bin/cache/dart-sdk/bin/dart`.
