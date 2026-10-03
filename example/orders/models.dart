import 'package:orm/schema.dart';

export 'receipts.dart';

@Model(table: 'inventory')
@Check('available >= 0', name: 'nonnegative_inventory')
@Check(
  'unit_price_cents >= 0 AND unit_price_cents <= 100000000',
  name: 'price_range',
)
final class Inventory({
  @Id() required final String sku,
  required final String label,
  required final int available,
  required final int unitPriceCents,
});

@Model(table: 'purchase_orders')
@Unique(['customerId', 'requestKey'])
@Check('total_cents >= 0', name: 'nonnegative_total')
final class PurchaseOrder({
  @Id(generated: true) required final int id,
  required final String customerId,
  required final String requestKey,
  required final String requestPayload,
  required final int totalCents,
  required final String? note,
  @ClientDefault(DateTime.now) required final DateTime placedAt,
});

@Model(table: 'order_lines')
@Check('quantity > 0', name: 'positive_quantity')
@Check('unit_price_cents >= 0', name: 'nonnegative_line_price')
final class OrderLine({
  @Id()
  @Relation(
    target: PurchaseOrder,
    name: 'order',
    inverse: 'lines',
    onDelete: .cascade,
  )
  required final int orderId,
  @Id()
  @Relation(target: Inventory, name: 'inventory', key: 'sku')
  required final String sku,
  required final String label,
  required final int quantity,
  required final int unitPriceCents,
});
