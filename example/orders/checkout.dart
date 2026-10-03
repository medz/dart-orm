import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';

import 'models.orm.dart';
import 'request.dart';

/// Places or replays one order inside the caller's explicit transaction.
///
/// The caller chooses engine settings and any bounded retry policy. Every SQL
/// operation uses [tx]; a stock or request-content error escapes to roll back
/// the order, previous reservations and all lines. No external effects run here.
Future<OrderReceipt> placeOrder(
  Database<Backend> tx,
  OrderRequest request,
) async {
  if (!tx.inTransaction) {
    throw StateError('placeOrder needs the transaction callback view.');
  }
  final existing = await _requestOrder(tx, request).singleOrNull();
  if (existing != null) return _replay(tx, request, existing);

  final stock = await tx.inventory
      .where((i) => i.sku.isIn(request.items.map((item) => item.sku)))
      .get();
  final bySku = {for (final item in stock) item.sku: item};
  var total = 0;
  for (final item in request.items) {
    final catalog = bySku[item.sku];
    if (catalog == null) throw InsufficientStock(item.sku);
    total += item.quantity * catalog.unitPriceCents;
  }

  final input = purchaseOrderInsert(
    customerId: request.customerId,
    requestKey: request.requestKey,
    requestPayload: request.payload,
    totalCents: total,
    note: request.note,
  );
  final order = await claimOrder(tx, request, input);
  if (order == null) {
    return _replay(tx, request, await _requestOrder(tx, request).single());
  }

  for (final item in request.items) {
    final reserved = await tx.inventory
        .byId(item.sku)
        .where((i) => i.available.gte(.value(item.quantity)))
        .update(
          inventoryPatch.values(
            available: .expression((i) => i.available.minus(item.quantity)),
          ),
        );
    if (reserved != 1) throw InsufficientStock(item.sku);
  }
  await tx.orderLine.insertMany([
    for (final item in request.items)
      orderLineInsert(
        orderId: order.id,
        sku: item.sku,
        label: bySku[item.sku]!.label,
        quantity: item.quantity,
        unitPriceCents: bySku[item.sku]!.unitPriceCents,
      ),
  ]);
  return readReceipt(tx, order.id);
}

/// The unique request key arbitrates concurrent duplicates on SQLite/PostgreSQL.
///
/// Conflict handling is the one advanced write needed by this workflow. The
/// insert plan samples client defaults at execution, once per callback attempt.
/// Returns the newly inserted order, or null if the request key already exists.
/// Without native RETURNING, reads a successful insert by [request]'s key. The
/// caller constructs [input] from that same request before crossing this boundary.
Future<PurchaseOrder?> claimOrder(
  Database<Backend> tx,
  OrderRequest request,
  PurchaseOrderInsert input,
) async {
  final write = tx.purchaseOrder.plan
      .insert(input)
      .onConflictDoNothing(target: (o) => [o.customerId, o.requestKey]);
  if (tx.capabilities.returning) return write.returning().singleOrNull();
  if (await write.execute() == 0) return null;
  return _requestOrder(tx, request).single();
}

ModelQuery<PurchaseOrder, PurchaseOrderFields, PurchaseOrderPatch>
_requestOrder(Database<Backend> tx, OrderRequest request) =>
    tx.purchaseOrder.where(
      (o) => allOf([
        o.customerId.eq(.value(request.customerId)),
        o.requestKey.eq(.value(request.requestKey)),
      ]),
    );

Future<OrderReceipt> _replay(
  Database<Backend> tx,
  OrderRequest request,
  PurchaseOrder order,
) {
  if (order.requestPayload != request.payload) {
    throw IdempotencyConflict(request.requestKey);
  }
  return readReceipt(tx, order.id);
}

/// Reads the saved commercial snapshot, never the current catalog price/label.
/// The root and ordered line collection use two observable statements.
Future<OrderReceipt> readReceipt(Database<Backend> db, int id) =>
    db.purchaseOrder.byId(id).select(receiptSelection).single();

Selection<OrderReceipt> receiptSelection(PurchaseOrderFields o) => orderReceipt(
  id: o.id,
  customerId: o.customerId,
  requestKey: o.requestKey,
  totalCents: o.totalCents,
  note: o.note,
  placedAt: o.placedAt,
  items: o.lines
      .orderBy((line) => [line.sku.asc()])
      .select(
        (line) => orderItem(
          sku: line.sku,
          label: line.label,
          quantity: line.quantity,
          unitPriceCents: line.unitPriceCents,
        ),
      )
      .many(),
);
