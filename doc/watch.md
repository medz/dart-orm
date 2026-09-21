# Query subscriptions

`watch()` emits an initial query result, then re-runs the query after relevant
committed writes:

```dart
final subscription = db.user
    .orderBy((u) => [u.id.asc()])
    .select((u) => u.email)
    .watch()
    .listen(
      (emails) => print(emails), // List<String>
      onError: (Object error) => print(error),
    );

await db.user.create(email: 'seven@example.com');
await subscription.cancel();
```

Each stream has one subscriber and starts work only when listened to. Create a
separate `watch()` for another subscriber. Each subscription executes its own
query; there is no global result cache, object identity map or polling timer.
Each refresh uses normal `query.get()` semantics, including relationship batches.
Bound snapshot size with filters and `take`; use `query.stream()` for incremental
row consumption through a database cursor.

## Commit behavior

Typed insert, update, delete, upsert and batch operations record affected tables.
Zero-row writes and `ON CONFLICT DO NOTHING` with no inserted rows do not refresh
queries. Raw operations can explicitly declare effects as described below.

```dart
await db.transaction((tx) async {
  await tx.user.create(email: 'a@example.com');
  await tx.user.create(email: 'b@example.com');
}); // One combined invalidation after COMMIT succeeds.
```

A rolled-back transaction produces no invalidation. Released savepoints merge
their changes into the enclosing transaction; rolled-back savepoints discard
their changes. A batch's chunks follow the same transaction boundary. SQL and
constraint failures do not publish successful-write notifications.

If COMMIT's acknowledgement is lost, its outcome may be unknown. The transaction
still throws `TRANSACTION.COMMIT`, and subscriptions conservatively re-read its
affected tables. A refreshed result is not evidence that retrying the mutation is
safe.

Subscriptions observe invalidation and current data, not an audit log of every
intermediate state. Several commits may coalesce while a read is running or a
subscription is paused. Results are not compared for equality automatically;
an affected-table write may emit an unchanged projection. Consumers can apply
`distinct` with their own equality function if required.

## Which queries refresh

The compiler tracks physical sources used by root queries, explicit and automatic
JOINs, subqueries, CTEs, relation predicates and nested batch-loaded relations.
An unrelated table write does not execute another read.

Generated clients register their schema metadata. Declared foreign-key delete
effects then propagate through `CASCADE` chains; `SET NULL` invalidates the child
without treating that child as deleted. Ordinary updates do not trigger a
delete cascade. For hand-authored tables, register the full relevant schema:

```dart
db.registerSchema([usersSchema, postsSchema]);
```

Read dependencies are captured before the first read starts. An invalidation
arriving during a read marks that result stale; the subscription re-reads before
emitting it. Only one read runs per subscription at a time. Normal query and
relation loading semantics still apply; subscriptions do not add a stronger
cross-statement transaction isolation guarantee.

## Raw SQL, triggers and external writers

Table names hidden inside raw SQL cannot be discovered from a typed expression.
Add those dependencies explicitly:

```dart
final postCount = sql<int>(
  ['(SELECT COUNT(*) FROM posts)'], [], Codecs.integer,
);
final counts = db.user.select((_) => postCount).watch(reads: [postsSchema]);
```

Raw commands can declare tables they affect:

```dart
await db.execute(
  SqlCommand('DELETE FROM posts'),
  changedTables: [postsSchema],
);
```

`changedTables` requests an invalidation after a successful command even when its
reported row count is zero. It follows the current transaction/savepoint boundary
and conservatively includes declared delete effects. It is explicit metadata;
the ORM does not parse arbitrary SQL to infer writes.

For triggers, procedures or already-committed external work, notify explicitly:

```dart
db.invalidate([postsSchema]);
```

Inside a transaction, `tx.invalidate(...)` waits for that transaction's commit.
Supply all tables affected by unmodeled triggers or procedures. Independent
SQLite connections, PostgreSQL pools and other processes do not automatically
notify each other. Integrate an external notification, polling or CDC mechanism
and call `invalidate` after observing the external commit. Separate database
views using the **same driver instance** share notifications.

## Pause, cancellation and errors

- Pausing a subscription prevents additional reads. Writes set one dirty flag;
  resuming performs a fresh read. A read already in progress may finish, but its
  result is discarded if the subscriber is paused, avoiding a growing result queue.
- Cancelling the subscription stops future reads and interrupts active SQL when
  the driver supports cancellation. Await cancellation to wait for the active read
  and its connection cleanup. A driver without cancellation must finish its read.
- `ExecutionOptions.timeout` limits each SQL statement, including relation
  batches. It is not a lifetime limit for the subscription.
- An optional cancellation token cancels the subscription with
  `OPERATION.CANCELLED` and closes it. Explicit subscription cancellation is silent.
- Query/decoding failures emit errors. A later invalidation can retry; errors do
  not create a polling or automatic retry loop. Invalid subscription/query
  definitions detected before the first read are terminal.
- `Database.close()` stops its driver's subscriptions and waits for active reads.
  A paused listener cannot prevent database shutdown; it observes stream completion
  when resumed or cancelled.

Watch a root database query. Transaction and leased-session queries reject
subscription with `WATCH.SESSION`: those views expire when their callback returns.
Also avoid awaiting an outside subscription from code holding the only available
connection; its next read must wait for that lease to be released.
