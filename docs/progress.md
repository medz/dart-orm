# Implementation status

The active goal is the complete ORM described in `research/new-dart-orm-design.md`.
This file records verified delivery, not planned capabilities presented as working.
The [design acceptance map](acceptance.md) ties remaining gates to the original
requirements and distinguishes direct coverage from missing evidence.

Latest verification: 834 native tests pass in one invocation with PostgreSQL
enabled; analysis reports no issues. Real Chrome JS and Dart WASM each pass 19
scenarios, including temporal column precision and extended date/instant ranges.

Editor verification additionally covers real generated APIs at 10/100/1000 models:
fifteen completion probes with 300 warm samples, twelve diagnostic checks matching
exact codes/source ranges, and language-symbol rename responses. See the
[captured protocol measurements and limits](generation.md#editor-completion-diagnostics-and-rename).

The same-driver runtime cost baseline covers SQLite and PostgreSQL, including
controlled TCP latency, concurrency and separate allocation traces. That baseline
uses runtime source `94d24fe`; see [measurements](performance.md). Selection decoding
has since been optimized, with a separate `d0a8c9a` capture confirming fewer
intermediate List allocations; it does not establish a throughput improvement.

## Completed

- Reset the `next` branch contents, preserving the design research and license.
- Establish one Dart 3.13 package and local-only commit policy.
- Typed scalar expressions, 2–6-field composable projections and dynamic field maps.
- Immutable filters, order, offset/limit, count/exists, basic aggregation and mutations.
- Parameter binding, table occurrence scope checking, explicit default/null changes.
- Native SQLite worker with verified foreign keys, journal mode and parameter limit.
- Browser SQLite worker with explicit memory/OPFS storage, exclusive ownership, verified journaling/foreign keys and shared native codecs/functions.
- Real Chrome acceptance for JavaScript and Dart WASM clients, including persistent reopen, interrupted-transaction recovery and schema upgrades after page reload.
- PostgreSQL driver with a single pool owner, TLS settings and explicit borrowed pools.
- Transaction lifecycle, rollback, savepoints, pending work checks and query observation.
- Non-executing SQL/column/key/join/batch inspection and optional acquisition/SQL/decode phase observations with immutable metadata and isolated observer failures.
- Reproducible same-driver/SQL/result runtime comparisons with latency samples, concurrent throughput, logical/protocol bytes, lease distributions, live heap and separate selected allocation traces.
- Transaction-wide deadlines/cancellation with native SQL interruption, callback expiry and awaited cleanup.
- SQLite actual transaction-state reporting, automatic rollback recovery and invalidated-savepoint protection.
- Conservative server failure classification distinguishing known commit rejection from unknown outcome.
- Opt-in transaction replay and SQLite COMMIT-only retry with shared attempt/time budgets and cancellable backoff.
- Analyzer-based record generator, scalar annotations, composite keys, indexes and FK validation.
- Named SQL files with generated Record parameters/results, dialect-specific methods, native structure checks and stale-output detection.
- Explicit named-query build_runner assets, CLI generation/checking and shared query/transaction/stream/watch execution.
- Generated table accessors, named create parameters, byId, typed patches and schema snapshots.
- Database computed expressions with stored/virtual modes, typed read-only fields, catalog/import metadata and reviewed migrations.
- Batched and nested relation projections, per-parent SQL window pagination, optional/required relations.
- Runnable generated many-to-many membership example with role/time payloads, composite keys, bidirectional queries, transactional writes and measured query/row counts.
- Explicit `relatesTo` query navigation without a database FK, including nonunique/composite/self/inverse edges and unchanged physical snapshots.
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
- Finite exact Decimal values, typed SQL arithmetic, numeric SQLite collation and native PostgreSQL NUMERIC, including keys, relations, aggregates and windows.
- Decimal generation/import, catalog drift checks, reviewed conversion migrations and exact historical backfill keys.
- Declared decimal precision/scale, consistent ORM write coercion, exact SQL precision casts, constrained defaults and width-preserving import/migrations.
- Exact SQL decimal division and six explicit rounding modes, including full finite-range checks and window projections with preserved filtering/grouping/pagination.
- Exact rounded decimal averages with bounded PostgreSQL component sums, incremental SQLite accumulation and shared window inputs.
- LocalDate, LocalTime and LocalDateTime with microsecond precision and full finite native PostgreSQL ranges, independent of DateTime and session timezone.
- Temporal column precision from zero to six digits, matching PostgreSQL rounding in SQLite, with generated writes, explicit value/SQL rounding, default/computed coercion, catalog/import and reviewed precision migrations.
- Calendar generation/import, SQLite indexed collations, normalized relation keys, typed cursors and resumable historical date-key backfills.
- Explicit UTC instant storage, offset-equivalent SQLite indexing, strict process-independent decoding and overflow-checked native PostgreSQL DateTime decoding.
- Reviewed legacy timestamp upgrades preserve captured migration checksums and roll back invalid values or newly equivalent SQLite unique keys.
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

Static analysis is clean. The complete suite passes 740 checks with native SQLite
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
types, nullable primary keys, virtual/shadow tables,
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
Unconstrained NUMERIC now imports as finite Decimal; it is never guessed to contain
only integers. Broader native types remain part of the active goal.

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

Twenty-nine exact-decimal checks cover canonical values, scientific input,
finite range limits, signed rounding and independent integer arithmetic, plus
both databases' typed writes/defaults/patches, comparisons, IN, sorting, distinct
values, transported cursors, computed CTEs, UNIONs and streaming. Exact sums,
nullable aggregates, grouping and windows are verified, including a SQLite moving
frame and intermediate overflow that cancels before a valid final result. A
numeric key lookup retains SQLite index use; this is a query-plan check, not a
throughput benchmark. Equivalent numeric spellings match joined/batched relations
and reject duplicate unique keys. Catalog import/generation, quoted and Unicode
column collations, default equivalence, historical backfill keys and conversion
migration rollback run against actual databases. Unsupported drivers reject typed
decimal SQL before execution. `test/support/decimals/native.dart` compiles and runs
as a macOS AOT executable, verifying exact values, sorting, aggregate/window
functions, normalized relation keys and catalog checks. Invalid external SQLite
text and PostgreSQL special numeric values fail typed decoding; no finite-decimal
CHECK constraint or cross-client SQLite function installation is claimed. Browser
acceptance remains open; constrained columns, SQL division/rounding and averages
are covered by the additional acceptance checks below.

Nineteen precision checks cover signed ties, negative and excess scales, maximum
precision/scale boundaries, nullable values, defaults, expression writes, wider
aggregates, SQL casts, CTEs, batches and upserts. Rounded keys participate in real
foreign-key relationships. Catalogs, snapshots, generated/imported declarations,
renames, default changes and historical backfills retain column constraints.
Scale reduction with duplicate rounded keys rolls back structure and history;
repairing data allows the same migration to resume. SQLite rejects raw values
that do not fit, detects missing default coercion and retains an explicitly
disabled trusted_schema setting. The current SQLite binding requires
trusted_schema ON to evaluate the managed precision CHECK/default functions.
Generator checks reject invalid/repeated annotations and preserve decimal-backed
domain types. The precision fixture compiles and runs as a macOS AOT executable.
Exact SQL averages are covered by the additional acceptance checks below.

Twenty-three division checks compare all signed rounding modes and positive/negative
scales with exact integer arithmetic. They cover 16383 fractional digits, values
around rounding ties, nulls, zero divisors, finite-range overflow and enormous
remainders whose naive intermediate products overflow PostgreSQL NUMERIC. Exact
defaults reject lost digits. Real queries combine division/rounding with grouped
aggregates, windows, HAVING, DISTINCT, ordering, pagination, outer joins, CTEs,
UNIONs, correlated subqueries and per-parent batched relation pagination. Window
expressions retain frame/partition/order identity when referenced through CTEs.
Volatile PostgreSQL operands are evaluated once each; failed expression writes
roll back their transaction. The updated decimal fixture compiles and runs as a
macOS AOT executable, including exact SQL/window division and configurable rounding.
PostgreSQL uses scalar quotient/remainder stages and an additional projection for
window operands; native arithmetic throughput is not implied.
The reproducible decimal benchmark separately records native AOT 10000-row
read/divide/round/window queries on SQLite 3.51.0 and PostgreSQL 18.4. Its raw
report is `research/benchmarks/decimal-division.json`; methodology and medians
are in `docs/decimals.md`. This is a small single-client end-to-end cost probe,
not the complete runtime performance acceptance or a high-precision stress benchmark.

Twenty-three average checks cover exact integer fractions, empty/all-null/constant
inputs, signed ties and every rounding mode, maximum fractional scale and explicit
final-result overflow. Means remain valid when an intermediate total exceeds the
finite NUMERIC range, including cancellation between extreme values. Real queries
cover grouping, HAVING, unique-input CTEs, UNIONs, streaming, partitions, mixed
windows, DISTINCT results, pagination and windows over grouped sums. Correlated
averages update fields; failed exact rounding rolls back the containing transaction.
Per-parent relation windows retain limits. PostgreSQL sequence tests prove one
evaluation per contributing input/order row, including repeated source values;
SQLite moving-frame tests remove values, reset empty frames and reject varying
rounding policies. Illegal aggregate assignments and nested windows fail before
execution. The updated decimal AOT fixture verifies ordinary and running averages.
The expanded native benchmark records 10000-input-row averages and running
averages in `research/benchmarks/decimal-average.json`, together with read/divide/
round controls. It uses the same bounded single-client method and records returned
row counts separately; it does not establish concurrency or large-coefficient cost.

Twenty-four local temporal checks verify Gregorian era/leap boundaries, random
full-range ordinal round trips, finite PostgreSQL endpoints, microseconds and
24:00. Real SQLite/PostgreSQL checks cover generated writes, defaults and null
patches, ordering/min/max/windows/grouping, CTEs, UNION, streams, equivalent
relation keys, unique indexes, cursor transport, imported declarations and
historical date-key backfill recovery. Reviewed text-to-time conversion rejects
equivalent unique keys and rolls back. A reproduced PostgreSQL default comparison
regression now retains expression casts that discard time. Invalid external dates
and infinities fail typed decoding without damaging the connection. Borrowed
PostgreSQL pools explicitly opt into the configured calendar registry; the
unconfigured path rejects temporal queries before execution. A second negative
compilation check rejects five calendar/instant/string mismatches.

`test/support/temporals/native.dart` compiles and runs as a macOS AOT executable,
covering endpoints, calendar order, bounded streams, equivalent relation keys and
catalog/default verification. These checks do not establish browser behavior or
temporal query throughput. Column precision, calendar SQL arithmetic and timezone
conversion are still pending. The local-type checks are distinct from the UTC
instant corrections verified below.

Twenty UTC instant checks reproduce and correct the prior SQLite microsecond
ordering and process-timezone decoding failures. Native SQLite/PostgreSQL tests
cover common DateTime endpoints, microsecond round trips, offset-equivalent
predicates/unique keys/relations, indexed lookups, grouping/windows/CTEs/UNION,
streaming, cursors, imported DateTime declarations, literal defaults and expression
cast drift. Instant-key backfills resume across BC and sub-millisecond boundaries.
Out-of-DateTime PostgreSQL values retain raw text and fail typed decoding without
integer overflow or connection damage.

The captured `test/support/instants/0001_legacy.json` was emitted using commit
`00853b4`. Its original checksum is asserted after decoding with the current
migration reader. Both databases upgrade it through a reviewed timestamp-to-instant
change; SQLite tests prove rollback on equivalent keys and invalid calendar text.
The new instant storage tag leaves old snapshot/DDL meaning unchanged. Native
drivers use one `temporal` capability for local calendar values and UTC instants;
borrowed PostgreSQL pools require the configured registry before opting in.

`test/support/instants/native.dart` passes JIT in a Shanghai-timezone subprocess
and as a compiled macOS AOT executable under UTC, Asia/Shanghai and America/New_York.
It checks UTC defaults, local DateTime input conversion, microsecond sorting and
relations. These checks do not prove browser precision, timezone-name resolution,
column precision policies or temporal throughput.

Twenty-four named SQL checks cover deterministic generation, bound/repeated/nullable
parameters, injection strings, SQL quotes/comments, typed projections, CTEs, UNION,
scalar subqueries, Decimal/calendar/instant codecs, streaming, transaction rollback,
explicit watch dependencies, and native structure failures. Seven additional
invalid API uses fail Dart analysis, including wrong result types and calling a
PostgreSQL-only query on SQLite. The CLI refuses stale generated files and opens
SQLite checks read-only without creating missing database files.

SQLite EXPLAIN and PostgreSQL PREPARE checks do not execute the application SELECT;
throwing expressions and an unchanged PostgreSQL sequence verify that boundary.
PostgreSQL prepared statements are deallocated after storage checks. Result
nullability, value ranges and custom codec semantics remain explicit declarations
with runtime decoding, rather than claimed database inference.

The real build_runner build/watch process also tracks named SQL assets and imported
enum changes, recovers from SQL parameter errors, and removes both query outputs
when their source is deleted. The native named-query fixture compiles and runs as
a macOS AOT executable with SQLite. See
`docs/named-sql.md` for the API and validation limits.

Sixteen browser acceptance scenarios pass in Chrome 153 with a JavaScript client,
and the same sixteen pass with a Dart WASM client. Both use a separately compiled
JavaScript database worker and the pinned sqlite3 3.6.0 WASM asset. They cover
memory migrations/catalogs, FK enforcement, generated records and relations,
rollback/savepoints/transaction lifetime, bounded cursors, watch snapshots, exact
BigInt/Decimal/blob/calendar transport, unsupported interruption, responsive UI
events during a long query, bounded startup failures and exclusive OPFS ownership.
Committed rows survive closing/reopening and an actual page reload while a second
transaction is still open. Reload recovery discards that transaction, passes
integrity_check, and applies the next schema version without losing prior rows.

Browser acceptance reproduced two numeric differences: integral doubles can be
mistaken for unsafe integer parameters, and epoch-microsecond arithmetic loses
precision for remote DateTime values. Explicit SqlReal binding and component-based
instant decoding preserve their intent and precision in both compilation modes.
Floating keyset cursor tokens preserve their value and stable tie breaker.
Checks include BC microseconds and DateTime's upper boundary. Two additional real
native database checks verify SqlReal floating storage on SQLite and PostgreSQL.
The native UTC instant AOT fixture is revalidated after sharing SQLite functions
with the web worker. Captured browser results are in
`research/validation/browser.json`; setup and limitations are in
`docs/sqlite-web.md`. These correctness checks do not measure throughput or certify
Safari, Firefox, Flutter embedding, IndexedDB or a shared multi-tab service.
Statement interruption remains explicitly unsupported by this web driver.
After the floating-cursor correction, all 54 native query/floating-parameter
checks pass again, as do both complete browser runs and static analysis.

The native full suite passes in one invocation with PostgreSQL enabled. macOS runs
test files serially because separate Dart CLI startups can concurrently rewrite
and codesign the shared SQLite native-asset cache before application code starts.
Explicit concurrent database operations inside tests remain enabled. Browser
acceptance commands run separately from the native suite.

Twenty-four unconstrained-relation checks cover real SQLite/PostgreSQL catalogs,
missing/nullable targets, nonunique cardinality, per-parent pagination, self and
inverse navigation, correlated predicates, streaming, transactions and watch
dependencies. The declaration adds no FK, index, uniqueness promise or cascade.
Adding a real FK over dangling data fails and rolls back; repairing rows permits
the same reviewed migration to proceed. Removing it preserves rows and permits
unmatched references again.

Seven generator checks distinguish query navigation from physical constraints
and reject invalid selectors, types, codecs, names and referential actions.
Five additional invalid generated API calls fail static analysis. Existing FK
fixtures remain byte-for-byte deterministic. Browser JS and Dart WASM acceptance
also covers generated query-only relations with single and composite REAL keys.
This reproduced a missing floating binding tag in relationship batches; grouping
now retains comparable storage values and binding restores SQL floating intent.
See `docs/relations.md` for declaration and integrity semantics.
The complete native suite passes all 703 checks in one invocation after these
changes, with PostgreSQL enabled. Both complete browser runs and static analysis
also pass. The design acceptance map records the remaining product gates.

Seventeen CHECK checks cover generated named/unnamed constraints, SQL NULL,
native write failures, import and baseline without replacing rows, duplicate
constraints, drift, casts/precedence, missing/type-changed columns and SQLite
Unicode identifiers. Add/change/remove migrations validate old data and roll back
history on failure; explicit renames preserve incoming references, indexes,
views and SQLite triggers. Unclaimed checks still block SQLite rebuilds.
PostgreSQL unvalidated, NO INHERIT and NOT ENFORCED constraints stay unmanaged;
verification plans but does not execute volatile row expressions.

The generator additionally rejects dynamic/empty CHECK SQL, empty names and
duplicate names. CLI inspection exposes names and expressions. Older snapshots
without checks preserve their JSON/checksum representation. CHECK SQL is trusted,
uses physical names and may have backend overrides; PostgreSQL comparison has
planning cost, and checked SQLite renames may copy a table twice. These boundaries
are documented in `docs/checks.md`.

The complete native suite passes 721 checks in one invocation, with PostgreSQL
enabled, after updating an old integer-test assertion for the newly recognized
CHECK catalog category. Static analysis reports no issues. Real Chrome JS and
Dart WASM runs each pass 15 scenarios, including generated CHECK enforcement,
atomic constraint migration failure/retry and persistent upgrades. The browser
report records both runs; these are correctness checks, not performance results.

Seventeen client-default checks cover real SQLite/PostgreSQL creation, typed
domain IDs, nullable values, DateTime constructors, optional static-method
arguments, generic factories and const function references. Explicit values/null
and database DEFAULT bypass the corresponding factory. Prepared inserts and
batches call each omitted factory once and retain values through compilation,
execution and conflict clauses. Updates do not apply insert defaults; database
rollback does not undo Dart side effects. Explicit DEFAULT on a client-defaulted
identity retains each backend's native sequence behavior.

Generation and moved-output analysis do not execute application factories.
Generator negatives reject incompatible/async scalar results, erased domain
types, required arguments, private/nonconstant references and repeated annotations.
Four invalid generated create calls fail static analysis. Snapshots and imports
contain no client factories; physical defaults and migration checksums remain
separate. Tables without client factories take a direct insertion path, while
other tables cache their default-bearing columns. See `docs/defaults.md`.

The complete native suite passes 740 checks in one invocation with PostgreSQL
enabled, and static analysis reports no issues. Both real Chrome compilation
modes pass 16 scenarios, adding client omission versus explicit null and prepared
batch behavior. The browser schema snapshot itself is unchanged by adding a
client factory. No throughput measurement is claimed by these correctness runs.

Nineteen computed-column checks cover SQLite and PostgreSQL stored/virtual CRUD,
nullable results, batch/conflict returning, generated relationship keys, quoted SQL,
catalog/import roundtrips and drift. Existing rows survive add/drop, expression and
result-type changes, stored-to-ordinary materialization, renamed CHECK expressions,
indexes, incoming references and views. Invalid recomputation rolls back rows,
schema and migration history. Decimal computation retains precision casts through
import and generation. Ten invalid declaration cases and seven invalid generated
API uses fail source/type checks; low-level copy/backfill maps reject computed
targets. CLI inspection returns computation SQL and storage mode.

The implementation uses `ReadField<T>` for computed results and excludes those
fields from generated creation/patch inputs. Native PostgreSQL mode/dependency
limits remain explicit; automatic diff requires reviewed replacement plans for
mode conversions it cannot emit natively. Renamed computed SQLite tables may
require two copies. See `docs/computed.md` for these costs and migration limits.
The complete native suite passes 761 checks in one invocation with PostgreSQL
enabled, and static analysis reports no issues. Real Chrome JS and Dart WASM each
pass 17 scenarios, including computed updates and migration recomputation alongside
the existing OPFS recovery/upgrade scenarios. The captured browser report records
both runs; these do not establish throughput or native Flutter behavior.

Eighteen many-to-many checks exercise the generated `example/teams` schema against
SQLite and PostgreSQL. Memberships carry an enum role and UTC joining time, with
two foreign keys and a composite primary key. Forward/reverse pagination returns
only requested associations; root pagination and empty results remain independent.
Nested team rosters deduplicate shared keys, parameter limits trigger bounded
chunks, and correlated predicates/counts remain in one statement. Tests assert
actual statement counts and fetched-row volume alongside payloads and endpoint
identity. Transactions roll back partial endpoint/association writes; composite-key
conflicts preserve joining times, unlinking preserves endpoints, cascades remove
only affected memberships, and watches track committed payload/endpoint changes.

Six invalid generated API uses fail analysis, covering composite keys, enum
payloads, result shapes and nonexistent implicit graph writes. The new example is
part of deterministic generation checks and runs directly, reporting two SQL
statements returning one root and two association rows. The targeted native
invocation passes 54 checks (many-to-many, generator and types), and static analysis
reports no issues. This stage adds examples and acceptance coverage over the
existing runtime; the last full-suite run remains the 761-check invocation above.
Real Chrome JS and Dart WASM each pass 18 scenarios. Both exercise the same teams
schema, checking association payloads, per-parent limits, two-statement reads,
transaction updates and endpoint cascades. The browser report retains both runs.

Twenty-seven new plan/observation checks pass against real SQLite and PostgreSQL.
Inspection uses existing statement compilers, without acquiring a connection,
decoding fabricated rows or invoking result mappers. It exposes root and one-key
child SQL templates, projection/presence/key slots, joins, read dependencies,
per-parent pagination and composite-key chunk capacity. Template count is distinct
from data-dependent execution count. Bound values are omitted; literal SQL text
is retained. Raw dependencies stay explicitly opaque.

Optional acquisition and decoding hooks propagate into sessions, transactions
and savepoints. Tests cover real pool/lease waiting, timeout/cancellation and
late-lease draining, SQL versus mapper failures, nested row grouping, cursor
batches and returning writes. Observer exceptions preserve commits and original
errors. Hooks omitted means no observation events or measurement Stopwatches;
inspection is only constructed when requested. These phase measurements exclude
some client work and do not isolate server CPU or provide trace correlation IDs.
See `docs/observability.md` for the exact scope and runnable example.

Static analysis passes. The updated teams example executes two SQL statements,
returns one root/two child rows and reports one acquisition/two decode batches.
The full native invocation passes 807 checks with PostgreSQL enabled. Real Chrome
JS and Dart WASM each pass 18 scenarios, including non-executing plan inspection,
one acquisition and child/root decode observations for generated memberships,
alongside OPFS persistence, reload recovery and upgrades. The captured browser
report contains both runs. This establishes behavior, not throughput or allocation
cost; native Flutter and the remaining acceptance gates are still open.

The runtime cost harness completes four workloads on SQLite WAL, local PostgreSQL
and a delayed TCP relay, retaining 200 raw/ORM samples for both paired latency and
eight-client throughput. Probes verify exact SQL/parameters, result shapes and row
volumes; PostgreSQL protocol bytes and SQLite logical JSON byte counts have distinct
labels. Independent echo calibration measured 26.410 ms p50 for the nominal 20 ms
delay. This is a local controlled-latency experiment, not a remote-server deployment.

Separate processes measure live isolate-group heap/RSS and selected main-isolate
allocation traces. The SDK's current `accumulatedSize` implementation reports live
size, so the harness does not misrepresent it as total allocation. Timing processes
have hooks, VM service and profiler disabled. Captured tool hashes, sample counts,
SQL/parameter equality and result volumes were independently read back. Analysis
reports no issues; no runtime source changed in this stage, so the 807-test and
JS/WASM correctness runs above remain the runtime baseline.

The results identify intermediate List construction and PostgreSQL protocol
round trips as concrete optimization candidates. There is no new performance
percentage guarantee or claim of superiority over another ORM; detailed numbers,
scope and reproduction commands are in `docs/performance.md`.

Selection decoding now binds field readers once and passes their results directly
to each typed mapper. Dynamic field maps also avoid an intermediate value list.
Related rows are expanded into fixed-length buffers with one copy, retaining
separate storage from driver rows. Public API, SQL, result shapes and mapping order
remain the existing contract. Six new backend checks cover all two-to-six-field
arities, repeated columns, deferred/ordered evaluation, streaming, first-error
propagation and dynamic field snapshots/nulls. The focused selection, relation,
observation, inspection and UNION invocation passes 93 checks. The full native
invocation passes 813 checks with PostgreSQL enabled, and analysis reports no
issues. Real Chrome JS and Dart WASM each pass 18 scenarios; the teams scenario
additionally checks a six-field mixed-type projection and deferred/ordered mapping.
The browser report retains both runs. The separate `runtime-selection.json` cost
capture preserves the original baseline, retaining 200 timing/concurrency samples
per lane and 64 acquisition samples. All twelve scenario/case combinations retain
identical SQL, parameters, row volumes and logical/protocol bytes. Three SQLite
relationship reads reduce selected List/backing-List traces from 8,244 to 5,220;
local PostgreSQL reduces them from 17,564 to 14,541. Normal latency and throughput
do not establish a speed improvement: some timings increased alongside raw-driver
controls, and relay calibration changed between runs. The report records those
limits rather than attributing timing changes to decoding.

PostgreSQL protocol lifecycle review confirms separate awaited prepare/dispose
work and pending portal cleanup in the pinned driver's Statement implementation.
Caching statements while retaining the current bind path cannot just omit
disposal; cancellation, portal release and connection reuse must stay valid.
The current adapter deliberately retains its verified cleanup behavior. The
measured round-trip cost and scope are documented in `docs/performance.md`.

Temporal precision now spans declarations, generated/manual columns, immutable
snapshots, SQL assignments and value/expression operations. Default and explicit
six-digit declarations retain the prior canonical snapshot and migration checksum.
SQLite uses managed coercion/functions and CHECKs; PostgreSQL uses native type
modifiers. Runtime rounding uses day-local microseconds to preserve extended dates
on JS without overflowing a total timestamp count. Tests cover all seven precisions
around the PostgreSQL epoch, BC dates, extended timestamp/instant limits, nullable
values, defaults/computed columns, CTE/grouping/streams, batch/upsert and rounded
relation keys. Import roundtrips preserve metadata and avoid duplicate wrappers.
Reviewed narrowing and rename can detect merged unique keys, rolling back schema,
data and history before a successful retry.

The new 21-check suite and the 17-check catalog import suite pass together. The
full native invocation then passes 834 checks with PostgreSQL enabled. Static
analysis passes. Real JS and WASM each pass 19 browser scenarios, including the
new precision worker scenario and existing persistence/reload upgrades. The
captured browser report includes both runs; no native Flutter claim is added.

## Editor protocol capture

`tool/benchmark_editor.dart` launches the installed Dart 3.13.3 Analysis Server in
isolated consumer packages against runtime `7eaab3b`. The checked report is
`research/benchmarks/editor.json`; it retains harness hashes, every warm sample,
startup/readiness costs, diagnostic ranges and applied rename edits. Independent
readback checks all hashes, nearest-rank quantiles, current error ranges and rename
edit counts. Final consumer analysis passes at all three scales. Root static
analysis also passes; runtime sources are unchanged from the 834-native-check and
19-per-browser-scenario capture above.

At 1000 models, warm table-entry completion is 11.572 / 17.094 ms p50 / p95;
query-field completion is 0.780 / 0.850 ms. Initial project readiness is 3.405 s,
and the query-field probe has a separate 128.488 ms opening/diagnostic wait. These
are stdio protocol observations with twenty warm samples per probe, not complete
GUI latency or a declaration-frontend comparison.

Record field rename returns null. Primary-constructor and table fields update
their declaration and typed reference; typedef rename updates the alias and its
two references. Rename probes run in a separate clean server: same-session class
field rename after diagnostic recovery stalled during harness development and
is not proven reliable here. A valid Dart arithmetic index selector passes CLI
analysis but the generator rejects it with a source offset, demonstrating the
boundary between Dart and ORM-specific rules. This closes the measured LSP slice,
not the full three-authoring-frontend experiment or whole-product goal.

## Declaration-form comparison

`tool/compare_authoring.dart` now executes the design's User/Post/Profile/Follow
experiment using actual Record, primary-constructor and typed table declarations.
Experimental adapters resolve each input, preserve field metadata and map it to a
common Record schema before using the unchanged production generator. The base,
field-type edit and physical-name-preserving field rename each produce identical
canonical source, generated client and physical snapshot across the three forms.
Four composite FKs, compound keys/uniqueness, identity/default/nullability, index
order and CHECK contents are verified independently from the report.

All forms compile the same generated create/patch and nested relation consumer.
The six stale-consumer checks fail after type edits/renames and pass after their
references/types are repaired. Fourteen negative cases locate Dart, generator or
adapter errors in original source; constructor logic and custom table codecs are
rejected instead of silently lost. Class/table schema rename updates the field and
typed constraint reference through real LSP edits. Record field rename is manual.

The captured model declarations occupy 487 / 585 / 1,574 bytes and 24 / 24 / 43
formatted lines respectively. These are fixture observations, not a universal
Record superiority claim. Stage timings have fixed-order JIT/cache bias and are
not a frontend speed comparison. The [report and interpretation](authoring.md)
preserve the distinction between schema-only adapters and nominal runtime rows.
Root static analysis passes. Runtime sources remain unchanged; this work does not
claim additional database or native Flutter validation.

## Still required for the goal

- Advanced-query capability and edge-case review.
- Broader unmanaged-object catalog coverage.
- Further native type coverage.
- Timezone conversions and remaining temporal operations.
- Further backend capability coverage.
- Native Flutter checks and remaining platform acceptance review.
- User documentation, performance measurements and complete acceptance review.

To-one projections join by default when declared keys prove uniqueness; otherwise
they batch and check cardinality. Collections use explicit parameter-aware batches.
`verifyColumns` checks column names/types/nullability, integer widths, decimal precision/scale, SQLite collations and computed expressions/modes. `verifySchema` additionally compares defaults,
keys, row CHECK constraints and simple indexes; its `unmanaged` objects require separate review.
Ordinary migration batches are atomic. Explicit backfills use durable per-step
checkpoints and short data transactions on both databases. General recoverable
autocommit SQL remains PostgreSQL-only; SQLite rejects `CheckedSql`. These are
implementation stages, not a reduction of the active goal.

The full suite includes 52 shared SQLite/PostgreSQL query checks, 20 generated
client/migration integration checks, 29 source generation checks, five codec
regressions, 19 migration evolution/catalog checks, 13 recovery checks, three CLI
workflows, 37 streaming/execution checks, 28 relation strategy checks and three
negative compilation checks covering 29 invalid API uses, plus 18 domain-codec
integration checks, 41 subscription checks, eight asset-builder checks and one
build_runner process workflow, plus 32 real-database set-query checks and 24 acquisition checks, plus 41 transaction-control checks, 29 retry checks, 19 application-version checks, 56 backfill checks, 17 catalog-import checks, two import CLI workflows, 20 integer-width checks, 29 exact-decimal checks, 19 decimal-precision checks, 23 decimal-division checks and 23 decimal-average checks, plus 24 local temporal checks, 20 UTC instant checks, 24 named SQL checks, two explicit floating-parameter checks, 24 unconstrained-relation checks 17 CHECK-constraint checks and 17 client-default checks.

Nineteen computed-column checks and additional generation/type checks are included
in the current aggregate above.

## Environment

Use the standalone SDK if the Flutter launcher tries to update its cache:
`/Users/seven/workspace/flutter/bin/cache/dart-sdk/bin/dart`.

On 2026-09-15 the installed Flutter cache reports 3.47.4 stable with Dart 3.13.3.
Xcode reports 27.0 (27A266a), but `xcodebuild -license check` exits 69 and explicitly
reports that its license has not been accepted. Native Flutter verification needs
the user's own license review/acceptance and any remaining Xcode initialization.
No license was accepted on the user's behalf; other development can continue.

The host also contains Android Studio, an Android SDK with API 35/36/36.1 platforms
and an installed API 35 arm64 emulator image. Android provides another candidate
for native Flutter verification without relying on Xcode. Existence checks alone
do not prove emulator startup, a Flutter build, or application behavior.
