import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';

import 'checkout.dart';
import 'models.orm.dart';

/// One customer's receipts and a cursor for the next page, if it exists.
typedef OrderPage = ({List<OrderReceipt> orders, String? nextCursor});

/// Reads a page inside the caller's snapshot transaction.
///
/// Use a SQLite transaction or PostgreSQL REPEATABLE READ (optionally read-only).
/// A session or PostgreSQL READ COMMITTED does not keep the order headers and
/// separately loaded lines in one snapshot. This function checks transaction
/// ownership; the caller must choose the isolation level.
///
/// The root SELECT includes an independent EXISTS for another page, then one
/// relation SELECT loads only the visible orders' lines. An empty page uses only
/// the root SELECT. Transaction control adds its own statements.
///
/// [pageSize] must be 1..100. The cursor includes placedAt and the unique id;
/// customer filtering is reapplied on every request. Separate page transactions
/// do not share a snapshot: changing ordering keys can cause repeats or omissions.
Future<OrderPage> readOrderHistory(
  Database<Backend> tx, {
  required String customerId,
  String? after,
  int pageSize = 20,
}) async {
  if (!tx.inTransaction) {
    throw StateError('readOrderHistory needs a snapshot transaction.');
  }
  RangeError.checkValueInInterval(pageSize, 1, 100, 'pageSize');

  final query = _historyQuery(tx, customerId, after);
  // A separate table occurrence keeps this subquery independent of each root
  // row. Existence needs N+1 qualifying orders, regardless of their order.
  final hasMore = _historyQuery(tx, customerId, after)
      .orderBy((_) => [])
      .skip(pageSize)
      .take(1)
      .select((o) => o.id)
      .existsExpression();
  final rows = await query
      .take(pageSize)
      .select(
        (o) => (
          receiptSelection(o),
          hasMore,
        ).map((receipt, more) => (receipt: receipt, more: more)),
      )
      .get();
  final orders = rows.map((row) => row.receipt).toList(growable: false);
  return (
    orders: orders,
    nextCursor: rows.isNotEmpty && rows.first.more
        ? tx.purchaseOrder.cursorToken(
            (o) => [
              o.placedAt.cursor(orders.last.placedAt, descending: true),
              o.id.cursor(orders.last.id, descending: true),
            ],
          )
        : null,
  );
}

Query<PurchaseOrder, PurchaseOrderFields> _historyQuery(
  Database<Backend> tx,
  String customerId,
  String? after,
) {
  var query = tx.purchaseOrder
      .where((o) => o.customerId.eq(.value(customerId)))
      .orderBy(_newestFirst);
  if (after != null) query = query.seekToken(after, orderBy: _newestFirst);
  return query;
}

List<OrderTerm> _newestFirst(PurchaseOrderFields o) => [
  o.placedAt.desc(),
  o.id.desc(),
];
