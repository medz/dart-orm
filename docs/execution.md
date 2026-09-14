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
transaction deadline. Queued operations check cancellation when they acquire a
connection; immediate removal from the acquisition queue is not implemented.

A token is a sticky request, not proof that a write was rolled back. Always await
the operation's result: a completed statement may win the cancellation race and
return success. Confirmed interruptions report `OPERATION.CANCELLED` or
`OPERATION.TIMEOUT`. Connection loss and uncertain commits remain errors whose
outcome must be checked; the ORM does not automatically retry writes.

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
