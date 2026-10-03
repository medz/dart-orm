@Tags(['database'])
library;

import 'dart:io';

import 'package:orm/driver.dart';
import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/orders/checkout.dart';
import '../example/orders/history.dart';
import '../example/orders/migrations/migrations.g.dart';
import '../example/orders/models.orm.dart';
import '../example/orders/request.dart';
import 'support/recording_driver.dart';

void main() {
  for (final dialect in [SqlDialect.sqlite, SqlDialect.postgres]) {
    group(
      dialect.name,
      () => historyTests(dialect),
      tags: [dialect.name],
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES to run real PostgreSQL.'
          : false,
    );
  }
}

void historyTests(SqlDialect dialect) {
  late Database<Backend> db, other;
  late RecordingDriver<Backend> primary;
  final events = <QueryEvent>[];
  final acquisitions = <AcquisitionEvent>[];
  final orderIds = <int>[];

  Future<OrderReceipt> checkout(
    String customer,
    String key, {
    bool large = false,
  }) => db.transaction(
    (tx) => placeOrder(
      tx,
      OrderRequest(
        customerId: customer,
        requestKey: key,
        items: [
          for (var i = 0; i < (large ? 100 : 1); i++)
            CartItem(sku: 'sku-${i.toString().padLeft(3, '0')}', quantity: 1),
        ],
      ),
    ),
    options: dialect == SqlDialect.sqlite
        ? const SqliteTransaction(mode: .immediate)
        : const PostgresTransaction(),
  );

  setUp(() async {
    if (dialect == SqlDialect.sqlite) {
      final dir = await Directory.systemTemp.createTemp('orm-history-');
      addTearDown(() => dir.delete(recursive: true));
      final options = SqliteOptions.file('${dir.path}/orders.sqlite');
      primary = RecordingDriver((await sqlite(options)).driver);
      other = Database.fromSql(await sqlite(options));
    } else {
      final url = Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!);
      final namespace =
          'orm_history_${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final admin = Database.fromSql(
        postgres(PostgresOptions(url: url, tls: .disable)),
      );
      addTearDown(admin.close);
      await admin.execute(SqlCommand('CREATE SCHEMA "$namespace"'));
      addTearDown(
        () => admin.execute(SqlCommand('DROP SCHEMA "$namespace" CASCADE')),
      );
      final options = PostgresOptions(
        url: url,
        tls: .disable,
        schema: namespace,
        maxConnections: 1,
      );
      primary = RecordingDriver(postgres(options).driver);
      other = Database.fromSql(postgres(options));
    }
    db = Database(primary, onQuery: events.add, onAcquire: acquisitions.add);
    addTearDown(db.close);
    addTearDown(other.close);
    await Migrator(db.sql).apply(
      dialect == SqlDialect.sqlite
          ? migrationHistory.checked
          : [
              Migration.create(
                '0001_orders_postgres',
                appSchema,
                dialect: .postgres,
              ),
            ],
    );
    await db.inventory.insertMany([
      for (var i = 0; i < 100; i++)
        inventoryInsert(
          sku: 'sku-${i.toString().padLeft(3, '0')}',
          label: 'Item $i',
          available: 10,
          unitPriceCents: 100,
        ),
    ]);
    orderIds.clear();
    orderIds.add((await checkout('ada', 'oldest')).id);
    await checkout('grace', 'another-customer');
    orderIds.add((await checkout('ada', 'large', large: true)).id);
    orderIds.add((await checkout('ada', 'small-1')).id);
    orderIds.add((await checkout('ada', 'small-2')).id);
    // Equal timestamps require the id tie breaker on every page.
    await db.purchaseOrder.patch(placedAt: DateTime.utc(2026, 10, 1));
    events.clear();
    acquisitions.clear();
    primary.commands.clear();
  });

  final TransactionOptions<Backend> snapshot = dialect == SqlDialect.sqlite
      ? const SqliteTransaction()
      : const PostgresTransaction(isolation: .repeatableRead, readOnly: true);

  Future<OrderPage> page({
    String customer = 'ada',
    String? after,
    int size = 2,
  }) => db.transaction(
    (tx) => readOrderHistory(
      tx,
      customerId: customer,
      after: after,
      pageSize: size,
    ),
    options: snapshot,
  );

  test(
    'requires an explicit transaction and a bounded positive page size',
    () async {
      await expectLater(
        readOrderHistory(db, customerId: 'ada'),
        throwsStateError,
      );
      await expectLater(
        db.session((s) => readOrderHistory(s, customerId: 'ada')),
        throwsStateError,
      );
      expect(events, isEmpty);
      for (final size in [0, 101]) {
        await expectLater(page(size: size), throwsRangeError);
      }
      expect(events.where((e) => e.sql.startsWith('SELECT')), isEmpty);
    },
  );

  test(
    'two SELECTs load only visible receipts, with one connection lease',
    () async {
      final result = await page();
      expect(result.orders.map((o) => o.id), orderIds.reversed.take(2));
      expect(result.orders.map((o) => o.items.length), [1, 1]);
      expect(result.nextCursor, isNotNull);
      final reads = events.where((e) => e.sql.startsWith('SELECT')).toList();
      expect(reads.map((e) => e.rowCount), [2, 2]);
      expect(reads.first.sql, contains('EXISTS (SELECT'));
      expect(
        events.first.sql,
        dialect == SqlDialect.sqlite
            ? 'BEGIN DEFERRED'
            : 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY',
      );
      expect(events.last.sql, 'COMMIT');
      expect(acquisitions.where((e) => !e.reusedConnection), hasLength(1));
      expect(acquisitions.every((e) => e.error == null), true);
    },
  );

  test(
    'tied dates, a new order and a deleted boundary preserve the next page',
    () async {
      final first = await page();
      final newer = await checkout('ada', 'arrived-between-pages');
      await other.purchaseOrder.byId(first.orders.last.id).delete();
      final second = await page(after: first.nextCursor);
      expect(second.orders.map((o) => o.id), [orderIds[1], orderIds[0]]);
      expect(second.orders.every((o) => o.customerId == 'ada'), true);
      expect(second.orders.every((o) => o.id != newer.id), true);
      expect(second.orders.map((o) => o.items.length), [100, 1]);
      expect(second.nextCursor, isNull);
    },
  );

  test(
    'one-row pages traverse all matching receipts without duplicates',
    () async {
      final ids = <int>[];
      String? after;
      for (var i = 0; i < orderIds.length; i++) {
        final result = await page(after: after, size: 1);
        ids.add(result.orders.single.id);
        after = result.nextCursor;
        expect(after == null, i == orderIds.length - 1);
      }
      expect(ids, orderIds.reversed);
    },
  );

  test(
    'a cursor from another customer does not replace the customer filter',
    () async {
      final first = await page();
      final grace = await page(customer: 'grace', after: first.nextCursor);
      expect(grace.orders, hasLength(1));
      expect(grace.orders.single.customerId, 'grace');
      expect(grace.nextCursor, isNull);
    },
  );

  test('exactly full, underfull and empty pages have no next cursor', () async {
    for (final size in [4, 5]) {
      final result = await page(size: size);
      expect(result.orders.map((o) => o.id), orderIds.reversed);
      expect(result.nextCursor, isNull);
    }
    events.clear();
    final empty = await page(customer: 'nobody');
    expect(empty.orders, isEmpty);
    expect(empty.nextCursor, isNull);
    expect(
      events.where((e) => e.sql.startsWith('SELECT')).map((e) => e.rowCount),
      [0],
    );
  });

  test(
    'a later page has a new snapshot; moving a seen sort key can repeat it',
    () async {
      final first = await page();
      await other.purchaseOrder
          .byId(first.orders.first.id)
          .patch(placedAt: DateTime.utc(2026, 9, 1));
      final second = await page(after: first.nextCursor, size: 4);
      expect(second.orders.map((o) => o.id), [
        orderIds[1],
        orderIds[0],
        first.orders.first.id,
      ]);
      expect(second.nextCursor, isNull);
    },
  );

  // Pause the real connection after its root SELECT, before relation loading.
  // The other connection must finish its commit before this read can continue.
  void beforeLines(Future<void> Function() mutate) {
    var reads = 0;
    primary.beforeCommand = (command) async {
      if (command.sql.startsWith('SELECT') && ++reads == 2) {
        primary.beforeCommand = null;
        await mutate();
      }
    };
  }

  for (final consistent in [true, if (dialect == SqlDialect.postgres) false]) {
    final mode = consistent ? 'snapshot' : 'READ COMMITTED counterexample';
    Future<OrderPage> read() => db.transaction(
      (tx) => readOrderHistory(tx, customerId: 'ada', pageSize: 2),
      options: consistent
          ? snapshot
          : const PostgresTransaction(readOnly: true),
    );

    test(
      '$mode: concurrent deletion between header and line SELECTs',
      () async {
        final deleted = orderIds[2];
        beforeLines(() async {
          expect(await other.purchaseOrder.byId(deleted).delete(), 1);
        });
        final result = await read();
        expect(result.orders.map((o) => o.id), [orderIds[3], deleted]);
        expect(result.orders.map((o) => o.items.length), [
          1,
          consistent ? 1 : 0,
        ]);
        expect(await other.purchaseOrder.byId(deleted).exists(), false);
      },
    );

    test(
      '$mode: concurrent header and line changes stay together only in a snapshot',
      () async {
        final changed = orderIds[2];
        final oldTime = DateTime.utc(2026, 10, 1);
        final newTime = DateTime.utc(2026, 10, 2);
        beforeLines(
          () => other.transaction((tx) async {
            await tx.purchaseOrder
                .byId(changed)
                .patch(placedAt: newTime, note: 'amended');
            await tx.orderLine
                .where((l) => l.orderId.eq(.value(changed)))
                .patch(label: 'amended');
          }),
        );
        final result = await read();
        final order = result.orders.singleWhere((o) => o.id == changed);
        expect(result.orders.map((o) => o.id), [orderIds[3], changed]);
        expect(order.placedAt, oldTime);
        expect(order.note, isNull);
        expect(order.items.single.label, consistent ? 'Item 0' : 'amended');
        expect(
          (await other.purchaseOrder.byId(changed).single()).placedAt,
          newTime,
        );
      },
    );
  }
}
