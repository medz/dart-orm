import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';

import 'checkout.dart';
import 'history.dart';
import 'migrations/migrations.g.dart';
import 'models.orm.dart';
import 'request.dart';

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('orm-orders-');
  try {
    final events = <QueryEvent>[];
    final db = Database.fromSql(
      await sqlite(
        SqliteOptions.file('${directory.path}/orders.sqlite'),
        onQuery: events.add,
      ),
    );
    try {
      await Migrator(db.sql).apply(migrationHistory.checked);
      await db.inventory.insertMany([
        inventoryInsert(
          sku: 'book',
          label: 'Notebook',
          available: 5,
          unitPriceCents: 750,
        ),
        inventoryInsert(
          sku: 'pen',
          label: 'Pen',
          available: 10,
          unitPriceCents: 125,
        ),
      ]);
      final request = OrderRequest(
        customerId: 'ada',
        requestKey: 'checkout-1',
        note: ' Leave at reception ',
        items: [
          CartItem(sku: 'book', quantity: 2),
          CartItem(sku: 'pen', quantity: 3),
        ],
      );
      events.clear();
      final receipt = await db.transaction(
        (tx) => placeOrder(tx, request),
        options: const SqliteTransaction(mode: .immediate),
      );
      print(
        'Order ${receipt.id}: ${receipt.totalCents} cents, ${receipt.items.length} lines',
      );
      print(
        'Transaction: ${events.first.sql} … ${events.last.sql}; ${events.length} statements',
      );
      final replay = await db.transaction(
        (tx) => placeOrder(tx, request),
        options: const SqliteTransaction(mode: .immediate),
      );
      if (replay.id != receipt.id) {
        throw StateError('Replay created a second order.');
      }
      events.clear();
      await readReceipt(db, receipt.id);
      print(
        'Replay: order ${replay.id}; saved receipt: ${events.length} statements',
      );
      events.clear();
      final history = await db.transaction(
        (tx) => readOrderHistory(tx, customerId: 'ada', pageSize: 10),
        options: const SqliteTransaction(),
      );
      print(
        'History: ${history.orders.length} orders; '
        'next page: ${history.nextCursor != null}; '
        '${events.length} statements including BEGIN and COMMIT',
      );
      for (final item
          in await db.inventory.orderBy((i) => [i.sku.asc()]).get()) {
        print('${item.sku}: ${item.available} remaining');
      }
    } finally {
      await db.close();
    }
  } finally {
    await directory.delete(recursive: true);
  }
}
