@Tags(['sqlite'])
library;

import 'dart:async';
import 'dart:io';

import 'package:orm/driver.dart';
import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
import 'package:test/test.dart';

import '../example/orders/checkout.dart';
import '../example/orders/migrations/migrations.g.dart';
import '../example/orders/models.orm.dart';
import '../example/orders/request.dart';
import 'support/recording_driver.dart';

void main() {
  late Directory directory;
  late Database<Sqlite> db, other;
  late RecordingDriver<Sqlite> primary, competing;
  final events = <QueryEvent>[];
  final immediate = const SqliteTransaction(mode: .immediate);
  Matcher code(String value) =>
      isA<OrmException>().having((e) => e.code, 'code', value);
  OrderRequest request({String key = 'checkout', List<CartItem>? items}) =>
      OrderRequest(
        customerId: 'ada',
        requestKey: key,
        note: ' Reception ',
        items:
            items ??
            [
              CartItem(sku: 'book', quantity: 2),
              CartItem(sku: 'pen', quantity: 3),
            ],
      );
  Future<OrderReceipt> checkout(
    Database<Sqlite> connection,
    OrderRequest input,
  ) =>
      connection.transaction((tx) => placeOrder(tx, input), options: immediate);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('orm-order-test-');
    final options = SqliteOptions.file('${directory.path}/orders.sqlite');
    final first = await sqlite(options);
    primary = RecordingDriver(first.driver);
    db = Database(primary, onQuery: events.add);
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    final second = await sqlite(options);
    competing = RecordingDriver(second.driver);
    other = Database(competing);
    addTearDown(other.close);
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
    events.clear();
    primary.commands.clear();
    competing.commands.clear();
  });

  test('saved migration, atomic checkout and named nested receipt', () async {
    final receipt = await checkout(db, request());
    expect(receipt.totalCents, 1875);
    expect(receipt.note, 'Reception');
    expect(receipt.items.map((i) => (i.sku, i.quantity, i.subtotalCents)), [
      ('book', 2, 1500),
      ('pen', 3, 375),
    ]);
    expect(events.first.sql, 'BEGIN IMMEDIATE');
    expect(events.last.sql, 'COMMIT');
    expect(await db.purchaseOrder.count(), 1);
    expect(await db.orderLine.count(), 2);
    expect((await db.inventory.byId('book').single()).available, 3);
    expect((await db.inventory.byId('pen').single()).available, 7);
    final saved = db.purchaseOrder.byId(receipt.id).select(receiptSelection);
    expect(saved.inspect().sqlTemplateCount, 2);
    events.clear();
    expect((await saved.single()).items.length, 2);
    expect(events.length, 2);
  });

  test(
    'later reservation failure rolls back the header and earlier deduction',
    () async {
      await expectLater(
        checkout(
          db,
          request(
            items: [
              CartItem(sku: 'book', quantity: 2),
              CartItem(sku: 'pen', quantity: 11),
            ],
          ),
        ),
        throwsA(isA<InsufficientStock>().having((e) => e.sku, 'sku', 'pen')),
      );
      expect(events.last.sql, 'ROLLBACK');
      expect(await db.purchaseOrder.count(), 0);
      expect(await db.orderLine.count(), 0);
      expect((await db.inventory.byId('book').single()).available, 5);
      expect((await db.inventory.byId('pen').single()).available, 10);
    },
  );

  test('two real connections compete for stock without overselling', () async {
    final reserved = Completer<void>(),
        release = Completer<void>(),
        submitted = Completer<void>();
    final input = request(items: [CartItem(sku: 'book', quantity: 4)]);
    final winner = db.transaction((tx) async {
      final receipt = await placeOrder(tx, input);
      reserved.complete();
      await release.future;
      return receipt;
    }, options: immediate);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await winner;
    });
    await reserved.future;
    competing.onCommand = (command) {
      if (command.sql == 'BEGIN IMMEDIATE') submitted.complete();
    };
    final loser = expectLater(
      checkout(other, request(key: 'competitor', items: input.items)),
      throwsA(isA<InsufficientStock>()),
    );
    await submitted.future;
    release.complete();
    await winner;
    await loser;
    expect(await db.purchaseOrder.count(), 1);
    expect(await db.orderLine.count(), 1);
    expect((await db.inventory.byId('book').single()).available, 1);
  });

  test(
    'replay preserves the commercial snapshot and rejects changed content',
    () async {
      final receipt = await checkout(db, request());
      await db.inventory.patch(
        available: 0,
        label: 'Changed',
        unitPriceCents: 1,
      );
      primary.commands.clear();
      competing.commands.clear();
      final replay = await checkout(
        other,
        request(
          items: [
            CartItem(sku: 'pen', quantity: 1),
            CartItem(sku: 'book', quantity: 2),
            CartItem(sku: 'pen', quantity: 2),
          ],
        ),
      );
      expect(replay.id, receipt.id);
      expect(replay.placedAt, receipt.placedAt);
      expect(replay.totalCents, receipt.totalCents);
      expect(replay.items.map((i) => i.label), ['Notebook', 'Pen']);
      await expectLater(
        checkout(db, request(items: [CartItem(sku: 'book', quantity: 1)])),
        throwsA(isA<IdempotencyConflict>()),
      );
      expect(await db.purchaseOrder.count(), 1);
      expect(await db.orderLine.count(), 2);
      expect(
        [...primary.commands, ...competing.commands].any(
          (c) =>
              c.sql.startsWith('INSERT') ||
              c.sql.startsWith('UPDATE') ||
              c.sql.startsWith('DELETE'),
        ),
        false,
      );
    },
  );

  test('concurrent duplicate requests commit only one reservation', () async {
    final input = request();
    final receipts = await Future.wait([
      checkout(db, input),
      checkout(other, input),
    ]);
    expect(receipts[0].id, receipts[1].id);
    expect(await db.purchaseOrder.count(), 1);
    expect((await db.inventory.byId('book').single()).available, 3);
  });

  test('real WAL snapshot retry resamples the default and reserves once', () async {
    if (!db.capabilities.cancellation) {
      var entered = false;
      await expectLater(
        () => db.transaction((tx) async {
          entered = true;
        }, retry: const TransactionRetry()),
        throwsA(code('CAPABILITY.CANCEL')),
      );
      expect(entered, false);
      markTestSkipped(
        'This SQLite platform has no bounded retry cancellation support.',
      );
      return;
    }
    var attempts = 0;
    Query<OrderReceipt, PurchaseOrderFields>? expired;
    Write<Inventory, InventoryFields>? expiredWrite;
    final receipt = await db.transaction((tx) async {
      attempts++;
      await tx.inventory.count();
      if (attempts == 1) {
        expired = tx.purchaseOrder.select(receiptSelection);
        expiredWrite = tx.inventory
            .byId('book')
            .plan
            .update(inventoryPatch(available: 999));
        await other.inventory.byId('book').patch(available: 4);
      } else {
        final before = primary.commands.length;
        await expectLater(expired!.get(), throwsA(code('SESSION.CLOSED')));
        await expectLater(
          expiredWrite!.execute(),
          throwsA(code('SESSION.CLOSED')),
        );
        expect(primary.commands.length, before);
      }
      return placeOrder(tx, request());
    }, retry: const TransactionRetry(delay: Duration(milliseconds: 20)));
    expect(attempts, 2);
    final failures = events.where((e) => e.error != null).toList();
    expect(
      failures.single.error,
      isA<SqliteFailure>().having((e) => e.extendedCode, 'extendedCode', 517),
    );
    final inserts = primary.commands
        .where((c) => c.sql.startsWith('INSERT INTO "purchase_orders"'))
        .toList();
    expect(inserts.length, 2);
    final firstTime = _parameter(inserts.first, 'placed_at');
    final committedTime = _parameter(inserts.last, 'placed_at');
    expect(firstTime, isNot(committedTime));
    // The native UTC timestamp codec binds ISO text, decoded by the same model.
    expect(DateTime.parse(committedTime as String), receipt.placedAt);
    expect(
      primary.commands
          .where((c) => c.sql.startsWith('UPDATE "inventory"'))
          .length,
      2,
    );
    expect((await db.inventory.byId('book').single()).available, 2);
    expect(await db.purchaseOrder.count(), 1);
  });

  test(
    'escaped receipt query and stock plan reject after commit without SQL',
    () async {
      late Query<OrderReceipt, PurchaseOrderFields> query;
      late Write<Inventory, InventoryFields> plan;
      await db.transaction((tx) async {
        final receipt = await placeOrder(tx, request());
        query = tx.purchaseOrder.byId(receipt.id).select(receiptSelection);
        plan = tx.inventory
            .byId('book')
            .plan
            .update(inventoryPatch(available: 999));
      }, options: immediate);
      primary.commands.clear();
      await expectLater(query.get(), throwsA(code('SESSION.CLOSED')));
      await expectLater(plan.execute(), throwsA(code('SESSION.CLOSED')));
      expect(primary.commands, isEmpty);
    },
  );
}

Object? _parameter(SqlCommand command, String column) {
  final names = RegExp(r'"([^"]+)"')
      .allMatches(
        command.sql.substring(
          command.sql.indexOf('('),
          command.sql.indexOf(')'),
        ),
      )
      .map((m) => m[1])
      .toList();
  return command.parameters[names.indexOf(column)];
}
