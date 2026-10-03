import 'dart:convert';

/// Validated application input. No SQL, session, or ORM write intents live here.
final class OrderRequest {
  final String customerId;
  final String requestKey;
  final String? note;
  final List<CartItem> items;

  OrderRequest({
    required this.customerId,
    required this.requestKey,
    required Iterable<CartItem> items,
    String? note,
  }) : items = _normalize(items),
       note = note?.trim() {
    if (customerId.isEmpty || requestKey.isEmpty) {
      throw ArgumentError('Customer and request key must be nonempty.');
    }
  }

  // Canonical request content deliberately excludes changing catalog prices.
  // Replays return the saved order, including its original price and timestamp.
  String get payload => jsonEncode({
    'items': [
      for (final item in items) [item.sku, item.quantity],
    ],
    'note': note,
  });

  static List<CartItem> _normalize(Iterable<CartItem> items) {
    final quantities = <String, int>{};
    for (final item in items) {
      if (item.sku.isEmpty || item.quantity < 1 || item.quantity > 10000) {
        throw ArgumentError(
          'Each line needs a SKU and quantity from 1 to 10000.',
        );
      }
      final quantity = (quantities[item.sku] ?? 0) + item.quantity;
      if (quantity > 10000) {
        throw ArgumentError('Combined quantity exceeds 10000.');
      }
      quantities[item.sku] = quantity;
    }
    if (quantities.isEmpty || quantities.length > 100) {
      throw ArgumentError('An order needs from 1 to 100 distinct items.');
    }
    final skus = quantities.keys.toList()..sort();
    return List.unmodifiable([
      for (final sku in skus) CartItem(sku: sku, quantity: quantities[sku]!),
    ]);
  }
}

final class CartItem({required final String sku, required final int quantity});

final class InsufficientStock(final String sku) implements Exception {
  @override
  String toString() => 'Insufficient stock: $sku';
}

final class IdempotencyConflict(final String requestKey) implements Exception {
  @override
  String toString() => 'Request key reused with different content: $requestKey';
}
