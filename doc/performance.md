# Runtime cost measurements

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

## Comparison contract

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

## Timing and transport

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

## Observation and memory scopes

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

## Interpret a comparison

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

See [observability](https://github.com/medz/dart-orm/blob/main/doc/observability.md) for the event timing scopes and
[acceptance](https://github.com/medz/dart-orm/blob/main/doc/acceptance.md) for correctness checks that accompany performance work.
