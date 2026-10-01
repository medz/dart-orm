import 'package:orm/schema.dart';

@Model(table: "products")
@Check(
  "stock >= 0",
  name: "stock_nonnegative",
  postgres: "stock >= 0",
  mysql: "stock >= 0",
  mariadb: "stock >= 0",
)
@Check(
  "price >= 0",
  name: "nonnegative_price",
  postgres: "price >= 0",
  mysql: "price >= 0",
  mariadb: "price >= 0",
)
@Check(
  "discount >= 0 AND discount <= price",
  name: "valid_discount",
  postgres: "discount >= 0 AND discount <= price",
  mysql: "discount >= 0 AND discount <= price",
  mariadb: "discount >= 0 AND discount <= price",
)
@Check(
  "state IN ('draft', 'published')",
  name: "valid_state",
  postgres: "state IN ('draft', 'published')",
  mysql: "state IN ('draft', 'published')",
  mariadb: "state IN ('draft', 'published')",
)
@Check(
  "length(label) <= 20",
  name: "short_label",
  postgres: "char_length(label) <= 20",
  mysql: "length(label) <= 20",
  mariadb: "length(label) <= 20",
)
@Check(
  "label <> '; CHECK (0)'",
  name: null,
  postgres: "label <> '; CHECK (0)'",
  mysql: "label <> '; CHECK (0)'",
  mariadb: "label <> '; CHECK (0)'",
)
@Relation(
  target: Line,
  name: "lines",
  fields: ["id"],
  keys: ["productId"],
  constraint: false,
)
final class Product({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "stock", bits: 16)
  @DatabaseDefault.sql("0")
  required final int stock,
  @Column(name: "price") required final double price,
  @Column(name: "discount") required final double? discount,
  @Column(name: "state") required final String state,
  @Column(name: "label") required final String? label,
});

@Model(table: "lines")
@Relation(
  target: Product,
  name: "product",
  fields: ["productId"],
  keys: ["id"],
  onDelete: .restrict,
)
final class Line({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "product_id") required final int productId,
});
