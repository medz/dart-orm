# Streaming and execution

`get()` materializes a complete result. `stream()` keeps a database cursor open
and fetches the next batch when the consumer requests more rows:

```dart
await for (final user in db.users
    .orderBy((u) => [u.id.asc()])
    .stream(batchSize: 128)) {
  await exportUser(user);
}
```

`await for` pauses while its body awaits. With `listen`, pause/resume the
subscription yourself; an asynchronous `onData` callback does not create demand
control. `toList()` deliberately accumulates the whole stream in the consumer.

The default batch size is 128. SQLite advances a native prepared cursor in its
background isolate. PostgreSQL declares a server cursor and issues bounded
`FETCH` statements. Neither adapter first materializes all root rows in Dart.
The SQL plan can still sort or aggregate before it returns its first row.

Relations are loaded once per root batch on the same connection, including
nested selections and per-parent limits. Memory includes the selected related
rows: use relation `take()` when a parent can have a large collection. Root
batch size alone does not bound that collection.

A stream holds one connection until completion or cancellation. Outside an
explicit transaction it opens a read transaction, committing after normal
exhaustion and rolling back on early exit or failure. PostgreSQL uses a
non-holdable, forward-only cursor. For a consistent snapshot across root and
relationship queries, stream inside a transaction with the required isolation:

```dart
await db.transaction((tx) async {
  await for (final row in tx.users.stream()) {
    await consume(row);
  }
}, options: const PostgresTransaction(
  isolation: Isolation.repeatableRead,
  readOnly: true,
));
```

Finish/cancel subscriptions inside a transaction or leased session callback.
An escaping active stream is stopped and the callback fails with
`TRANSACTION.UNAWAITED` or `SESSION.UNAWAITED`. `Database.close()` also stops
active cursors before releasing its driver. A leased connection executes one
statement at a time; overlapping statements fail with `SESSION.BUSY`.
Concurrent `close()` callers all await the same drain and driver shutdown.

## Connection acquisition

```dart
final options = ExecutionOptions(
  acquireTimeout: const Duration(seconds: 1),
  timeout: const Duration(seconds: 5),
  cancellation: token,
);
final rows = await db.users.select((u) => u.email).get(options: options);

await db.transaction((tx) async {
  await tx.users.create(email: 'within-a-lease@example.com');
}, acquire: const AcquisitionOptions(timeout: Duration(seconds: 2)));

await db.session((session) async {
  // This session already owns its connection.
}, acquire: AcquisitionOptions(
  timeout: const Duration(seconds: 2),
  cancellation: acquisitionToken,
));
```

`ExecutionOptions.acquireTimeout` spans waiting for the driver to supply a
connection, including connection establishment and initialization. It ends before
SQL starts. The same query cancellation token covers both waiting and statement
execution. Stream and watch options propagate this acquisition bound; batch
inserts apply it before opening their transaction. An existing leased session
needs no further acquisition.

`AcquisitionOptions` is the corresponding session/transaction entry setting.
Its cancellation token affects acquisition only: after the callback begins it
does not interrupt that callback or its statements. It is not a transaction
execution deadline. Non-positive timeouts and already-cancelled requests are
rejected before queuing.

A [Dart Future timeout](https://api.dart.dev/dart-async/Future/timeout.html) does
not cancel its source computation. Expired acquisitions report `CONNECTION.TIMEOUT`; requested cancellation reports
`OPERATION.CANCELLED`. The ORM does not merely abandon a Future: a late driver
lease is returned without entering the query, mutation or transaction callback.
A monotonic clock also checks the deadline at entry, so a delayed Dart Timer
cannot allow expired work to start. The underlying pool can retain its reservation
until it grants a lease or fails; the ORM does not pretend that it can remove an
entry from a driver queue that exposes no removal API. `Database.close()` waits
for these reservations to drain. A caller holding a session must still release it.

PostgreSQL has separate driver settings:

| Setting | Default | Scope |
| --- | --- | --- |
| `PostgresOptions.connectTimeout` | 10 seconds | Establishing a new connection |
| `PostgresOptions.poolTimeout` | 30 seconds | Native driver's pool queue waits |
| `PostgresOptions.queryTimeout` | 30 seconds | Each SQL statement |
| `ExecutionOptions.acquireTimeout` | unset | Entire acquisition for this operation |

The per-operation bound can shorten acquisition; it does not enlarge the native
pool limit. Borrowed pools retain their owner's connection and queue settings.
Driver timeouts before callback entry are classified as `CONNECTION.TIMEOUT`;
a `TimeoutException` thrown by application code after entry is preserved.
SQLite's `busyTimeout` controls database lock waits, not its ORM lease queue.
Neither backend's connection settings substitute for a total transaction deadline.

## Cancellation and statement deadlines

```dart
final token = CancellationToken();
final options = ExecutionOptions(
  cancellation: token,
  timeout: const Duration(seconds: 5),
);
final pending = db.users.where((u) => u.email.eq(email)).get(options: options);
// Another event can call token.cancel().
final users = await pending;
```

Options are accepted by query `get/first/single/count/exists/stream`, mutation
`execute`, returning `get/single/first`, `createRow`, batch execution/returning,
and `Database.execute`. They propagate into relation loads and batch chunks.
Generated named `create/patch` shortcuts currently use default execution
options; use the underlying insert/update builder for explicit options.

`timeout` applies to each SQL statement or cursor fetch. It excludes time spent
waiting for a connection and consuming already fetched rows. It is not a total
transaction deadline. Use `acquireTimeout` for the separate acquisition phase.
Cancellation while acquiring a connection now completes promptly and prevents
the SQL callback from ever entering, including when the driver grants a lease
later. Cancellation of an executing statement still awaits database cleanup.

A token is a sticky request, not proof that a write was rolled back. Always await
the operation's result: a completed statement may win the cancellation race and
return success. Confirmed interruptions report `OPERATION.CANCELLED` or
`OPERATION.TIMEOUT`. Connection loss and uncertain commits remain errors whose
outcome must be checked. Writes are retried only inside an explicitly opted-in
transaction, subject to the confirmed-rollback rules below.

SQLite uses `sqlite3_interrupt` from the exact native asset backing the open
database. `capabilities.cancellation` is false if that build does not export the
symbol. Such builds reject cancellation/deadlines instead of merely abandoning
a running future. Native macOS JIT and AOT execution have been verified. Reproduce
the native acceptance check with:

```sh
dart compile exe test/support/native_execution.dart -o /tmp/orm-native-check
/tmp/orm-native-check
```

PostgreSQL opens a separate control connection only when cancellation is
requested and calls `pg_cancel_backend` for the leased backend. It waits for
control cleanup before permitting another statement. This may temporarily use
one connection beyond the pool limit. The control role must be allowed to cancel
the original backend; the default uses the same connection credentials.

The deadline also covers the first backend PID lookup. Cancellation before that
lookup completes discards the connection without sending the application SQL.
Successful lookups are cached for reuse of the same physical connection.

Owned PostgreSQL drivers default to a 30-second statement deadline, configurable
with `PostgresOptions.queryTimeout`. `PostgresDriver.borrow` needs a
`cancellationConnection` factory for cancellation or deadlines, and accepts its
own optional `queryTimeout`. The borrowed pool's statement timeout is not used:
the ORM controls cancellation completion itself. Closing a borrowed ORM driver
does not close the caller's pool.

An interrupted statement marks an explicit transaction failed even if its error
is caught. Cancellation between batch chunks also fails the transaction, so
catching that error cannot commit earlier chunks. Use a savepoint for recoverable work. Cancelling a stream while a
PostgreSQL fetch is executing can abort that transaction; ending a stream between
fetches just closes its cursor.

`onQuery` reports `execute`, `cursorOpen`, `cursorFetch` and `cursorClose` events.
Fetch events include actual batch row counts; they carry the original query SQL
for attribution. Parameters are counted but their values are not recorded.

Optional `onAcquire` and `onDecode` callbacks separately report lease acquisition
and synchronous ORM result processing. See [plans and observations](observability.md)
for their scopes, inheritance and limits, and non-executing `query.inspect()`.


## Transaction deadlines and failure outcomes

```dart
final cancel = CancellationToken();
await db.transaction((tx) async {
  await tx.users.create(email: 'one@example.com');
  await tx.savepoint((child) async {
    await child.users.create(email: 'two@example.com');
  });
},
  acquire: const AcquisitionOptions(timeout: Duration(seconds: 1)),
  timeout: const Duration(seconds: 5),
  cancellation: cancel,
);
```

`transaction(timeout: ...)` starts after acquiring its connection, immediately
before BEGIN. It covers BEGIN, application callback time, all statements and
savepoints, cursor consumption, and COMMIT. It does not restart for each query or
savepoint. A monotonic check prevents new SQL or COMMIT after a CPU-bound callback
has exceeded the deadline even when its Timer could not run promptly. The
transaction cancellation token also cancels acquisition; `acquire.cancellation`
continues to apply only to acquisition.

Expiration rejects new operations, cancels active SQL and cursors, drains pending
work, and rolls back using the underlying connection without the expired token.
The outer Future completes after this cleanup. Cleanup can exceed the requested
duration: stopping a statement, waiting for SQLite's busy handler, and confirming
rollback take time. A driver without actual statement cancellation rejects these
options before starting the transaction.

Dart cannot forcibly stop an arbitrary asynchronous callback or interrupt Dart
code currently monopolizing its isolate. A callback waiting on another Future
may resume later; its expired database view rejects further operations. Its late
errors are observed. External effects performed by callback code are not rolled
back by the ORM. Use transaction/outbox patterns for effects that must follow
committed data.

Successful COMMIT acknowledgement wins a cancellation race. Failure outcomes are
explicit:

| Outcome | Error |
| --- | --- |
| Transaction deadline expires before confirmed commit | `TRANSACTION.TIMEOUT` |
| Transaction cancellation during execution | `TRANSACTION.CANCELLED` |
| Cancellation while still acquiring | `OPERATION.CANCELLED` |
| Shorter statement timeout | `OPERATION.TIMEOUT` |
| Database has already ended the transaction | `TRANSACTION.ENDED` for further calls; the enclosing transaction fails |
| Rollback cannot be confirmed | `TRANSACTION.ROLLBACK`; the connection is discarded |
| COMMIT outcome cannot be established | `TRANSACTION.COMMIT`; never assume callback replay is safe |
| Server explicitly rejects COMMIT | Original classified `SqlFailure`, or the elapsed transaction deadline with that failure as its cause |

PostgreSQL can replace a discarded physical connection from its pool. SQLite
uses one worker connection; discarding it requires reopening the database, and
an in-memory database cannot preserve its contents across that reopen.

`SqlFailure` exposes conservative `retryTransaction`, `retryCommit` and `commitRejected`
classification. Native PostgreSQL errors use `PostgresFailure`, retaining the
SQLSTATE in `code` and the original `package:postgres` exception in `cause`.
SQLite retains `SqliteFailure.code`, `extendedCode` and `message`.

| Database error | Possible transaction retry after confirmed rollback | Known COMMIT rejection |
| --- | --- | --- |
| PostgreSQL `40001` or `40P01` | Yes | Yes |
| PostgreSQL integrity constraints, SQLSTATE class `23` | No | Yes |
| PostgreSQL `40003` | No | No |
| SQLite `BUSY`, including extended busy codes | Yes | Yes |
| SQLite constraint errors | No | Yes |
| Other errors | No automatic eligibility | Conservatively unknown |

These flags do not enable retries by themselves. Without `retry:`, the ORM makes
one attempt, rolls back a rejected transaction and returns its failure.
PostgreSQL serialization failures require repeating the whole transaction logic,
including reads and application decisions.
[PostgreSQL retry guidance](https://www.postgresql.org/docs/current/mvcc-serialization-failure-handling.html)
and the [SQLSTATE catalog](https://www.postgresql.org/docs/current/errcodes-appendix.html)
explain these distinctions.

SQLite reports actual autocommit state from the worker after every completed
request, including errors. If an interrupt or `OR ROLLBACK` has already rolled
back the whole transaction, the ORM skips a redundant ROLLBACK. A vanished
savepoint marks its parent failed and prevents subsequent writes from silently
running in autocommit mode. Healthy SQLite connections remain usable. PostgreSQL's
current Dart driver does not expose transaction status publicly, so its adapter
reports an unknown state and confirms cleanup with ROLLBACK.
[SQLite autocommit status](https://www.sqlite.org/c3ref/get_autocommit.html)
and [transaction error handling](https://www.sqlite.org/lang_transaction.html)
describe why statement errors alone cannot establish SQLite transaction state.


## Explicit bounded retries

```dart
final result = await db.transaction((tx) async {
  final user = await tx.users.byId(userId).single();
  await tx.users.where((u) => u.id.eq(userId))
      .update((u) => [u.nickname.set(user.email)]).execute();
  return user.email;
},
  retry: const TransactionRetry(
    maxAttempts: 3,
    timeout: Duration(seconds: 5),
    delay: Duration(milliseconds: 10),
    maxDelay: Duration(milliseconds: 250),
  ),
);
```

The callback must be safe to repeat after database rollback. Each callback attempt
receives a fresh transaction view and re-executes its reads and decisions. The
previous view closes before another attempt can enter. Application errors,
constraint violations, cancelled statements and caught transaction failures do
not trigger replay. A failed attempt's write notifications are discarded; only a
confirmed commit publishes them. Unknown COMMIT outcomes and unconfirmed rollback
always prohibit replay, even when a retry policy is supplied.

Defaults are three attempts, a 30-second total budget, a 10-millisecond initial
backoff and a 250-millisecond cap. Backoff grows exponentially, with jitter between
approximately half and all of the current delay. Setting `delay: Duration.zero`
disables backoff. The initial attempt consumes one slot; **each callback replay or
commit-only retry consumes one additional slot from the same `maxAttempts`**.
For example, with three slots, one callback replay leaves room for only one
commit-only retry. Attempts are finite even when repeated failures happen quickly.
Exhausting slots returns the final database failure; expiry reports
`TRANSACTION.TIMEOUT`. Cancellation interrupts backoff and reports the transaction
cancellation error without starting another attempt.

SQLite COMMIT returning BUSY is retried in place only if the adapter confirms the
same transaction is still active. The successful callback is not re-entered, so
its in-memory result is retained. A SQLite busy snapshot error during a statement
instead requires confirmed rollback and replay from BEGIN. PostgreSQL serialization
failures and deadlocks also require whole-transaction replay. The current PostgreSQL
adapter never retries COMMIT in place.

`TransactionRetry.timeout` starts at the transaction call and includes acquisition,
all attempts, callback time, SQL and backoff. `transaction(timeout: ...)` still
starts after acquisition and spans all attempts; the shorter remaining budget wins.
A shorter explicit acquisition timeout reports `CONNECTION.TIMEOUT`, as do native
pool/connection failures. An ORM acquisition timer limited by the retry budget
reports `TRANSACTION.TIMEOUT`. These error classes are tied to the source of expiry,
not inferred from timing after the error. Native cancellation support is required.
The cleanup and confirmed-COMMIT rules above also apply to retries.

One connection remains leased for the bounded attempt series, including backoff.
This preserves session state and avoids reacquisition on each retry, but holds a
pool slot while waiting. Keep budgets short under contention. The ORM does not
reconnect and replay after a transport failure, and external callback effects are
not rolled back. This API makes no exactly-once guarantee for such effects.

The real-database retry checks include PostgreSQL serialization/deadlock conflicts,
SQLite WAL snapshot conflicts and DELETE-journal COMMIT lock contention. Additional
driver-injected failures exercise rollback, budgets and lost acknowledgements.
Native SQLite retry acceptance also runs without the JIT/test runner:

```sh
dart compile exe test/support/native_retry.dart -o /tmp/orm-native-retry
/tmp/orm-native-retry
```
