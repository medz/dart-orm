# Runtime cost measurements

Run the same native SQL and result shapes through the public driver and ORM:

```sh
ORM_TEST_POSTGRES='postgresql://localhost/orm_bench' dart run tool/benchmark_runtime.dart
```

The PostgreSQL account needs permission to create/drop its own temporary schema.
The tool removes that schema and its temporary SQLite WAL file when finished.
It does not alter the application's tables. `--smoke` uses five timing samples
and writes `.dart_tool/runtime-smoke.json`; it validates the harness and is not
a performance result. The normal run records
[`research/benchmarks/runtime.json`](../research/benchmarks/runtime.json).
Use `--output <path>` to retain a subsequent measurement separately from that
baseline, for example `--output research/benchmarks/runtime-selection.json`.

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
counts. All data belongs to the generated [example schema](../example/schema.dart).

| Case | Result | Expected SQL result volume |
| --- | --- | --- |
| `full_rows` | 100 complete User Records; nullable, long Unicode nicknames | 100 rows, one statement |
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

## Interpretation

Captured on 2026-09-15 with an Apple M3 Max, Dart 3.13.3, SQLite 3.53.4 and
PostgreSQL 18.4. Runtime source is `94d24fe`. Durations below are milliseconds;
throughput is operations/second for the separate eight-client run.

| Environment | Case | Raw p50 | ORM p50 | ORM p95 | ORM concurrent ops/s |
| --- | --- | ---: | ---: | ---: | ---: |
| SQLite WAL | full rows | 0.111 | 0.160 | 0.242 | 6,919 |
| SQLite WAL | two columns | 0.055 | 0.075 | 0.127 | 14,159 |
| SQLite WAL | three posts | 0.728 | 0.817 | 0.915 | 1,238 |
| SQLite WAL | aggregate | 0.036 | 0.040 | 0.049 | 24,564 |
| PostgreSQL loopback | full rows | 0.931 | 0.994 | 1.126 | 1,838 |
| PostgreSQL loopback | two columns | 0.530 | 0.555 | 0.849 | 2,817 |
| PostgreSQL loopback | three posts | 1.778 | 1.960 | 2.383 | 725 |
| PostgreSQL loopback | aggregate | 0.352 | 0.365 | 0.406 | 5,956 |
| PostgreSQL delayed relay | full rows | 82.706 | 83.526 | 86.316 | 46 |
| PostgreSQL delayed relay | two columns | 82.083 | 81.652 | 85.104 | 47 |
| PostgreSQL delayed relay | three posts | 166.178 | 168.265 | 173.045 | 23 |
| PostgreSQL delayed relay | aggregate | 80.660 | 80.563 | 83.713 | 49 |

The delayed relay's actual echo RTT p50 was **26.410 ms**, despite the nominal
20 ms delay; timers and scheduling add overhead. Full-driver `SELECT 1` p50 was
82.678 ms. Loopback echo p50 was 0.188 ms. Small reversals where ORM appears faster
under the delayed relay are not evidence of an ORM speedup.

For PostgreSQL, selecting two columns instead of complete users reduced received
protocol bytes from **27,784 to 4,693** in the probe. Batched relationships returned
100 parent and 300 child rows in two SQL statements. The ORM's separate eight-client
relation probe measured acquisition p50 of 5.530 ms for SQLite, 5.212 ms for local
PostgreSQL and 180.287 ms with the delayed relay. Pool saturation and network costs
matter more than a single idle-connection probe suggests.

Across three SQLite relationship reads, selected traces recorded **996 raw versus
8,244 ORM List/backing-List allocations** (`_List` plus `_GrowableList`). These are
main-isolate traces with tracing enabled, not all-process allocated bytes. They
identify intermediate collection construction for follow-up review. The measured
local ORM p50 overhead in that case was 0.089 ms. A future optimization should
re-run this harness and preserve exact SQL, results, transaction behavior and
observer semantics before claiming improvement.

The captured report identifies runtime source commit, SDK/OS/CPU, database versions,
fixture, sample counts and harness hashes. It is one machine/run, without confidence
intervals or a cross-library comparison. It does not establish AOT, browser or Flutter
performance. Correctness checks for those platforms have separate evidence.

Use absolute overhead, selected bytes, actual statement counts and measured lease
waits together. A small local query can have a large percentage overhead while
remaining short in absolute time. On a delayed connection, protocol round trips
can dominate; fewer selected columns do not eliminate those round trips. Allocation
traces identify work worth investigating but do not by themselves justify a cache
or a new abstraction.

## Direct selection decoding

The separate [selection report](../research/benchmarks/runtime-selection.json)
captures runtime `d0a8c9a` on the same machine, SDK and database versions. Field
readers now pass values directly to typed mappers or the requested dynamic Map,
avoiding a temporary values List for each row. Relationship expansion allocates
one fixed-length buffer and copies the original row into it. This preserves
driver-row ownership and adds no cache or dependency.

The workload, relay and VM-profiling helper hashes match the baseline. The main
harness only adds output-path selection, allowing both reports to be retained.
Each of the twelve scenario/case combinations has 200 latency and concurrent
samples per lane and 64 separate acquisition samples. Independent report readback
confirms identical SQL, parameters, statement/row counts and logical/protocol
bytes between raw/ORM and before/after. Temporary PostgreSQL schemas were removed.

The selected main-isolate List traces over **three reads** are:

| Backend | Case | Raw before → after | ORM before → after | ORM reduction |
| --- | --- | ---: | ---: | ---: |
| SQLite WAL | full rows | 39 → 40 | 1,239 → 333 | 73.1% |
| SQLite WAL | two columns | 37 → 37 | 885 → 282 | 68.1% |
| SQLite WAL | three posts | 996 → 996 | 8,244 → 5,220 | 36.7% |
| SQLite WAL | aggregate | 29 → 29 | 371 → 308 | 17.0% |
| PostgreSQL loopback | full rows | 3,386 → 3,382 | 4,598 → 3,695 | 19.6% |
| PostgreSQL loopback | two columns | 2,359 → 2,359 | 3,215 → 2,611 | 18.8% |
| PostgreSQL loopback | three posts | 10,235 → 10,248 | 17,564 → 14,541 | 17.2% |
| PostgreSQL loopback | aggregate | 451 → 451 | 803 → 740 | 7.8% |

Counts sum `_List` and `_GrowableList`, including backing arrays. All captured
traces report zero truncated stacks; the selected-class and isolate limitations
above still apply. These percentages describe observed List creations, not total
allocated bytes, retained heap, RSS or throughput.

Normal untraced local latency did **not** establish a speed improvement. Several
raw-driver timings increased too. All local cases are shown in milliseconds:

| Backend | Case | Raw p50 before → after | ORM p50 before → after | New ORM p95 |
| --- | --- | ---: | ---: | ---: |
| SQLite WAL | full rows | 0.111 → 0.127 | 0.160 → 0.170 | 0.267 |
| SQLite WAL | two columns | 0.055 → 0.057 | 0.075 → 0.075 | 0.164 |
| SQLite WAL | three posts | 0.728 → 0.806 | 0.817 → 0.907 | 1.099 |
| SQLite WAL | aggregate | 0.036 → 0.036 | 0.040 → 0.041 | 0.053 |
| PostgreSQL loopback | full rows | 0.931 → 0.907 | 0.994 → 0.979 | 1.189 |
| PostgreSQL loopback | two columns | 0.530 → 0.553 | 0.555 → 0.593 | 0.827 |
| PostgreSQL loopback | three posts | 1.778 → 1.909 | 1.960 → 2.154 | 2.498 |
| PostgreSQL loopback | aggregate | 0.352 → 0.353 | 0.365 → 0.375 | 0.510 |

Local ORM eight-client throughput was also lower in this capture; all durations
and throughput samples are retained in the report. Two separate captures cannot
distinguish small runtime regressions from load, scheduling and JIT variability.
The supported conclusion is fewer intermediate List allocations, with unchanged
SQL/result volume and verified correctness, not a latency or throughput gain.

The delayed relay's echo p50 changed from 26.410 to 24.725 ms and full-driver
`SELECT 1` from 82.678 to 75.129 ms. Relationship raw/ORM p50 changed from
166.178/168.265 to 162.096/162.396 ms. Transport calibration itself changed, so
those lower durations cannot be attributed to selection decoding.

The [PostgreSQL adapter](../lib/postgres.dart) still prepares each statement,
consumes its bound ResultStream and awaits disposal. Inspection of the locked
`postgres` 3.5.12 implementation shows separate awaited parse and close messages;
`_PreparedStatement` also queues transaction portals for cleanup in `run()` or
`dispose()`. Retaining statements while continuing to use `bind()` would retain
that pending cleanup until disposal. Simply removing disposal is therefore not
a valid optimization. The adapter currently owns cancellation and awaits control
cleanup before allowing reuse. A future connection-scoped statement cache or
protocol change must preserve these lifecycle guarantees and be evaluated with
the delayed-relay harness. No implicit statement cache is introduced here.

Correctness after this change: 813 native tests with PostgreSQL enabled, clean
static analysis, and 18 real Chrome scenarios for each of JS and Dart WASM. The
browser membership scenario additionally covers six mixed field types and
deferred, ordered mapping. These remain separate from performance evidence and
do not establish native Flutter behavior.
