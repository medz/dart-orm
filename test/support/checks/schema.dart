import 'package:orm/schema.dart';

typedef Product = ({
  @Id.generated() int id,
  @IntegerBits(16) @Default.sql('0') int stock,
  double price,
  double? discount,
  String state,
  String? label,
});
typedef Line = ({@Id.generated() int id, int productId});
final products = entity<Product>();
final lines = entity<Line>();
final nonnegativeStock = products.check(
  'stock >= 0',
  name: 'stock_nonnegative',
);
final nonnegativePrice = products.check('price >= 0');
final validDiscount = products.check('discount >= 0 AND discount <= price');
final validState = products.check("state IN ('draft', 'published')");
final shortLabel = products.check(
  'length(label) <= 20',
  postgres: 'char_length(label) <= 20',
);
final literalLabel = products.check("label <> '; CHECK (0)'", name: null);
final product = lines
    .key((l) => l.productId)
    .references(products.key((p) => p.id), inverse: 'lines');
