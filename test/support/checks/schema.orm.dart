// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;
export "schema.dart" show Product, Line;

final _productsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _productsStock = Column<int>(
  "stock",
  Codecs.integer,
  nullable: false,
  generated: false,
  defaultSql: "0",
  integerBits: 16,
);
final _productsPrice = Column<double>(
  "price",
  Codecs.real,
  nullable: false,
  generated: false,
);
final _productsDiscount = Column<double?>(
  "discount",
  Codecs.real.nullable(),
  nullable: true,
  generated: false,
);
final _productsState = Column<String>(
  "state",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _productsLabel = Column<String?>(
  "label",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final productsSchema = TableSchema(
  "products",
  columns: [
    _productsId,
    _productsStock,
    _productsPrice,
    _productsDiscount,
    _productsState,
    _productsLabel,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  checks: [
    CheckSchema.forDialects(
      "stock_nonnegative",
      sqlite: "stock >= 0",
      postgres: "stock >= 0",
    ),
    CheckSchema.forDialects(
      "nonnegative_price",
      sqlite: "price >= 0",
      postgres: "price >= 0",
    ),
    CheckSchema.forDialects(
      "valid_discount",
      sqlite: "discount >= 0 AND discount <= price",
      postgres: "discount >= 0 AND discount <= price",
    ),
    CheckSchema.forDialects(
      "valid_state",
      sqlite: "state IN ('draft', 'published')",
      postgres: "state IN ('draft', 'published')",
    ),
    CheckSchema.forDialects(
      "short_label",
      sqlite: "length(label) <= 20",
      postgres: "char_length(label) <= 20",
    ),
    CheckSchema.forDialects(
      null,
      sqlite: "label <> '; CHECK (0)'",
      postgres: "label <> '; CHECK (0)'",
    ),
  ],
  foreignKeys: [],
);

final class ProductsFields extends Fields {
  ProductsFields(super.table);
  late final id = column(_productsId);
  late final stock = column(_productsStock);
  late final price = column(_productsPrice);
  late final discount = column(_productsDiscount);
  late final state = column(_productsState);
  late final label = column(_productsLabel);
  Relation<models.Line, LinesFields> get lines =>
      Relation(linesTable, parent: [id], child: (row) => [row.productId]);
}

final productsTable = Table<models.Product, ProductsFields>(
  productsSchema,
  ProductsFields.new,
  (row) =>
      (row.id, row.stock, row.price, row.discount, row.state, row.label).map(
        (id, stock, price, discount, state, label) => (
          id: id,
          stock: stock,
          price: price,
          discount: discount,
          state: state,
          label: label,
        ),
      ),
);

final class ProductsTableSet extends TableSet<models.Product, ProductsFields> {
  ProductsTableSet(Database<Backend> db) : super(db, productsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Product> create({
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
  Query<models.Product, ProductsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension ProductsUpdates on Query<models.Product, ProductsFields> {
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

final _linesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _linesProductId = Column<int>(
  "product_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final linesSchema = TableSchema(
  "lines",
  columns: [_linesId, _linesProductId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["product_id"], "products", ["id"], onDelete: "RESTRICT"),
  ],
);

final class LinesFields extends Fields {
  LinesFields(super.table);
  late final id = column(_linesId);
  late final productId = column(_linesProductId);
  Relation<models.Product, ProductsFields> get product =>
      Relation(productsTable, parent: [productId], child: (row) => [row.id]);
}

final linesTable = Table<models.Line, LinesFields>(
  linesSchema,
  LinesFields.new,
  (row) => (
    row.id,
    row.productId,
  ).map((id, productId) => (id: id, productId: productId)),
);

final class LinesTableSet extends TableSet<models.Line, LinesFields> {
  LinesTableSet(Database<Backend> db) : super(db, linesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Line> create({
    Change<int> id = const Change.keep(),
    required int productId,
  }) =>
      createRow((row) => [...row.id.change(id), row.productId.set(productId)]);
  Query<models.Line, LinesFields> byId(int id) => where((row) => row.id.eq(id));
}

extension LinesUpdates on Query<models.Line, LinesFields> {
  Future<int> patch({Change<int> productId = const Change.keep()}) =>
      update((row) => [...row.productId.change(productId)]).execute();
}

final appSchema = List<TableSchema>.unmodifiable([productsSchema, linesSchema]);

extension AppTables<B extends Backend> on Database<B> {
  ProductsTableSet get products => ProductsTableSet(this);
  LinesTableSet get lines => LinesTableSet(this);
}
