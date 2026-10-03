@Tags(['postgres'])
library;

import 'dart:async';
import 'dart:io';

import 'package:orm/driver.dart';
import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sql.dart';
import 'package:test/test.dart';

import '../example/orders/checkout.dart';
import '../example/orders/models.orm.dart';
import '../example/orders/request.dart';
import 'support/recording_driver.dart';

void main() {
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  group(
    'order inventory on PostgreSQL',
    () {
      late Database<Postgres> db, other;
      late RecordingDriver<Postgres> primary, competing;
      final events = <QueryEvent>[];
      OrderRequest request(String key, {int quantity = 4}) => OrderRequest(
        customerId: 'ada',
        requestKey: key,
        items: [CartItem(sku: 'book', quantity: quantity)],
      );
      Future<OrderReceipt> checkout(
        Database<Postgres> connection,
        OrderRequest input,
      ) => connection.transaction((tx) => placeOrder(tx, input));

      // Both transactions have read the absent key and the same catalog snapshot
      // before either insert reaches PostgreSQL. No driver result is simulated.
      void synchronizeClaims() {
        final ready = Completer<void>();
        var waiting = 0;
        Future<void> before(SqlCommand command) async {
          if (!command.sql.startsWith('INSERT INTO "purchase_orders"')) return;
          if (++waiting == 2) ready.complete();
          await ready.future.timeout(const Duration(seconds: 10));
        }

        primary.beforeCommand = before;
        competing.beforeCommand = before;
      }

      setUp(() async {
        final namespace =
            'orm_orders_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        final admin = Database.fromSql(
          postgres(PostgresOptions(url: Uri.parse(url!), tls: .disable)),
        );
        addTearDown(admin.close);
        await admin.execute(SqlCommand('CREATE SCHEMA "$namespace"'));
        addTearDown(
          () => admin.execute(SqlCommand('DROP SCHEMA "$namespace" CASCADE')),
        );
        final options = PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          schema: namespace,
          maxConnections: 1,
        );
        primary = RecordingDriver(postgres(options).driver);
        competing = RecordingDriver(postgres(options).driver);
        db = Database(primary, onQuery: events.add);
        other = Database(competing);
        addTearDown(db.close);
        addTearDown(other.close);
        // A separate PostgreSQL history: never apply the saved SQLite migration.
        // These unqualified fixture models use this test's isolated search path.
        await Migrator(db.sql).apply([
          Migration.create(
            '0001_orders_postgres',
            appSchema,
            dialect: .postgres,
          ),
        ]);
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

      test('read committed stock competitors cannot oversell', () async {
        synchronizeClaims();
        Future<Object> result(Database<Postgres> connection, String key) async {
          try {
            return await checkout(connection, request(key));
          } on InsufficientStock catch (error) {
            return error;
          }
        }

        final results = await Future.wait([
          result(db, 'first'),
          result(other, 'second'),
        ]);
        expect(results.whereType<OrderReceipt>(), hasLength(1));
        expect(results.whereType<InsufficientStock>(), hasLength(1));
        expect((await db.inventory.byId('book').single()).available, 1);
        expect(await db.purchaseOrder.count(), 1);
        expect(await db.orderLine.count(), 1);
      });

      test('unique claim arbitrates concurrent duplicates, then replays saved prices', () async {
        synchronizeClaims();
        final input = request('same-key');
        final receipts = await Future.wait([
          checkout(db, input),
          checkout(other, input),
        ]);
        expect(receipts[0].id, receipts[1].id);
        expect(receipts[0].placedAt, receipts[1].placedAt);
        expect((await db.inventory.byId('book').single()).available, 1);
        final claims = [...primary.commands, ...competing.commands]
            .where((c) => c.sql.startsWith('INSERT INTO "purchase_orders"'))
            .toList();
        expect(claims, hasLength(2));
        expect(
          claims.every(
            (c) => c.sql.contains(
              'ON CONFLICT ("customer_id", "request_key") DO NOTHING',
            ),
          ),
          true,
        );
        await db.inventory.patch(
          available: 0,
          label: 'Changed',
          unitPriceCents: 1,
        );
        final replay = await checkout(db, input);
        expect(replay.totalCents, 3000);
        expect(replay.items.single.label, 'Notebook');
        await expectLater(
          checkout(db, request('same-key', quantity: 1)),
          throwsA(isA<IdempotencyConflict>()),
        );
        expect(await db.purchaseOrder.count(), 1);
        events.clear();
        expect((await readReceipt(db, replay.id)).items, hasLength(1));
        expect(events, hasLength(2));
      });

      test(
        'later stock failure rolls back previous updates and header',
        () async {
          await expectLater(
            checkout(
              db,
              OrderRequest(
                customerId: 'ada',
                requestKey: 'insufficient',
                items: [
                  CartItem(sku: 'book', quantity: 4),
                  CartItem(sku: 'pen', quantity: 11),
                ],
              ),
            ),
            throwsA(isA<InsufficientStock>()),
          );
          expect(events.last.sql, 'ROLLBACK');
          expect((await db.inventory.byId('book').single()).available, 5);
          expect(await db.purchaseOrder.count(), 0);
          expect(await db.orderLine.count(), 0);
        },
      );

      test(
        'conflict plan RETURNING yields the inserted model or no row',
        () async {
          final input = purchaseOrderInsert(
            customerId: 'ada',
            requestKey: 'claim',
            requestPayload: '{}',
            totalCents: 0,
          );
          final write = db.purchaseOrder.plan
              .insert(input)
              .onConflictDoNothing(target: (o) => [o.customerId, o.requestKey]);
          final PurchaseOrder? inserted = await write
              .returning()
              .singleOrNull();
          expect(inserted?.customerId, 'ada');
          expect(await write.returning().singleOrNull(), isNull);
          expect(await db.purchaseOrder.count(), 1);
        },
      );
    },
    skip: url == null
        ? 'Set ORM_TEST_POSTGRES for real PostgreSQL order tests.'
        : false,
  );
}
