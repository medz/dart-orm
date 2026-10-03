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

No implicit retry or external service runs here. If the caller opts into bounded
transaction retry, `placedAt` is sampled again when that attempt executes its
insert plan. Stock arithmetic uses the database's current value at each executed
UPDATE. Rollback reverses database writes, not Dart callback side effects. Plans
and queries captured from a callback expire when that attempt ends.
