import 'package:orm/migration.dart';
import 'package:orm/query.dart';
import 'package:orm/sqlite.dart';

import 'migrations/sqlite/history.dart' as migrations;
import 'models.db.dart';
import 'shop.dart';

Future<void> main() async {
  final db = AppDatabase(SqliteDriver.memory());
  try {
    await MigrationRunner(db.database, migrations.history).apply();
    final seeded = await db.transaction((tx) async {
      final user = await tx.users.create(username: 'seven', age: 28);
      await tx.posts.create(authorId: user.id, title: 'Hello Dart ORM');
      final product = await tx.products.create(
        sku: 'dart-book',
        name: 'Dart book',
        priceCents: 4900,
        stock: 10,
      );
      return (user: user, product: product);
    });

    await db.users.update(seeded.user.id, nickname: 'Seven');
    await db.users.update(seeded.user.id, nickname: null);
    final page = await searchUsers(db, 'sev');
    print('${page.users.first.username}: ${page.total} matching users');
    final related = await usersWithPosts(db);
    print('${related.first.user.username}: ${related.first.posts.first.title}');

    final items = [(productId: seeded.product.id, quantity: 2)];
    final receipt = await checkout(
      db,
      userId: seeded.user.id,
      requestKey: 'first-order',
      items: items,
    );
    final replay = await checkout(
      db,
      userId: seeded.user.id,
      requestKey: 'first-order',
      items: items,
    );
    print('Order ${receipt.order.id}: ${receipt.order.totalCents} cents');
    print('Replay: ${replay.replayed}');

    await db.transaction((tx) async {
      await for (final row
          in tx.users.where(active: eq(true)).stream(fetchSize: 100)) {
        print(row.username);
      }
    }, readOnly: true);
  } finally {
    await db.close();
  }
}
