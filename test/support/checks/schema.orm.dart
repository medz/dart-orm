// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Product, Line;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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
  Relation<models.Product, ProductFields> get product =>
      Relation(productTable, parent: [productId], child: (row) => [row.id]);
}

final lineTable = Table<models.Line, LineFields>(
  lineSchema,
  LineFields.new,
  (row) => (
    row.id,
    row.productId,
  ).map((v0, v1) => models.Line(id: v0, productId: v1)),
);

/// Immutable input data; composition belongs to [linePatch], not field names.
final class LinePatch {
  final WriteValue<int, LineFields> productId;
  LinePatch._({required this.productId});

  List<Assignment> _assignments(LineFields fields) => [
    ...fields.productId.write(productId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class LinePatchFactory {
  LinePatch call({int productId});
  LinePatch values({WriteValue<int, LineFields> productId = const .keep()});
  LinePatch overlay(Iterable<LinePatch> layers);
  bool isEmpty(LinePatch input);
}

const LinePatchFactory linePatch = _LinePatchFactory();

final class _LinePatchFactory implements LinePatchFactory {
  const _LinePatchFactory();
  @override
  LinePatch call({Object? productId = _writeAbsent}) =>
      LinePatch._(productId: _writeLiteral<int, LineFields>(productId));
  @override
  LinePatch values({WriteValue<int, LineFields> productId = const .keep()}) =>
      LinePatch._(productId: productId);
  @override
  LinePatch overlay(Iterable<LinePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = LinePatch._(
        productId: WriteValue.overlay(earlier.productId, later.productId),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(LinePatch input) => input.productId.isMissing;
}

/// Immutable input data; composition belongs to [lineInsert], not field names.
final class LineInsert {
  final WriteValue<int, LineFields> id;
  final WriteValue<int, LineFields> productId;
  LineInsert._({required this.id, required this.productId}) {
    if (productId.isMissing) {
      throw ArgumentError.value(productId, 'productId', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(LineFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.productId.write(productId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class LineInsertFactory {
  LineInsert call({int id, required int productId});
  LineInsert values({
    WriteValue<int, LineFields> id = const .keep(),
    required WriteValue<int, LineFields> productId,
  });
  LineInsert overlay(LineInsert earlier, Iterable<LinePatch> layers);
}

const LineInsertFactory lineInsert = _LineInsertFactory();

final class _LineInsertFactory implements LineInsertFactory {
  const _LineInsertFactory();
  @override
  LineInsert call({Object? id = _writeAbsent, required int productId}) =>
      LineInsert._(
        id: _writeLiteral<int, LineFields>(id),
        productId: .set(productId),
      );
  @override
  LineInsert values({
    WriteValue<int, LineFields> id = const .keep(),
    required WriteValue<int, LineFields> productId,
  }) => LineInsert._(id: id, productId: productId);
  @override
  LineInsert overlay(LineInsert earlier, Iterable<LinePatch> layers) {
    for (final later in layers) {
      earlier = LineInsert._(
        id: earlier.id,
        productId: WriteValue.overlay(earlier.productId, later.productId),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Line from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class LineCreator {
  Future<models.Line> call({int id, required int productId});
}

final class _LineCreator implements LineCreator {
  final LineTableSet _table;
  const _LineCreator(this._table);
  @override
  Future<models.Line> call({
    Object? id = _writeAbsent,
    required int productId,
  }) async => _table.plan
      .insert(
        LineInsert._(
          id: _writeLiteral<int, LineFields>(id),
          productId: .set(productId),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class LinePatcher {
  Future<int> call({int productId});
}

final class _LinePatcher implements LinePatcher {
  final orm_model.ModelQuery<models.Line, LineFields, LinePatch> _query;
  const _LinePatcher(this._query);
  @override
  Future<int> call({Object? productId = _writeAbsent}) => _query.update(
    LinePatch._(productId: _writeLiteral<int, LineFields>(productId)),
  );
}

/// Named literal updates on a complete models.Line query.
extension LineWrites
    on orm_model.ModelQuery<models.Line, LineFields, LinePatch> {
  /// Executes one update; omitted fields remain unchanged.
  LinePatcher get patch => _LinePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class LineTableSet
    extends
        orm_model.ModelTable<models.Line, LineFields, LineInsert, LinePatch> {
  LineTableSet(QueryContext db)
    : super(
        db,
        lineTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final LineCreator create = _LineCreator(this);

  orm_model.ModelQuery<models.Line, LineFields, LinePatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

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

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Line, LineFields> get lines =>
      Relation(lineTable, parent: [id], child: (row) => [row.productId]);
}

final productTable = Table<models.Product, ProductFields>(
  productSchema,
  ProductFields.new,
  (row) =>
      (row.id, row.stock, row.price, row.discount, row.state, row.label).map(
        (v0, v1, v2, v3, v4, v5) => models.Product(
          id: v0,
          stock: v1,
          price: v2,
          discount: v3,
          state: v4,
          label: v5,
        ),
      ),
);

/// Immutable input data; composition belongs to [productPatch], not field names.
final class ProductPatch {
  final WriteValue<int, ProductFields> stock;
  final WriteValue<double, ProductFields> price;
  final WriteValue<double?, ProductFields> discount;
  final WriteValue<String, ProductFields> state;
  final WriteValue<String?, ProductFields> label;
  ProductPatch._({
    required this.stock,
    required this.price,
    required this.discount,
    required this.state,
    required this.label,
  });

  List<Assignment> _assignments(ProductFields fields) => [
    ...fields.stock.write(stock, fields),
    ...fields.price.write(price, fields),
    ...fields.discount.write(discount, fields),
    ...fields.state.write(state, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ProductPatchFactory {
  ProductPatch call({
    int stock,
    double price,
    double? discount,
    String state,
    String? label,
  });
  ProductPatch values({
    WriteValue<int, ProductFields> stock = const .keep(),
    WriteValue<double, ProductFields> price = const .keep(),
    WriteValue<double?, ProductFields> discount = const .keep(),
    WriteValue<String, ProductFields> state = const .keep(),
    WriteValue<String?, ProductFields> label = const .keep(),
  });
  ProductPatch overlay(Iterable<ProductPatch> layers);
  bool isEmpty(ProductPatch input);
}

const ProductPatchFactory productPatch = _ProductPatchFactory();

final class _ProductPatchFactory implements ProductPatchFactory {
  const _ProductPatchFactory();
  @override
  ProductPatch call({
    Object? stock = _writeAbsent,
    Object? price = _writeAbsent,
    Object? discount = _writeAbsent,
    Object? state = _writeAbsent,
    Object? label = _writeAbsent,
  }) => ProductPatch._(
    stock: _writeLiteral<int, ProductFields>(stock),
    price: _writeLiteral<double, ProductFields>(price),
    discount: _writeLiteral<double?, ProductFields>(discount),
    state: _writeLiteral<String, ProductFields>(state),
    label: _writeLiteral<String?, ProductFields>(label),
  );
  @override
  ProductPatch values({
    WriteValue<int, ProductFields> stock = const .keep(),
    WriteValue<double, ProductFields> price = const .keep(),
    WriteValue<double?, ProductFields> discount = const .keep(),
    WriteValue<String, ProductFields> state = const .keep(),
    WriteValue<String?, ProductFields> label = const .keep(),
  }) => ProductPatch._(
    stock: stock,
    price: price,
    discount: discount,
    state: state,
    label: label,
  );
  @override
  ProductPatch overlay(Iterable<ProductPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = ProductPatch._(
        stock: WriteValue.overlay(earlier.stock, later.stock),
        price: WriteValue.overlay(earlier.price, later.price),
        discount: WriteValue.overlay(earlier.discount, later.discount),
        state: WriteValue.overlay(earlier.state, later.state),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(ProductPatch input) =>
      input.stock.isMissing &&
      input.price.isMissing &&
      input.discount.isMissing &&
      input.state.isMissing &&
      input.label.isMissing;
}

/// Immutable input data; composition belongs to [productInsert], not field names.
final class ProductInsert {
  final WriteValue<int, ProductFields> id;
  final WriteValue<int, ProductFields> stock;
  final WriteValue<double, ProductFields> price;
  final WriteValue<double?, ProductFields> discount;
  final WriteValue<String, ProductFields> state;
  final WriteValue<String?, ProductFields> label;
  ProductInsert._({
    required this.id,
    required this.stock,
    required this.price,
    required this.discount,
    required this.state,
    required this.label,
  }) {
    if (price.isMissing) {
      throw ArgumentError.value(price, 'price', 'Must be supplied.');
    }
    if (state.isMissing) {
      throw ArgumentError.value(state, 'state', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(ProductFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.stock.write(stock, fields),
    ...fields.price.write(price, fields),
    ...fields.discount.write(discount, fields),
    ...fields.state.write(state, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ProductInsertFactory {
  ProductInsert call({
    int id,
    int stock,
    required double price,
    double? discount,
    required String state,
    String? label,
  });
  ProductInsert values({
    WriteValue<int, ProductFields> id = const .keep(),
    WriteValue<int, ProductFields> stock = const .keep(),
    required WriteValue<double, ProductFields> price,
    WriteValue<double?, ProductFields> discount = const .keep(),
    required WriteValue<String, ProductFields> state,
    WriteValue<String?, ProductFields> label = const .keep(),
  });
  ProductInsert overlay(ProductInsert earlier, Iterable<ProductPatch> layers);
}

const ProductInsertFactory productInsert = _ProductInsertFactory();

final class _ProductInsertFactory implements ProductInsertFactory {
  const _ProductInsertFactory();
  @override
  ProductInsert call({
    Object? id = _writeAbsent,
    Object? stock = _writeAbsent,
    required double price,
    Object? discount = _writeAbsent,
    required String state,
    Object? label = _writeAbsent,
  }) => ProductInsert._(
    id: _writeLiteral<int, ProductFields>(id),
    stock: _writeLiteral<int, ProductFields>(stock),
    price: .set(price),
    discount: _writeLiteral<double?, ProductFields>(discount),
    state: .set(state),
    label: _writeLiteral<String?, ProductFields>(label),
  );
  @override
  ProductInsert values({
    WriteValue<int, ProductFields> id = const .keep(),
    WriteValue<int, ProductFields> stock = const .keep(),
    required WriteValue<double, ProductFields> price,
    WriteValue<double?, ProductFields> discount = const .keep(),
    required WriteValue<String, ProductFields> state,
    WriteValue<String?, ProductFields> label = const .keep(),
  }) => ProductInsert._(
    id: id,
    stock: stock,
    price: price,
    discount: discount,
    state: state,
    label: label,
  );
  @override
  ProductInsert overlay(ProductInsert earlier, Iterable<ProductPatch> layers) {
    for (final later in layers) {
      earlier = ProductInsert._(
        id: earlier.id,
        stock: WriteValue.overlay(earlier.stock, later.stock),
        price: WriteValue.overlay(earlier.price, later.price),
        discount: WriteValue.overlay(earlier.discount, later.discount),
        state: WriteValue.overlay(earlier.state, later.state),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Product from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class ProductCreator {
  Future<models.Product> call({
    int id,
    int stock,
    required double price,
    double? discount,
    required String state,
    String? label,
  });
}

final class _ProductCreator implements ProductCreator {
  final ProductTableSet _table;
  const _ProductCreator(this._table);
  @override
  Future<models.Product> call({
    Object? id = _writeAbsent,
    Object? stock = _writeAbsent,
    required double price,
    Object? discount = _writeAbsent,
    required String state,
    Object? label = _writeAbsent,
  }) async => _table.plan
      .insert(
        ProductInsert._(
          id: _writeLiteral<int, ProductFields>(id),
          stock: _writeLiteral<int, ProductFields>(stock),
          price: .set(price),
          discount: _writeLiteral<double?, ProductFields>(discount),
          state: .set(state),
          label: _writeLiteral<String?, ProductFields>(label),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class ProductPatcher {
  Future<int> call({
    int stock,
    double price,
    double? discount,
    String state,
    String? label,
  });
}

final class _ProductPatcher implements ProductPatcher {
  final orm_model.ModelQuery<models.Product, ProductFields, ProductPatch>
  _query;
  const _ProductPatcher(this._query);
  @override
  Future<int> call({
    Object? stock = _writeAbsent,
    Object? price = _writeAbsent,
    Object? discount = _writeAbsent,
    Object? state = _writeAbsent,
    Object? label = _writeAbsent,
  }) => _query.update(
    ProductPatch._(
      stock: _writeLiteral<int, ProductFields>(stock),
      price: _writeLiteral<double, ProductFields>(price),
      discount: _writeLiteral<double?, ProductFields>(discount),
      state: _writeLiteral<String, ProductFields>(state),
      label: _writeLiteral<String?, ProductFields>(label),
    ),
  );
}

/// Named literal updates on a complete models.Product query.
extension ProductWrites
    on orm_model.ModelQuery<models.Product, ProductFields, ProductPatch> {
  /// Executes one update; omitted fields remain unchanged.
  ProductPatcher get patch => _ProductPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class ProductTableSet
    extends
        orm_model.ModelTable<
          models.Product,
          ProductFields,
          ProductInsert,
          ProductPatch
        > {
  ProductTableSet(QueryContext db)
    : super(
        db,
        productTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final ProductCreator create = _ProductCreator(this);

  orm_model.ModelQuery<models.Product, ProductFields, ProductPatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([lineSchema, productSchema]);

extension AppTables on QueryContext {
  LineTableSet get line => LineTableSet(this);
  ProductTableSet get product => ProductTableSet(this);
}
