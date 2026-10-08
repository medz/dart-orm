import 'dart:typed_data';

import 'package:orm/schema.dart';

/// One immutable application row; its table identity is explicitly declared.
@Table('users')
final class const User({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Unique() required final String username,
  required final int age,
  final String? nickname,
  @Column(defaultValue: true) required final bool active,
  @Column(defaultValue: 0.0) required final double score,
  @Column(name: 'joined_at') final DateTime? joinedAt,
  final Uint8List? avatar,
});

/// SQL projection registered before runtime.
@SelectFrom(User)
typedef UserCard = ({int id, String username});

/// Nullable fields retain their exact nullability in selections.
@SelectFrom(User)
typedef UserProfile = ({int id, String? nickname, bool active});

@Table('posts')
final class const Post({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Column(name: 'author_id')
  @References('users', onDelete: 'cascade')
  required final int authorId,
  required final String title,
  final String? body,
});

@SelectFrom(Post)
typedef PostCard = ({int id, int authorId, String title});

@Table('products')
final class const Product({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Unique() required final String sku,
  required final String name,
  @Column(name: 'price_cents') required final int priceCents,
  @Column(defaultValue: 0) required final int stock,
});

@SelectFrom(Product)
typedef ProductCard = ({int id, String name, int priceCents});

@Table('orders')
final class const Order({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Column(name: 'user_id') @References('users') required final int userId,
  @Unique() @Column(name: 'request_key') required final String requestKey,
  @Column(name: 'request_signature') required final String requestSignature,
  @Column(name: 'total_cents', defaultValue: 0) required final int totalCents,
  @Column(defaultValue: 'building') required final String status,
  @Column(name: 'created_at') required final DateTime createdAt,
});

@Table('order_lines')
final class const OrderLine({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Column(name: 'order_id')
  @References('orders', onDelete: 'cascade')
  required final int orderId,
  @Column(name: 'product_id')
  @References('products')
  required final int productId,
  required final int quantity,
  @Column(name: 'unit_price_cents') required final int unitPriceCents,
});
