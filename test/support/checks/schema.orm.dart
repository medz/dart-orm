// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

/// A complete immutable row from "products".
final class Product({
  required final int id,
  required final int stock,
  required final double price,
  required final double? discount,
  required final String state,
  required final String? label,
});
final _productId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _productStock = Column<int>(
  "stock",
  Codecs.integer,
  nullable: false,
  generated: false,
  defaultSql: "0",
  integerBits: 16,
);
final _productPrice = Column<double>(
  "price",
  Codecs.real,
  nullable: false,
  generated: false,
);
final _productDiscount = Column<double?>(
  "discount",
  Codecs.real.nullable(),
  nullable: true,
  generated: false,
);
final _productState = Column<String>(
  "state",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _productLabel = Column<String?>(
  "label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final productSchema = TableSchema(
  "products",
  columns: [
    _productId,
    _productStock,
    _productPrice,
    _productDiscount,
    _productState,
    _productLabel,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  checks: [
    CheckSchema.forDialects(
      "stock_nonnegative",
      sqlite: "stock >= 0",
      postgres: "stock >= 0",
      mysql: "stock >= 0",
      mariadb: "stock >= 0",
    ),
    CheckSchema.forDialects(
      "nonnegative_price",
      sqlite: "price >= 0",
      postgres: "price >= 0",
      mysql: "price >= 0",
      mariadb: "price >= 0",
    ),
    CheckSchema.forDialects(
      "valid_discount",
      sqlite: "discount >= 0 AND discount <= price",
      postgres: "discount >= 0 AND discount <= price",
      mysql: "discount >= 0 AND discount <= price",
      mariadb: "discount >= 0 AND discount <= price",
    ),
    CheckSchema.forDialects(
      "valid_state",
      sqlite: "state IN ('draft', 'published')",
      postgres: "state IN ('draft', 'published')",
      mysql: "state IN ('draft', 'published')",
      mariadb: "state IN ('draft', 'published')",
    ),
    CheckSchema.forDialects(
      "short_label",
      sqlite: "length(label) <= 20",
      postgres: "char_length(label) <= 20",
      mysql: "length(label) <= 20",
      mariadb: "length(label) <= 20",
    ),
    CheckSchema.forDialects(
      null,
      sqlite: "label <> '; CHECK (0)'",
      postgres: "label <> '; CHECK (0)'",
      mysql: "label <> '; CHECK (0)'",
      mariadb: "label <> '; CHECK (0)'",
    ),
  ],
  foreignKeys: [],
);

final class ProductFields extends Fields {
  ProductFields(super.table);
  late final id = column(_productId);
  late final stock = column(_productStock);
  late final price = column(_productPrice);
  late final discount = column(_productDiscount);
  late final state = column(_productState);
  late final label = column(_productLabel);
  Relation<Line, LineFields> get lines =>
      Relation(lineTable, parent: [id], child: (row) => [row.productId]);
}

final productTable = Table<Product, ProductFields>(
  productSchema,
  ProductFields.new,
  (row) =>
      (row.id, row.stock, row.price, row.discount, row.state, row.label).map(
        (v0, v1, v2, v3, v4, v5) => Product(
          id: v0,
          stock: v1,
          price: v2,
          discount: v3,
          state: v4,
          label: v5,
        ),
      ),
);

final class ProductTableSet extends TableSet<Product, ProductFields> {
  ProductTableSet(QueryContext db) : super(db, productTable) {
    db.registerSchema(appSchema);
  }
  Future<Product> create({
    Change<int> id = const Change.keep(),
    Change<int> stock = const Change.keep(),
    required double price,
    double? discount,
    required String state,
    String? label,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      ...row.stock.change(stock),
      row.price.set(price),
      row.discount.set(discount),
      row.state.set(state),
      row.label.set(label),
    ],
  );
  Query<Product, ProductFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension ProductUpdates on Query<Product, ProductFields> {
  Future<int> patch({
    Change<int> stock = const Change.keep(),
    Change<double> price = const Change.keep(),
    Change<double?> discount = const Change.keep(),
    Change<String> state = const Change.keep(),
    Change<String?> label = const Change.keep(),
  }) => update(
    (row) => [
      ...row.stock.change(stock),
      ...row.price.change(price),
      ...row.discount.change(discount),
      ...row.state.change(state),
      ...row.label.change(label),
    ],
  ).execute();
}

/// A complete immutable row from "lines".
final class Line({required final int id, required final int productId});
final _lineId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _lineProductId = Column<int>(
  "product_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final lineSchema = TableSchema(
  "lines",
  columns: [_lineId, _lineProductId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["product_id"], "products", ["id"], onDelete: "RESTRICT"),
  ],
);

final class LineFields extends Fields {
  LineFields(super.table);
  late final id = column(_lineId);
  late final productId = column(_lineProductId);
  Relation<Product, ProductFields> get product =>
      Relation(productTable, parent: [productId], child: (row) => [row.id]);
}

final lineTable = Table<Line, LineFields>(
  lineSchema,
  LineFields.new,
  (row) => (row.id, row.productId).map((v0, v1) => Line(id: v0, productId: v1)),
);

final class LineTableSet extends TableSet<Line, LineFields> {
  LineTableSet(QueryContext db) : super(db, lineTable) {
    db.registerSchema(appSchema);
  }
  Future<Line> create({
    Change<int> id = const Change.keep(),
    required int productId,
  }) =>
      createRow((row) => [...row.id.change(id), row.productId.set(productId)]);
  Query<Line, LineFields> byId(int id) => where((row) => row.id.eq(.value(id)));
}

extension LineUpdates on Query<Line, LineFields> {
  Future<int> patch({Change<int> productId = const Change.keep()}) =>
      update((row) => [...row.productId.change(productId)]).execute();
}

final appSchema = List<TableSchema>.unmodifiable([productSchema, lineSchema]);

extension AppTables on QueryContext {
  ProductTableSet get product => ProductTableSet(this);
  LineTableSet get line => LineTableSet(this);
}
