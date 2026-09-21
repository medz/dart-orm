import 'package:orm/schema.dart';

final Model product = model(
  "products",
  (
    id: integer().identity(),
    stock: integer(defaultSql: "0", bits: 16),
    price: real(),
    discount: real().nullable(),
    state: text(),
    label: text().nullable(),
  ),
  checks: [
    check(
      "stock >= 0",
      name: "stock_nonnegative",
      postgres: "stock >= 0",
      mysql: "stock >= 0",
      mariadb: "stock >= 0",
    ),
    check(
      "price >= 0",
      name: "nonnegative_price",
      postgres: "price >= 0",
      mysql: "price >= 0",
      mariadb: "price >= 0",
    ),
    check(
      "discount >= 0 AND discount <= price",
      name: "valid_discount",
      postgres: "discount >= 0 AND discount <= price",
      mysql: "discount >= 0 AND discount <= price",
      mariadb: "discount >= 0 AND discount <= price",
    ),
    check(
      "state IN ('draft', 'published')",
      name: "valid_state",
      postgres: "state IN ('draft', 'published')",
      mysql: "state IN ('draft', 'published')",
      mariadb: "state IN ('draft', 'published')",
    ),
    check(
      "length(label) <= 20",
      name: "short_label",
      postgres: "char_length(label) <= 20",
      mysql: "length(label) <= 20",
      mariadb: "length(label) <= 20",
    ),
    check(
      "label <> '; CHECK (0)'",
      name: null,
      postgres: "label <> '; CHECK (0)'",
      mysql: "label <> '; CHECK (0)'",
      mariadb: "label <> '; CHECK (0)'",
    ),
  ],
  relations: (r) => (lines: referencedBy(() => line, on: (productId: r.id))),
);

final Model line = model(
  "lines",
  (id: integer().identity(), productId: integer()),
  relations: (r) => (
    product: references((id: r.productId), () => product, onDelete: .restrict),
  ),
);
