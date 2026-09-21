# Query plans and execution observations

`query.inspect()` describes the SQL the ORM will request without acquiring a
connection, executing statements or invoking result mappers. It works with the
same query builder used by `get()` and `stream()`:

```dart
final query = db.user.select((u) => (
  u.name,
  u.memberships
    .orderBy((m) => [m.joinedAt.desc(), m.teamId.desc()])
    .take(2)
    .select((m) => m.team.select((t) => t.name).required())
    .many(),
).map((name, teams) => (name: name, teams: teams)));

final plan = query.inspect();
print(plan.sql);
print(plan.loads.single.query!.sql);
print(plan.toJson());
final rows = await query.get();
```

Run `dart run example/teams/main.dart` for a complete generated-schema example.
Inspection compiles SQL on demand; normal execution does not construct this
description. Query compilation and structural errors can surface during inspection.

## What the description contains

Each `QueryPlan` contains one statement and its dependent `RelationLoadPlan`s.
Its immutable lists describe:

- SQL and parameter count, excluding bound parameter values. Literal text in raw
  or named SQL is retained, so this is not a general SQL redaction mechanism.
- Physical output slots, including association keys and joined presence markers.
  `codecType` names the logical codec SQL type, not necessarily the database's
  physical storage type. Expressions without direct column origins omit table
  and column names. Slot indices start at zero.
- Explicit and generated relationship joins, with table/CTE source names and
  left/inner join kind. Joins inside subqueries remain visible in the SQL text.
- Known table reads for this statement, including CTEs and subqueries. Child
  batch reads belong to their own plans. Raw SQL and named SQL set `opaqueReads`
  because the compiler does not parse their dependencies.
- Each batch's parent/child key slots, composite key width, per-parent limit and
  offset, fixed parameter count, and maximum parent keys per chunk.

A child SQL template contains placeholders for **one** parent key tuple. Its
parameter count therefore equals `fixedParameters + keyWidth`. Runtime expands
the key placeholders to match each actual chunk. The capacity is:

```text
maxKeysPerBatch = (driver.maxParameters - fixedParameters) ~/ keyWidth
```

`sqlTemplateCount` counts statement templates in the tree. It is not an execution
count: empty parent results skip child statements, repeated keys share a lookup,
and large key sets require multiple chunks. Composite keys containing NULL do
not join through equality. For one active relationship at one level, child
statement count is `ceil(distinct non-null parent keys / maxKeysPerBatch)`.
Nested loads apply that rule separately to each returned parent batch, and
streaming applies it for each root fetch batch. `take(0)` has a skipped load with
no child SQL. Selected to-one JOINs are already part of their parent's statement.

This description does not estimate database page reads, optimizer choices, row
volume or elapsed time. Native optimizer inspection is a separate operation:
[PostgreSQL EXPLAIN](https://www.postgresql.org/docs/18/sql-explain.html) and
[SQLite EXPLAIN QUERY PLAN](https://www.sqlite.org/eqp.html) consult the database.
PostgreSQL's `ANALYZE` option actually executes the statement. The ORM does not
issue either command automatically.

## Measuring execution phases

```dart
final db = await sqlite(
  const SqliteOptions.memory(),
  onAcquire: (event) => print((event.elapsed, event.reusedConnection, event.error)),
  onQuery: (event) => print((event.operation, event.rowCount, event.elapsed)),
  onDecode: (event) => print((event.inputRows, event.elapsed, event.error)),
);
```

`Database`, `postgres` and `sqlite` accept the same optional hooks.
Sessions, transaction attempts and savepoints inherit them.

| Hook | Measured interval | Limits |
| --- | --- | --- |
| `onAcquire` | Driver lease request until callback entry or acquisition failure | Includes pool wait and setup inside that request. Does not separate those driver internals. Initial SQLite/worker opening occurs before the Database exists and is excluded. |
| `onQuery` | Driver statement or cursor operation until completion/failure | Includes driver conversion and transport, not only server CPU. SQL and parameter count are recorded, bound values are excluded. Cursor fetches report their actual returned row counts. |
| `onDecode` | Synchronous ORM codec/mapping and related-row grouping | Excludes SQL, acquisition, compilation, consumer pauses and other client work. `inputRows` counts rows presented to that decode batch, including on failure. |

An operation within an existing session/transaction reports
`reusedConnection: true` and zero acquisition time. A root query and its collection
loads use one acquisition. Acquisition timeout/cancellation reports a failed
event; returning a later lease does not report a second success or start SQL.
Invalid options and already-cancelled requests fail before acquisition begins.

Each root result, child chunk and nonempty stream fetch has a decode event.
Nested child results are decoded before their parent result. Returning mutations
use their command SQL; batch RETURNING combines command results and reports
`sql: null`. Raw `Database.execute` returns driver rows without ORM decoding.
Empty `get()` results can report zero input rows; an exhausted stream's empty
fetch needs no decode event.

Callbacks are synchronous. Their exceptions are ignored, preserving the actual
operation result and original error. Measurement stops before invoking each
callback, but callback work still delays the caller; keep it small. With hooks
omitted the ORM creates no observation events or measurement Stopwatches.

These intervals are not a complete decomposition of total latency: compilation,
some relation bookkeeping, scheduling and caller work are outside them. Concurrent
operations may interleave events; callbacks do not provide trace correlation IDs.
Neither a successful SQL event nor a decode error alone establishes a transaction's
commit outcome. A result mapper runs in the existing mutation lifecycle and can
fail after an autocommitted write; observation does not move transaction boundaries.

Use [performance measurements](https://github.com/medz/dart-orm/blob/main/doc/performance.md)
to compare end-to-end latency, query volume and allocation costs in your workload.
