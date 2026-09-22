# Contributing

Use Dart 3.13 or newer. From a repository checkout:

```sh
dart pub get
dart analyze
dart test
dart run example/main.dart
dart run example/company/main.dart
dart run example/queries.dart
```

The Flutter example is a separate package; run its analysis with the Flutter SDK.
For browser checks, set `CHROME_EXECUTABLE` and run
`dart run tool/test_browser.dart`, then add `--wasm` for the WASM build.

## Real database checks

Set `ORM_TEST_POSTGRES`, `ORM_TEST_MYSQL` and `ORM_TEST_MARIADB` to disposable
database URLs to include those integration suites. Tests create and drop their
own tables; MySQL/MariaDB migration tests also create isolated databases.
Use dedicated test servers and accounts with those privileges.

Server TLS defaults to `verifyFull`. Self-signed local fixtures can explicitly
set `ORM_TEST_MYSQL_TLS=require` and `ORM_TEST_MARIADB_TLS=require`.
Run `dart test` with the default suite concurrency for the complete native matrix.
CI runs `dart test --preset core` once for shared behavior and build/CLI workflows,
and `--preset sqlite`, `postgres`, `mysql` and `mariadb` on separate Linux runners.
Each server job supplies only its own database URL and service. Chrome JS and
WASM have separate jobs. Keep database groups tagged with their engine; leave
shared assertions untagged in mixed files. Entire shared-only suites use `core`,
entire database-only suites use `database` (or their sole engine), and MySQL-family
suites also use `mysql-suite`. These suite tags exclude irrelevant files before
compilation. Presets never lower the runner's default concurrency.

Test command behavior in process with the helpers in `test/support/cli.dart`.
Use absolute fixture paths and capture output with `IOOverrides`; never change
the shared VM's working directory or exit code. Keep subprocesses for generated
consumer compilation, configuration reload, AOT packaging and crash recovery.
Use package entrypoints (`dart run orm` or `dart run orm_build_fixture:migrate`)
when a Dart subprocess is necessary so it can reuse compiled code. Exercise
unchanged generated sources in one consumer instead of compiling each assertion.

## Documentation and public APIs

Keep public entrypoints explicit and add `///` comments at the declarations they
export. Explain result shape, ownership, transaction boundaries and errors where
those affect callers. Internal modules use ordinary imports and exports; do not
introduce `part` directives to share private state.

Handwritten user guides live in `doc/`. Explain supported behavior, practical
examples and compatibility limits. Keep research notes, task progress and test-run
logs out of public guides; report validation in the relevant pull request.
Dartdoc categories connect those guides to API navigation. After changing comments,
exports or category configuration, run:

```sh
dart doc --validate-links
```

After moving or renaming APIs, remove the previous generated `doc/api/` directory
before regenerating so stale pages cannot survive. Broken links, ambiguous
canonical exports and unresolved symbol references fail documentation generation.

Inspect the generated `doc/api/` pages through a local HTTP server, including
library/category navigation, symbol links and public signatures. Do not commit
or publish that generated directory. Run package analysis and the relevant
examples as well; a formatted code block alone does not verify an example.

## Release checks

Check formatting, run `dart doc --validate-links` and run
`dart pub publish --dry-run`. Documentation generation is a release check, not
part of the ordinary test CI. The published package
includes its Dart sources, documentation, examples and SQLite Web assets;
development caches and repository test tools stay out of the archive.

`dart run tool/build_sqlite_web.dart --check` verifies committed worker/WASM
resources. Regenerate them only when their source fingerprint changes.
Report the tested revision, platforms and meaningful skips in the pull request.
Do not use a public guide as a development status log.

## Choose regression suites by behavior

All names below refer to files under `test/` with the `_test.dart` suffix.

| Changed behavior | Representative suites |
| --- | --- |
| Model declarations and generated types | `record_generation`, `record_relations`, `record_database`, `generator`, `generator_dialects`, `types`, `generated_database`, `nominal_database` |
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
databases. See [database setup](#real-database-checks) for environment variables and the
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

For Android, follow the [APK upgrade and restart workflow](https://github.com/medz/dart-orm/blob/main/example/flutter/README.md). Browser,
Android and native server validation are separate: one passing target does not
establish another. Keep SDK, database, browser/device, source revision and report
paths with the validation result. Reports are local outputs under `.dart_tool/`.


## Measure generation and editor cost


From an ORM repository checkout:

```sh
dart run tool/benchmark_generation.dart
dart run tool/benchmark_editor.dart --smoke
dart run tool/benchmark_editor.dart
```

The generation benchmark creates disposable projects with 10, 100 and 1000
four-field Record models. It measures first and unchanged builds, watcher startup,
field and imported-metadata edits, and analysis. It also checks that an unrelated
edit leaves output timestamps unchanged. The report is written to
`.dart_tool/benchmarks/generation.json`; a positional argument chooses another
report path.

The editor benchmark drives the installed Dart Analysis Server over stdio LSP.
It checks completion labels, deliberate type errors with exact diagnostic ranges,
source edits and a final consumer analysis. Full results go to
`.dart_tool/benchmarks/editor.json`. `--smoke` uses ten models and two warm samples,
writing `.dart_tool/benchmarks/editor-smoke.json`; it checks the harness rather
than establishing performance. `--same-session` retains the server across error
recovery and rename probes; its separate report includes `-recovery` in the name.

Generation timing includes process startup where applicable, excludes dependency
downloads, and uses warm shared SDK/pub caches. Editor measurements include protocol
transport and JSON processing, but exclude GUI rendering and editor extensions.
Keep startup, analysis readiness, first completion and warm completion separate.
A successful rename probe does not guarantee every IDE workflow; Record field
renaming depends on the Dart SDK. Always regenerate and analyze after refactoring.

Run these tools independently of other builds with source and SDK versions fixed.
Read sample counts, conditions and errors in the produced report before comparing
results. The build/watch regression suites also exercise imported metadata,
prior-builder output, error recovery and generated-file cleanup.

## Decimal benchmarks

The repository benchmark fetches and decodes 10000 integer-valued Decimal rows,
with one warmup and three measured runs per case. It includes ordinary reads,
division, rounding, average and running aggregates. Build before measuring:

```sh
dart build cli --target=tool/benchmark_decimal.dart --output=/tmp/orm-decimal-benchmark
mkdir -p .dart_tool/benchmarks
/tmp/orm-decimal-benchmark/bundle/bin/benchmark_decimal > .dart_tool/benchmarks/decimal.json
```

Set `ORM_TEST_POSTGRES` to a disposable local PostgreSQL URL to include that
backend. The script disables TLS for this local benchmark, creates a uniquely
named schema and removes it afterward; the account needs schema-creation
permission. Without the variable it measures SQLite only.

These are single-client end-to-end samples, including compilation of each query,
database work, transport and decoding. They are not latency percentiles,
concurrency measurements or estimates for large coefficients and high scales.
Run separately from tests and builds. Retain database/SDK versions and each sample
from the JSON report when comparing revisions.

## Runtime benchmarks

Run the same native SQL and result shapes through the public driver and ORM:

```sh
ORM_TEST_POSTGRES='postgresql://localhost/orm_bench' dart run tool/benchmark_runtime.dart
```

The PostgreSQL account needs permission to create/drop its own temporary schema.
The tool removes that schema and its temporary SQLite WAL file when finished.
It does not alter the application's tables. `--smoke` uses five timing samples
and writes `.dart_tool/benchmarks/runtime-smoke.json`; it validates the harness and is not
a performance result. The normal run writes `.dart_tool/benchmarks/runtime.json`.
Use `--output <path>` to retain separate runs, for example
`--output .dart_tool/benchmarks/runtime-after.json`.

### Comparison contract

Both paths use the **same public Driver**: PostgreSQL pooling/protocol/decoding,
or the native SQLite background isolate and its message transport. The raw path
calls `driver.run` and `connection.execute` directly, then constructs the same
Records/lists using the same public codecs. This isolates the query layer above
the adapter. It is not a comparison against synchronous `package:sqlite3` on the
main isolate or an independently configured `package:postgres` connection.

The raw path reuses captured, precompiled SQL. Its relationship loader derives
keys from the returned parent rows, fills the same parameter positions, groups
children and returns unmodifiable child lists. The fixture has a fixed root/key
count; this baseline is handwritten for that workload, not a general replacement
for the ORM query planner. Raw SQL, parameter values, statement count and complete
business results are checked against the corresponding generated ORM query.
Independent assertions check root count, per-parent ordering/limits and grouped
counts. All data belongs to the generated [example schema](https://github.com/medz/dart-orm/blob/main/example/schema.dart).

| Case | Result | Expected SQL result volume |
| --- | --- | --- |
| `full_rows` | 100 complete user results; nullable, long Unicode nicknames | 100 rows, one statement |
| `two_columns` | 100 `(id, email)` Records | 100 rows, one statement |
| `three_posts` | 100 users with their latest three `(id, title)` posts | 100 parent + 300 child rows, two statements |
| `aggregate` | Counts for ten score groups | 10 rows, one statement |

The database contains 100 users and 1,000 posts. Field selection reduces returned
columns; per-parent pagination returns 300 of those posts. This sample does not
measure arbitrary graph cardinalities, mutation throughput or every codec.

### Timing and transport

Each backend runs in a separate native JIT process. Query objects, schema,
connections and database caches are warm. Query object construction is outside
the timing; ORM SQL compilation on each `get()` is inside it. The default hooks,
VM service and profiler are disabled in the timing processes.

For each case, 20 raw/ORM pairs warm the code before 200 measured pairs. The first
lane alternates in each measured pair. Both lanes retain their actual duration
samples, with nearest-rank p50/p95. In the paired timing section, `wallMicros`
sums measured operation intervals and operations/second is the inverse mean
duration. It excludes the gaps between those intervals. The separate closed-loop
concurrency section runs 200 operations per lane across eight clients, and its
wall time/throughput covers the entire concurrent run. It runs raw then ORM;
repeat measurements to assess order/load/JIT variability.

SQLite uses one worker connection and a temporary WAL file. PostgreSQL warms all
four pool slots. These backend configurations serve different purposes; their
absolute throughputs are not a driver ranking.

Both PostgreSQL timing scenarios use an external loopback TCP relay. One forwards
immediately. The other schedules each received chunk after 10 milliseconds in
each direction, preserving order without serially adding a delay for every chunk.
An independent byte echo measures the relay's actual round-trip latency and checks
its byte accounting. The report also measures `SELECT 1` through the complete
driver. That command can involve multiple protocol round trips: a SQL statement
count is not a TCP round-trip count.

This is controlled transport latency on a local database, not a remote database
deployment. It does not simulate WAN loss, bandwidth limits, TLS or a remote
server's CPU/storage. The relay and its counters run in the controller process,
outside the benchmark process's measured heap.

### Observation and memory scopes

Separate probes preserve SQL/parameters, returned-row counts and UTF-8 JSON byte
lengths of the driver rows and normalized result. These JSON lengths describe
logical payload volume, not native heap sizes or SQLite IPC encoding. PostgreSQL
also records bytes received/sent by its relay during each probe, including
protocol messages but excluding TCP/IP headers. Connection setup is already done.

A separate instrumented eight-client run records 64 acquisition samples per lane
and statement durations. These are driver lease times, including setup inside the
request; they do not isolate the pool implementation's queue time. The ORM probe
also records synchronous decode/grouping times. These probes do not contribute to
the default latency samples.

Memory profiling uses fresh local processes after timing. The external controller
queries the SDK VM service, requests GC, runs three reads retaining the last result,
then inspects live heap state. Reports include heap/external memory, selected live
class counts, RSS before/after and process-lifetime maximum RSS. The latter can
include startup and previous cases; it is not a per-query peak. Live heap statistics
cover the isolate group, including SQLite's worker, and are not solely result size.

The SDK's protocol describes allocation accumulators, but
[Dart 3.13.3's implementation](https://github.com/dart-lang/sdk/blob/3.13.3/runtime/vm/class_table.cc#L263)
emits current counts/sizes for both the accumulated and current fields. This
benchmark therefore does not subtract `accumulatedSize` values or describe a live
heap delta as total allocated bytes. The
[service implementation](https://github.com/dart-lang/sdk/blob/3.13.3/runtime/vm/service.cc#L4443)
also establishes the isolate-group scope of its GC/profile operation.

Instead, a separate
[allocation trace](https://github.com/dart-lang/sdk/blob/3.13.3/runtime/vm/service/service.md#getallocationtraces)
counts observed creations of selected Record, List, Map and selection-plan classes
in the main query isolate, and records allocation frames. It excludes untraced
classes, native allocations and the SQLite worker's allocation traces. Buffer and
stack limits apply; truncated stack counts are retained. These are observed traces,
not an exact census of every allocation or a measurement of total allocated bytes.
Tracing can deoptimize code and changes execution cost; no traced durations are
used as normal throughput results.

### Interpret a comparison

Compare exact SQL, bound parameters, statement counts and complete business
results before comparing durations. A faster run with fewer returned rows or a
different transaction boundary is a different workload.

Use absolute overhead, selected bytes, actual statement counts and measured lease
waits together. A short local query can have a large percentage overhead while
remaining short in absolute time. With network delay, protocol round trips can
dominate; selecting fewer columns does not eliminate those round trips. Allocation
traces can locate intermediate collections, but do not establish retained memory
or application throughput.

Retain the report's runtime revision, SDK, OS/CPU, database versions, fixture,
sample counts and harness hashes. Repeat runs to assess load, scheduling and JIT
variation. If raw-driver timings or calibrated relay latency also change, do not
attribute the entire difference to the ORM. A native JIT result says nothing about
AOT, browser or Flutter performance without a corresponding workload there.

Typed selection decodes values into the requested scalar, Record, DTO or dynamic
Map. Relationship expansion preserves driver-row ownership. Any optimization must
retain mapping order, decoder failures, transaction boundaries, cursor cleanup
and observation events. Statement reuse must also preserve protocol disposal and
connection ownership; omitting cleanup is not a valid cache.
