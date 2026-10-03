import 'package:orm/schema.dart';

@Projection()
final class OrderItem({
  required final String sku,
  required final String label,
  required final int quantity,
  required final int unitPriceCents,
}) {
  int get subtotalCents => quantity * unitPriceCents;
}

@Projection()
final class OrderReceipt({
  required final int id,
  required final String customerId,
  required final String requestKey,
  required final int totalCents,
  required final String? note,
  required final DateTime placedAt,
  required final List<OrderItem> items,
});
