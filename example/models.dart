import 'dart:typed_data';

import 'package:orm/schema.dart';

/// One immutable application row; its table identity is explicitly declared.
@Table('users')
final class User {
  const User({
    required this.id,
    required this.username,
    required this.age,
    this.nickname,
    required this.active,
    required this.score,
    this.joinedAt,
    this.avatar,
  });
  @PrimaryKey(autoIncrement: true)
  final int id;
  @Unique()
  final String username;
  final int age;
  final String? nickname;
  @Column(defaultValue: true)
  final bool active;
  @Column(defaultValue: 0.0)
  final double score;
  @Column(name: 'joined_at')
  final DateTime? joinedAt;
  final Uint8List? avatar;
}

/// SQL projection registered before runtime.
@SelectFrom(User)
typedef UserCard = ({int id, String username});

/// Nullable fields retain their exact nullability in selections.
@SelectFrom(User)
typedef UserProfile = ({int id, String? nickname, bool active});

@Table('posts')
final class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.title,
    this.body,
  });
  @PrimaryKey(autoIncrement: true)
  final int id;
  @Column(name: 'author_id')
  @References('users', onDelete: 'cascade')
  final int authorId;
  final String title;
  final String? body;
}

@SelectFrom(Post)
typedef PostCard = ({int id, int authorId, String title});

@Table('products')
final class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.priceCents,
    required this.stock,
  });
  @PrimaryKey(autoIncrement: true)
  final int id;
  @Unique()
  final String sku;
  final String name;
  @Column(name: 'price_cents')
  final int priceCents;
  @Column(defaultValue: 0)
  final int stock;
}

@SelectFrom(Product)
typedef ProductCard = ({int id, String name, int priceCents});

@Table('orders')
final class Order {
  const Order({
    required this.id,
    required this.userId,
    required this.requestKey,
    required this.requestSignature,
    required this.totalCents,
    required this.status,
    required this.createdAt,
  });
  @PrimaryKey(autoIncrement: true)
  final int id;
  @Column(name: 'user_id')
  @References('users')
  final int userId;
  @Unique()
  @Column(name: 'request_key')
  final String requestKey;
  @Column(name: 'request_signature')
  final String requestSignature;
  @Column(name: 'total_cents', defaultValue: 0)
  final int totalCents;
  @Column(defaultValue: 'building')
  final String status;
  @Column(name: 'created_at')
  final DateTime createdAt;
}

@Table('order_lines')
final class OrderLine {
  const OrderLine({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.quantity,
    required this.unitPriceCents,
  });
  @PrimaryKey(autoIncrement: true)
  final int id;
  @Column(name: 'order_id')
  @References('orders', onDelete: 'cascade')
  final int orderId;
  @Column(name: 'product_id')
  @References('products')
  final int productId;
  final int quantity;
  @Column(name: 'unit_price_cents')
  final int unitPriceCents;
}
