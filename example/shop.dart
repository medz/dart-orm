import 'package:orm/database.dart';
import 'package:orm/query.dart';

import 'models.dart';
import 'models.db.dart';

typedef CartItem = ({int productId, int quantity});
typedef Receipt = ({Order order, List<OrderLine> lines, bool replayed});
typedef UserWithPosts = ({UserCard user, List<PostCard> posts});

/// Searches active users by username or nickname prefix in one paged SELECT.
/// Only the selected columns cross the connection.
Future<List<UserCard>> searchUsers(AppDatabase db, String prefix) => db.users
    .where(active: eq(true))
    .whereAny(username: startsWith(prefix), nickname: startsWith(prefix))
    .orderBy(id: asc)
    .limit(20)
    .select<UserCard>();

/// Loads both sides in one read-only snapshot, using exactly two SELECTs.
/// An empty root page needs only one SELECT. Relationship batching is explicit.
Future<List<UserWithPosts>> usersWithPosts(AppDatabase db) => db.transaction((
  tx,
) async {
  final users = await tx.users.orderBy(id: asc).limit(20).select<UserCard>();
  if (users.isEmpty) return const <UserWithPosts>[];
  final posts = await tx.posts
      .where(authorId: oneOf(users.map((user) => user.id)))
      .orderBy(id: asc)
      .select<PostCard>();
  final grouped = <int, List<PostCard>>{};
  for (final post in posts) {
    (grouped[post.authorId] ??= []).add(post);
  }
  return List<UserWithPosts>.unmodifiable([
    for (final user in users)
      (
        user: user,
        posts: List<PostCard>.unmodifiable(grouped[user.id] ?? const []),
      ),
  ]);
}, readOnly: true);

/// Creates a complete order atomically; all amounts are integer cents.
///
/// The request key is scoped to the user. Repeating the same normalized cart
/// returns its receipt without debiting stock again. Reusing it for another
/// cart fails. Product IDs are sorted to make concurrent lock order consistent.
/// Each guarded UPDATE returns the price and remaining stock in one statement.
/// A failed item rolls back the order, every line and every stock change.
///
/// Successful work takes 2N + 2 statements, replay takes three. Transaction
/// BEGIN/COMMIT are additional observable boundaries. There is no automatic
/// retry or payment call inside the transaction.
Future<Receipt> checkout(
  AppDatabase db, {
  required int userId,
  required String requestKey,
  required List<CartItem> items,
}) async {
  if (userId < 1 ||
      !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(requestKey) ||
      items.isEmpty ||
      items.length > 50) {
    throw ArgumentError('Invalid user, request key or cart size');
  }
  final quantities = <int, int>{};
  for (final item in items) {
    if (item.productId < 1 || item.quantity < 1 || item.quantity > 99) {
      throw ArgumentError('Each cart item needs a product and quantity 1..99');
    }
    final quantity = (quantities[item.productId] ?? 0) + item.quantity;
    if (quantity > 99) throw ArgumentError('Combined quantity exceeds 99');
    quantities[item.productId] = quantity;
  }
  final ids = quantities.keys.toList()..sort();
  final signature = ids.map((id) => '$id:${quantities[id]}').join(',');
  final scopedKey = '$userId:$requestKey';
  const maxTotalCents = 1000000000000;

  return db.transaction(
    (tx) async {
      final claim = await tx.orders.createIfAbsent(
        .requestKey,
        userId: userId,
        requestKey: scopedKey,
        requestSignature: signature,
        createdAt: DateTime.now().toUtc(),
      );
      if (claim == null) {
        final order =
            (await tx.orders.where(requestKey: eq(scopedKey)).all()).single;
        if (order.userId != userId ||
            order.requestSignature != signature ||
            order.status != 'placed') {
          throw StateError('Request key was used for a different order');
        }
        final lines = await tx.orderLines
            .where(orderId: eq(order.id))
            .orderBy(id: asc)
            .all();
        return (order: order, lines: lines, replayed: true);
      }
      final orderId = claim.id;
      final lines = <OrderLine>[];
      var totalCents = 0;
      for (final id in ids) {
        final quantity = quantities[id]!;
        final product = await tx.products
            .where(stock: gte(quantity))
            .decrement(id, stock: quantity);
        if (product == null) {
          throw StateError('Product $id is missing or sold out');
        }
        if (product.priceCents < 0 || product.priceCents > maxTotalCents) {
          throw StateError('Product price is outside the supported range');
        }
        totalCents += product.priceCents * quantity;
        if (totalCents > maxTotalCents) {
          throw StateError('Order total is too large');
        }
        lines.add(
          await tx.orderLines.create(
            orderId: orderId,
            productId: id,
            quantity: quantity,
            unitPriceCents: product.priceCents,
          ),
        );
      }
      final order = await tx.orders.update(
        orderId,
        status: 'placed',
        totalCents: totalCents,
      );
      if (order == null) {
        throw StateError('Order disappeared inside transaction');
      }
      return (
        order: order,
        lines: List<OrderLine>.unmodifiable(lines),
        replayed: false,
      );
    },
    isolation: db.session.engine == Engine.postgresql
        ? Isolation.readCommitted
        : Isolation.serializable,
  );
}
