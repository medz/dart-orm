# Orders and inventory

This example uses the unreleased insert-plan conflict API. Run it from a repository
checkout; the complete workflow is in [checkout.dart](checkout.dart).

```sh
dart pub get
dart run bin/orm.dart generate --config example/orders/orm.config.dart
dart run example/orders/main.dart
```

The program creates a temporary SQLite database, applies the reviewed
[saved migration](migrations/m0001_initial.dart), seeds inventory, places an order,
replays the same request and reads its receipt. It closes the database and deletes
the temporary directory on exit. Regeneration changes the derived client and
snapshot; retain saved migration definitions and their fingerprints.

[Models](models.dart) declare stock, an order header with a customer-scoped unique
request key, and order lines. The line's `order` relation declares the inverse
`lines` collection once. [OrderRequest](request.dart) validates and combines cart
quantities, orders SKUs consistently, and stores canonical request content for
idempotency checks. Money uses integer cents; quantities use positive integers.

The caller starts an explicit transaction. `placeOrder` checks for a prior request,
reads catalog prices, passes a typed `PurchaseOrderInsert` to `claimOrder`, deducts
each stock quantity with `WHERE available >= quantity`, inserts the lines, and
returns a named [OrderReceipt](receipts.dart). Conflict suppression is the only
write using `.plan`. All SQL uses the supplied transaction view.

When the driver supports native RETURNING, the claim returns the new order header
directly; only a skipped claim reads the existing header by its request key.
Drivers without RETURNING retain insert-then-read behavior. For the two-item
example, a successful transaction uses 10 statements with RETURNING and 11 without
it, including BEGIN and COMMIT. Both paths keep the same idempotency and rollback
boundaries; RETURNING support is checked through the driver's capabilities.

If any reservation fails, let `InsufficientStock` escape the callback: the header,
earlier deductions and lines roll back together. SQLite callers use
`SqliteTransaction(mode: .immediate)` so competing writers serialize before
reading stock. A lock deadline may still fail and propagates to the caller.
PostgreSQL uses its default READ COMMITTED transaction and the unique constraint
arbitrates concurrent request claims. The example's saved history is SQLite-only;
PostgreSQL needs its own generated and reviewed migration history.

A matching request key and canonical content returns the saved order even when
prices, labels or stock subsequently change. Different content under the same key
throws `IdempotencyConflict`. Lines retain commercial snapshots; the receipt's
ordered line collection loads in two observable statements regardless of line
count. Read a receipt in a transaction when a consistent multi-statement snapshot
is required by the application's concurrent editing policy.

## Customer order history

[history.dart](history.dart) reads a customer's receipts in descending
`placedAt, id` order. Both values travel in the cursor, so orders with identical
timestamps still have a deterministic position. The customer filter is applied
again for every page; a cursor is pagination input, not authorization.

Keep headers and lines in the same snapshot. For the SQLite database in
[main.dart](main.dart), use a deferred transaction:

```dart
final first = await db.transaction(
  (tx) => readOrderHistory(tx, customerId: 'ada', pageSize: 20),
  options: const SqliteTransaction(),
);
if (first.nextCursor case final after?) {
  final next = await db.transaction(
    (tx) => readOrderHistory(tx, customerId: 'ada', after: after, pageSize: 20),
    options: const SqliteTransaction(),
  );
  print(next.orders);
}
```

For a `Database<Postgres>` configured with its own migration history, import
`package:orm/postgres.dart` and use REPEATABLE READ for each page:

```dart
final page = await db.transaction(
  (tx) => readOrderHistory(tx, customerId: 'ada', pageSize: 20),
  options: const PostgresTransaction(
    isolation: .repeatableRead,
    readOnly: true,
  ),
);
```

`readOrderHistory` requires a transaction, but the caller chooses its isolation.
A session alone does not provide a snapshot. PostgreSQL's default READ COMMITTED
also allows another transaction's changes between the header and line SELECTs,
even inside an explicit transaction. SQLite WAL lets a competing writer commit
while this read transaction retains its snapshot; rollback-journal mode instead
can delay that writer's commit. See the engine's
[SQLite isolation](https://www.sqlite.org/isolation.html) and
[PostgreSQL isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
rules.

The root SELECT returns at most `pageSize` headers and an independent `EXISTS`
checks for more matching orders. One batched SELECT loads only those headers'
lines. A nonempty page uses two SELECTs, and an empty page uses one, plus transaction
control. The existence check adds an order-table lookup: fewer returned rows do
not guarantee less execution time. Inspect plans and indexes for your workload.

The calls above start a new snapshot for each page. Deleting the order that supplied the
cursor does not invalidate its saved boundary. Changing `placedAt` between
requests can cause repeats or omissions; this example's checkout keeps ordering
keys unchanged. Concurrently deleted later orders disappear from subsequent
pages. A next cursor describes availability in the current page's snapshot, so
the next request can still return an empty page.

No implicit retry or external service runs here. If the caller opts into bounded
transaction retry, `placedAt` is sampled again when that attempt executes its
insert plan. Stock arithmetic uses the database's current value at each executed
UPDATE. Rollback reverses database writes, not Dart callback side effects. Plans
and queries captured from a callback expire when that attempt ends.
