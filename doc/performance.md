# Query performance

Start with the amount of data and work a query requests: selected columns, returned
rows, SQL statements and indexes. Measure on the database and platform your
application uses; the same Dart expression can have different backend costs.

## Select only what you need

A projection selects and decodes only its requested values:

```dart
final people = await db.employee
    .orderBy((e) => [e.id.asc()])
    .take(50)
    .select((e) => (e.id, e.name).row)
    .get();
```

Loading a complete row also transfers and decodes columns your view may never use.
This matters especially for large text, JSON and binary values. `get()` materializes
the result; use pagination or streaming when callers can process bounded chunks.
Keyset pagination needs a deterministic unique tie breaker. See
[queries](https://github.com/medz/dart-orm/blob/main/doc/queries.md) and
[streaming](https://github.com/medz/dart-orm/blob/main/doc/execution.md).

## Count relationship statements

Load related values in the selection rather than making one request per row.
A to-one relation whose keys prove uniqueness can join the root statement.
Collections batch parent keys into child queries; nested collections add loading
stages, and driver parameter limits can split batches.

```dart
final query = db.employee.select((e) => (
  e.name,
  e.manager.select((m) => m.name).one(),
).row);
print(query.inspect().toJson());
```

`inspect()` describes planned SQL without executing it. Use `onQuery` to count
statements actually executed, including child batches. `onAcquire` and `onDecode`
help separate connection waiting and decoding costs. Their scopes do not add up
to every part of application latency; see
[observability](https://github.com/medz/dart-orm/blob/main/doc/observability.md).

## Index for access patterns

Declare indexes for frequently combined filters, joins and ordering:

```dart
indexes: (e) => [
  index((e.departmentId, e.id), name: 'employees_department_id'),
],
```

Primary and unique keys already create database access paths. Relationships do
not automatically add indexes for foreign-key columns. Inspect the database query
plan before adding an index; indexes cost storage and work on every affected write.
Use reviewed migrations to add or change them.

## Keep work bounded

Keep transactions short and avoid waiting for unrelated network requests while
holding a database connection. Batch compatible writes while preserving the
required transaction boundary. Bound result sizes, relation pagination and retry
budgets. A timeout does not prove a submitted write rolled back.

Custom decoders, result mappers and observation callbacks run in Dart. Keep them
small; background database execution does not move application callbacks off the
caller's isolate. Exact decimal operations should be measured with representative
coefficient sizes and scales.

## Compare equivalent workloads

Compare complete results, SQL, bound parameters, statement counts and transaction
boundaries before latency. Record absolute time as well as percentage differences.
A local single-client benchmark does not predict remote, concurrent, browser or
Flutter performance.

Measure on representative data with the same SDK, engine configuration and query
shape. Separate startup from steady-state work, run enough samples to see variation,
and avoid profiling allocations during ordinary latency measurements. Repository
contributors can use the [benchmark tools](https://github.com/medz/dart-orm/blob/main/CONTRIBUTING.md#runtime-benchmarks).
