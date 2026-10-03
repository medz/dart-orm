// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/sql.dart'
    as orm_projection
    show Slot, ProjectionType, ProjectionOutput, ProjectionFields, Projection;
import 'package:orm/values.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "models.dart" as models;
export "models.dart" show Inventory, PurchaseOrder, OrderLine;
export "receipts.dart" show OrderItem, OrderReceipt;
import "receipts.dart" as types0;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _inventorySku = Column<String>(
  "sku",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _inventoryLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _inventoryAvailable = Column<int>(
  "available",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _inventoryUnitPriceCents = Column<int>(
  "unit_price_cents",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final inventorySchema = TableSchema(
  "inventory",
  columns: [
    _inventorySku,
    _inventoryLabel,
    _inventoryAvailable,
    _inventoryUnitPriceCents,
  ],
  primaryKey: ["sku"],
  uniqueKeys: [],
  indexes: [],
  checks: [
    CheckSchema.forDialects(
      "nonnegative_inventory",
      sqlite: "available >= 0",
      postgres: "available >= 0",
      mysql: "available >= 0",
      mariadb: "available >= 0",
    ),
    CheckSchema.forDialects(
      "price_range",
      sqlite: "unit_price_cents >= 0 AND unit_price_cents <= 100000000",
      postgres: "unit_price_cents >= 0 AND unit_price_cents <= 100000000",
      mysql: "unit_price_cents >= 0 AND unit_price_cents <= 100000000",
      mariadb: "unit_price_cents >= 0 AND unit_price_cents <= 100000000",
    ),
  ],
  foreignKeys: [],
);

final class InventoryFields extends Fields {
  InventoryFields(super.table);
  late final sku = column(_inventorySku);
  late final label = column(_inventoryLabel);
  late final available = column(_inventoryAvailable);
  late final unitPriceCents = column(_inventoryUnitPriceCents);
}

final inventoryTable = Table<models.Inventory, InventoryFields>(
  inventorySchema,
  InventoryFields.new,
  (row) => (row.sku, row.label, row.available, row.unitPriceCents).map(
    (v0, v1, v2, v3) =>
        models.Inventory(sku: v0, label: v1, available: v2, unitPriceCents: v3),
  ),
);

/// Immutable input data; composition belongs to [inventoryPatch], not field names.
final class InventoryPatch {
  final WriteValue<String, InventoryFields> sku;
  final WriteValue<String, InventoryFields> label;
  final WriteValue<int, InventoryFields> available;
  final WriteValue<int, InventoryFields> unitPriceCents;
  InventoryPatch._({
    required this.sku,
    required this.label,
    required this.available,
    required this.unitPriceCents,
  });

  List<Assignment> _assignments(InventoryFields fields) => [
    ...fields.sku.write(sku, fields),
    ...fields.label.write(label, fields),
    ...fields.available.write(available, fields),
    ...fields.unitPriceCents.write(unitPriceCents, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class InventoryPatchFactory {
  InventoryPatch call({
    String sku,
    String label,
    int available,
    int unitPriceCents,
  });
  InventoryPatch values({
    WriteValue<String, InventoryFields> sku = const .keep(),
    WriteValue<String, InventoryFields> label = const .keep(),
    WriteValue<int, InventoryFields> available = const .keep(),
    WriteValue<int, InventoryFields> unitPriceCents = const .keep(),
  });
  InventoryPatch overlay(Iterable<InventoryPatch> layers);
  bool isEmpty(InventoryPatch input);
}

const InventoryPatchFactory inventoryPatch = _InventoryPatchFactory();

final class _InventoryPatchFactory implements InventoryPatchFactory {
  const _InventoryPatchFactory();
  @override
  InventoryPatch call({
    Object? sku = _writeAbsent,
    Object? label = _writeAbsent,
    Object? available = _writeAbsent,
    Object? unitPriceCents = _writeAbsent,
  }) => InventoryPatch._(
    sku: _writeLiteral<String, InventoryFields>(sku),
    label: _writeLiteral<String, InventoryFields>(label),
    available: _writeLiteral<int, InventoryFields>(available),
    unitPriceCents: _writeLiteral<int, InventoryFields>(unitPriceCents),
  );
  @override
  InventoryPatch values({
    WriteValue<String, InventoryFields> sku = const .keep(),
    WriteValue<String, InventoryFields> label = const .keep(),
    WriteValue<int, InventoryFields> available = const .keep(),
    WriteValue<int, InventoryFields> unitPriceCents = const .keep(),
  }) => InventoryPatch._(
    sku: sku,
    label: label,
    available: available,
    unitPriceCents: unitPriceCents,
  );
  @override
  InventoryPatch overlay(Iterable<InventoryPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = InventoryPatch._(
        sku: WriteValue.overlay(earlier.sku, later.sku),
        label: WriteValue.overlay(earlier.label, later.label),
        available: WriteValue.overlay(earlier.available, later.available),
        unitPriceCents: WriteValue.overlay(
          earlier.unitPriceCents,
          later.unitPriceCents,
        ),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(InventoryPatch input) =>
      input.sku.isMissing &&
      input.label.isMissing &&
      input.available.isMissing &&
      input.unitPriceCents.isMissing;
}

/// Immutable input data; composition belongs to [inventoryInsert], not field names.
final class InventoryInsert {
  final WriteValue<String, InventoryFields> sku;
  final WriteValue<String, InventoryFields> label;
  final WriteValue<int, InventoryFields> available;
  final WriteValue<int, InventoryFields> unitPriceCents;
  InventoryInsert._({
    required this.sku,
    required this.label,
    required this.available,
    required this.unitPriceCents,
  }) {
    if (sku.isMissing) {
      throw ArgumentError.value(sku, 'sku', 'Must be supplied.');
    }
    if (label.isMissing) {
      throw ArgumentError.value(label, 'label', 'Must be supplied.');
    }
    if (available.isMissing) {
      throw ArgumentError.value(available, 'available', 'Must be supplied.');
    }
    if (unitPriceCents.isMissing) {
      throw ArgumentError.value(
        unitPriceCents,
        'unitPriceCents',
        'Must be supplied.',
      );
    }
  }
  List<Assignment> _assignments(InventoryFields fields) => [
    ...fields.sku.write(sku, fields),
    ...fields.label.write(label, fields),
    ...fields.available.write(available, fields),
    ...fields.unitPriceCents.write(unitPriceCents, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class InventoryInsertFactory {
  InventoryInsert call({
    required String sku,
    required String label,
    required int available,
    required int unitPriceCents,
  });
  InventoryInsert values({
    required WriteValue<String, InventoryFields> sku,
    required WriteValue<String, InventoryFields> label,
    required WriteValue<int, InventoryFields> available,
    required WriteValue<int, InventoryFields> unitPriceCents,
  });
  InventoryInsert overlay(
    InventoryInsert earlier,
    Iterable<InventoryPatch> layers,
  );
}

const InventoryInsertFactory inventoryInsert = _InventoryInsertFactory();

final class _InventoryInsertFactory implements InventoryInsertFactory {
  const _InventoryInsertFactory();
  @override
  InventoryInsert call({
    required String sku,
    required String label,
    required int available,
    required int unitPriceCents,
  }) => InventoryInsert._(
    sku: .set(sku),
    label: .set(label),
    available: .set(available),
    unitPriceCents: .set(unitPriceCents),
  );
  @override
  InventoryInsert values({
    required WriteValue<String, InventoryFields> sku,
    required WriteValue<String, InventoryFields> label,
    required WriteValue<int, InventoryFields> available,
    required WriteValue<int, InventoryFields> unitPriceCents,
  }) => InventoryInsert._(
    sku: sku,
    label: label,
    available: available,
    unitPriceCents: unitPriceCents,
  );
  @override
  InventoryInsert overlay(
    InventoryInsert earlier,
    Iterable<InventoryPatch> layers,
  ) {
    for (final later in layers) {
      earlier = InventoryInsert._(
        sku: WriteValue.overlay(earlier.sku, later.sku),
        label: WriteValue.overlay(earlier.label, later.label),
        available: WriteValue.overlay(earlier.available, later.available),
        unitPriceCents: WriteValue.overlay(
          earlier.unitPriceCents,
          later.unitPriceCents,
        ),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Inventory from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class InventoryCreator {
  Future<models.Inventory> call({
    required String sku,
    required String label,
    required int available,
    required int unitPriceCents,
  });
}

final class _InventoryCreator implements InventoryCreator {
  final InventoryTableSet _table;
  const _InventoryCreator(this._table);
  @override
  Future<models.Inventory> call({
    required String sku,
    required String label,
    required int available,
    required int unitPriceCents,
  }) async => _table.plan
      .insert(
        InventoryInsert._(
          sku: .set(sku),
          label: .set(label),
          available: .set(available),
          unitPriceCents: .set(unitPriceCents),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class InventoryPatcher {
  Future<int> call({
    String sku,
    String label,
    int available,
    int unitPriceCents,
  });
}

final class _InventoryPatcher implements InventoryPatcher {
  final orm_model.ModelQuery<models.Inventory, InventoryFields, InventoryPatch>
  _query;
  const _InventoryPatcher(this._query);
  @override
  Future<int> call({
    Object? sku = _writeAbsent,
    Object? label = _writeAbsent,
    Object? available = _writeAbsent,
    Object? unitPriceCents = _writeAbsent,
  }) => _query.update(
    InventoryPatch._(
      sku: _writeLiteral<String, InventoryFields>(sku),
      label: _writeLiteral<String, InventoryFields>(label),
      available: _writeLiteral<int, InventoryFields>(available),
      unitPriceCents: _writeLiteral<int, InventoryFields>(unitPriceCents),
    ),
  );
}

/// Named literal updates on a complete models.Inventory query.
extension InventoryWrites
    on orm_model.ModelQuery<models.Inventory, InventoryFields, InventoryPatch> {
  /// Executes one update; omitted fields remain unchanged.
  InventoryPatcher get patch => _InventoryPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class InventoryTableSet
    extends
        orm_model.ModelTable<
          models.Inventory,
          InventoryFields,
          InventoryInsert,
          InventoryPatch
        > {
  InventoryTableSet(QueryContext db)
    : super(
        db,
        inventoryTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final InventoryCreator create = _InventoryCreator(this);

  orm_model.ModelQuery<models.Inventory, InventoryFields, InventoryPatch> byId(
    String sku,
  ) => where((row) => row.sku.eq(.value(sku)));
}

final _orderLineOrderId = Column<int>(
  "order_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _orderLineSku = Column<String>(
  "sku",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _orderLineLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _orderLineQuantity = Column<int>(
  "quantity",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _orderLineUnitPriceCents = Column<int>(
  "unit_price_cents",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final orderLineSchema = TableSchema(
  "order_lines",
  columns: [
    _orderLineOrderId,
    _orderLineSku,
    _orderLineLabel,
    _orderLineQuantity,
    _orderLineUnitPriceCents,
  ],
  primaryKey: ["order_id", "sku"],
  uniqueKeys: [],
  indexes: [],
  checks: [
    CheckSchema.forDialects(
      "positive_quantity",
      sqlite: "quantity > 0",
      postgres: "quantity > 0",
      mysql: "quantity > 0",
      mariadb: "quantity > 0",
    ),
    CheckSchema.forDialects(
      "nonnegative_line_price",
      sqlite: "unit_price_cents >= 0",
      postgres: "unit_price_cents >= 0",
      mysql: "unit_price_cents >= 0",
      mariadb: "unit_price_cents >= 0",
    ),
  ],
  foreignKeys: [
    ForeignKey(["order_id"], "purchase_orders", ["id"], onDelete: "CASCADE"),
    ForeignKey(["sku"], "inventory", ["sku"], onDelete: "RESTRICT"),
  ],
);

final class OrderLineFields extends Fields {
  OrderLineFields(super.table);
  late final orderId = column(_orderLineOrderId);
  late final sku = column(_orderLineSku);
  late final label = column(_orderLineLabel);
  late final quantity = column(_orderLineQuantity);
  late final unitPriceCents = column(_orderLineUnitPriceCents);
  Relation<models.PurchaseOrder, PurchaseOrderFields> get order =>
      Relation(purchaseOrderTable, parent: [orderId], child: (row) => [row.id]);
  Relation<models.Inventory, InventoryFields> get inventory =>
      Relation(inventoryTable, parent: [sku], child: (row) => [row.sku]);
}

final orderLineTable = Table<models.OrderLine, OrderLineFields>(
  orderLineSchema,
  OrderLineFields.new,
  (row) =>
      (row.orderId, row.sku, row.label, row.quantity, row.unitPriceCents).map(
        (v0, v1, v2, v3, v4) => models.OrderLine(
          orderId: v0,
          sku: v1,
          label: v2,
          quantity: v3,
          unitPriceCents: v4,
        ),
      ),
);

/// Immutable input data; composition belongs to [orderLinePatch], not field names.
final class OrderLinePatch {
  final WriteValue<int, OrderLineFields> orderId;
  final WriteValue<String, OrderLineFields> sku;
  final WriteValue<String, OrderLineFields> label;
  final WriteValue<int, OrderLineFields> quantity;
  final WriteValue<int, OrderLineFields> unitPriceCents;
  OrderLinePatch._({
    required this.orderId,
    required this.sku,
    required this.label,
    required this.quantity,
    required this.unitPriceCents,
  });

  List<Assignment> _assignments(OrderLineFields fields) => [
    ...fields.orderId.write(orderId, fields),
    ...fields.sku.write(sku, fields),
    ...fields.label.write(label, fields),
    ...fields.quantity.write(quantity, fields),
    ...fields.unitPriceCents.write(unitPriceCents, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class OrderLinePatchFactory {
  OrderLinePatch call({
    int orderId,
    String sku,
    String label,
    int quantity,
    int unitPriceCents,
  });
  OrderLinePatch values({
    WriteValue<int, OrderLineFields> orderId = const .keep(),
    WriteValue<String, OrderLineFields> sku = const .keep(),
    WriteValue<String, OrderLineFields> label = const .keep(),
    WriteValue<int, OrderLineFields> quantity = const .keep(),
    WriteValue<int, OrderLineFields> unitPriceCents = const .keep(),
  });
  OrderLinePatch overlay(Iterable<OrderLinePatch> layers);
  bool isEmpty(OrderLinePatch input);
}

const OrderLinePatchFactory orderLinePatch = _OrderLinePatchFactory();

final class _OrderLinePatchFactory implements OrderLinePatchFactory {
  const _OrderLinePatchFactory();
  @override
  OrderLinePatch call({
    Object? orderId = _writeAbsent,
    Object? sku = _writeAbsent,
    Object? label = _writeAbsent,
    Object? quantity = _writeAbsent,
    Object? unitPriceCents = _writeAbsent,
  }) => OrderLinePatch._(
    orderId: _writeLiteral<int, OrderLineFields>(orderId),
    sku: _writeLiteral<String, OrderLineFields>(sku),
    label: _writeLiteral<String, OrderLineFields>(label),
    quantity: _writeLiteral<int, OrderLineFields>(quantity),
    unitPriceCents: _writeLiteral<int, OrderLineFields>(unitPriceCents),
  );
  @override
  OrderLinePatch values({
    WriteValue<int, OrderLineFields> orderId = const .keep(),
    WriteValue<String, OrderLineFields> sku = const .keep(),
    WriteValue<String, OrderLineFields> label = const .keep(),
    WriteValue<int, OrderLineFields> quantity = const .keep(),
    WriteValue<int, OrderLineFields> unitPriceCents = const .keep(),
  }) => OrderLinePatch._(
    orderId: orderId,
    sku: sku,
    label: label,
    quantity: quantity,
    unitPriceCents: unitPriceCents,
  );
  @override
  OrderLinePatch overlay(Iterable<OrderLinePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = OrderLinePatch._(
        orderId: WriteValue.overlay(earlier.orderId, later.orderId),
        sku: WriteValue.overlay(earlier.sku, later.sku),
        label: WriteValue.overlay(earlier.label, later.label),
        quantity: WriteValue.overlay(earlier.quantity, later.quantity),
        unitPriceCents: WriteValue.overlay(
          earlier.unitPriceCents,
          later.unitPriceCents,
        ),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(OrderLinePatch input) =>
      input.orderId.isMissing &&
      input.sku.isMissing &&
      input.label.isMissing &&
      input.quantity.isMissing &&
      input.unitPriceCents.isMissing;
}

/// Immutable input data; composition belongs to [orderLineInsert], not field names.
final class OrderLineInsert {
  final WriteValue<int, OrderLineFields> orderId;
  final WriteValue<String, OrderLineFields> sku;
  final WriteValue<String, OrderLineFields> label;
  final WriteValue<int, OrderLineFields> quantity;
  final WriteValue<int, OrderLineFields> unitPriceCents;
  OrderLineInsert._({
    required this.orderId,
    required this.sku,
    required this.label,
    required this.quantity,
    required this.unitPriceCents,
  }) {
    if (orderId.isMissing) {
      throw ArgumentError.value(orderId, 'orderId', 'Must be supplied.');
    }
    if (sku.isMissing) {
      throw ArgumentError.value(sku, 'sku', 'Must be supplied.');
    }
    if (label.isMissing) {
      throw ArgumentError.value(label, 'label', 'Must be supplied.');
    }
    if (quantity.isMissing) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be supplied.');
    }
    if (unitPriceCents.isMissing) {
      throw ArgumentError.value(
        unitPriceCents,
        'unitPriceCents',
        'Must be supplied.',
      );
    }
  }
  List<Assignment> _assignments(OrderLineFields fields) => [
    ...fields.orderId.write(orderId, fields),
    ...fields.sku.write(sku, fields),
    ...fields.label.write(label, fields),
    ...fields.quantity.write(quantity, fields),
    ...fields.unitPriceCents.write(unitPriceCents, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class OrderLineInsertFactory {
  OrderLineInsert call({
    required int orderId,
    required String sku,
    required String label,
    required int quantity,
    required int unitPriceCents,
  });
  OrderLineInsert values({
    required WriteValue<int, OrderLineFields> orderId,
    required WriteValue<String, OrderLineFields> sku,
    required WriteValue<String, OrderLineFields> label,
    required WriteValue<int, OrderLineFields> quantity,
    required WriteValue<int, OrderLineFields> unitPriceCents,
  });
  OrderLineInsert overlay(
    OrderLineInsert earlier,
    Iterable<OrderLinePatch> layers,
  );
}

const OrderLineInsertFactory orderLineInsert = _OrderLineInsertFactory();

final class _OrderLineInsertFactory implements OrderLineInsertFactory {
  const _OrderLineInsertFactory();
  @override
  OrderLineInsert call({
    required int orderId,
    required String sku,
    required String label,
    required int quantity,
    required int unitPriceCents,
  }) => OrderLineInsert._(
    orderId: .set(orderId),
    sku: .set(sku),
    label: .set(label),
    quantity: .set(quantity),
    unitPriceCents: .set(unitPriceCents),
  );
  @override
  OrderLineInsert values({
    required WriteValue<int, OrderLineFields> orderId,
    required WriteValue<String, OrderLineFields> sku,
    required WriteValue<String, OrderLineFields> label,
    required WriteValue<int, OrderLineFields> quantity,
    required WriteValue<int, OrderLineFields> unitPriceCents,
  }) => OrderLineInsert._(
    orderId: orderId,
    sku: sku,
    label: label,
    quantity: quantity,
    unitPriceCents: unitPriceCents,
  );
  @override
  OrderLineInsert overlay(
    OrderLineInsert earlier,
    Iterable<OrderLinePatch> layers,
  ) {
    for (final later in layers) {
      earlier = OrderLineInsert._(
        orderId: WriteValue.overlay(earlier.orderId, later.orderId),
        sku: WriteValue.overlay(earlier.sku, later.sku),
        label: WriteValue.overlay(earlier.label, later.label),
        quantity: WriteValue.overlay(earlier.quantity, later.quantity),
        unitPriceCents: WriteValue.overlay(
          earlier.unitPriceCents,
          later.unitPriceCents,
        ),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.OrderLine from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class OrderLineCreator {
  Future<models.OrderLine> call({
    required int orderId,
    required String sku,
    required String label,
    required int quantity,
    required int unitPriceCents,
  });
}

final class _OrderLineCreator implements OrderLineCreator {
  final OrderLineTableSet _table;
  const _OrderLineCreator(this._table);
  @override
  Future<models.OrderLine> call({
    required int orderId,
    required String sku,
    required String label,
    required int quantity,
    required int unitPriceCents,
  }) async => _table.plan
      .insert(
        OrderLineInsert._(
          orderId: .set(orderId),
          sku: .set(sku),
          label: .set(label),
          quantity: .set(quantity),
          unitPriceCents: .set(unitPriceCents),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class OrderLinePatcher {
  Future<int> call({
    int orderId,
    String sku,
    String label,
    int quantity,
    int unitPriceCents,
  });
}

final class _OrderLinePatcher implements OrderLinePatcher {
  final orm_model.ModelQuery<models.OrderLine, OrderLineFields, OrderLinePatch>
  _query;
  const _OrderLinePatcher(this._query);
  @override
  Future<int> call({
    Object? orderId = _writeAbsent,
    Object? sku = _writeAbsent,
    Object? label = _writeAbsent,
    Object? quantity = _writeAbsent,
    Object? unitPriceCents = _writeAbsent,
  }) => _query.update(
    OrderLinePatch._(
      orderId: _writeLiteral<int, OrderLineFields>(orderId),
      sku: _writeLiteral<String, OrderLineFields>(sku),
      label: _writeLiteral<String, OrderLineFields>(label),
      quantity: _writeLiteral<int, OrderLineFields>(quantity),
      unitPriceCents: _writeLiteral<int, OrderLineFields>(unitPriceCents),
    ),
  );
}

/// Named literal updates on a complete models.OrderLine query.
extension OrderLineWrites
    on orm_model.ModelQuery<models.OrderLine, OrderLineFields, OrderLinePatch> {
  /// Executes one update; omitted fields remain unchanged.
  OrderLinePatcher get patch => _OrderLinePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class OrderLineTableSet
    extends
        orm_model.ModelTable<
          models.OrderLine,
          OrderLineFields,
          OrderLineInsert,
          OrderLinePatch
        > {
  OrderLineTableSet(QueryContext db)
    : super(
        db,
        orderLineTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final OrderLineCreator create = _OrderLineCreator(this);

  orm_model.ModelQuery<models.OrderLine, OrderLineFields, OrderLinePatch> byId({
    required int orderId,
    required String sku,
  }) => where(
    (row) =>
        orm.allOf([row.orderId.eq(.value(orderId)), row.sku.eq(.value(sku))]),
  );
}

final _purchaseOrderId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _purchaseOrderCustomerId = Column<String>(
  "customer_id",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _purchaseOrderRequestKey = Column<String>(
  "request_key",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _purchaseOrderRequestPayload = Column<String>(
  "request_payload",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _purchaseOrderTotalCents = Column<int>(
  "total_cents",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _purchaseOrderNote = Column<String?>(
  "note",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _purchaseOrderPlacedAt = Column<DateTime>(
  "placed_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  clientDefault: DateTime.now,
);
final purchaseOrderSchema = TableSchema(
  "purchase_orders",
  columns: [
    _purchaseOrderId,
    _purchaseOrderCustomerId,
    _purchaseOrderRequestKey,
    _purchaseOrderRequestPayload,
    _purchaseOrderTotalCents,
    _purchaseOrderNote,
    _purchaseOrderPlacedAt,
  ],
  primaryKey: ["id"],
  uniqueKeys: [
    ["customer_id", "request_key"],
  ],
  indexes: [],
  checks: [
    CheckSchema.forDialects(
      "nonnegative_total",
      sqlite: "total_cents >= 0",
      postgres: "total_cents >= 0",
      mysql: "total_cents >= 0",
      mariadb: "total_cents >= 0",
    ),
  ],
  foreignKeys: [],
);

final class PurchaseOrderFields extends Fields {
  PurchaseOrderFields(super.table);
  late final id = column(_purchaseOrderId);
  late final customerId = column(_purchaseOrderCustomerId);
  late final requestKey = column(_purchaseOrderRequestKey);
  late final requestPayload = column(_purchaseOrderRequestPayload);
  late final totalCents = column(_purchaseOrderTotalCents);
  late final note = column(_purchaseOrderNote);
  late final placedAt = column(_purchaseOrderPlacedAt);
  Relation<models.OrderLine, OrderLineFields> get lines =>
      Relation(orderLineTable, parent: [id], child: (row) => [row.orderId]);
}

final purchaseOrderTable = Table<models.PurchaseOrder, PurchaseOrderFields>(
  purchaseOrderSchema,
  PurchaseOrderFields.new,
  (row) =>
      (
        (
          row.id,
          row.customerId,
          row.requestKey,
          row.requestPayload,
          row.totalCents,
        ).map(
          (id, customerId, requestKey, requestPayload, totalCents) => (
            id: id,
            customerId: customerId,
            requestKey: requestKey,
            requestPayload: requestPayload,
            totalCents: totalCents,
          ),
        ),
        (
          row.note,
          row.placedAt,
        ).map((note, placedAt) => (note: note, placedAt: placedAt)),
      ).map(
        (left, right) => models.PurchaseOrder(
          id: left.id,
          customerId: left.customerId,
          requestKey: left.requestKey,
          requestPayload: left.requestPayload,
          totalCents: left.totalCents,
          note: right.note,
          placedAt: right.placedAt,
        ),
      ),
);

/// Immutable input data; composition belongs to [purchaseOrderPatch], not field names.
final class PurchaseOrderPatch {
  final WriteValue<String, PurchaseOrderFields> customerId;
  final WriteValue<String, PurchaseOrderFields> requestKey;
  final WriteValue<String, PurchaseOrderFields> requestPayload;
  final WriteValue<int, PurchaseOrderFields> totalCents;
  final WriteValue<String?, PurchaseOrderFields> note;
  final WriteValue<DateTime, PurchaseOrderFields> placedAt;
  PurchaseOrderPatch._({
    required this.customerId,
    required this.requestKey,
    required this.requestPayload,
    required this.totalCents,
    required this.note,
    required this.placedAt,
  });

  List<Assignment> _assignments(PurchaseOrderFields fields) => [
    ...fields.customerId.write(customerId, fields),
    ...fields.requestKey.write(requestKey, fields),
    ...fields.requestPayload.write(requestPayload, fields),
    ...fields.totalCents.write(totalCents, fields),
    ...fields.note.write(note, fields),
    ...fields.placedAt.write(placedAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PurchaseOrderPatchFactory {
  PurchaseOrderPatch call({
    String customerId,
    String requestKey,
    String requestPayload,
    int totalCents,
    String? note,
    DateTime placedAt,
  });
  PurchaseOrderPatch values({
    WriteValue<String, PurchaseOrderFields> customerId = const .keep(),
    WriteValue<String, PurchaseOrderFields> requestKey = const .keep(),
    WriteValue<String, PurchaseOrderFields> requestPayload = const .keep(),
    WriteValue<int, PurchaseOrderFields> totalCents = const .keep(),
    WriteValue<String?, PurchaseOrderFields> note = const .keep(),
    WriteValue<DateTime, PurchaseOrderFields> placedAt = const .keep(),
  });
  PurchaseOrderPatch overlay(Iterable<PurchaseOrderPatch> layers);
  bool isEmpty(PurchaseOrderPatch input);
}

const PurchaseOrderPatchFactory purchaseOrderPatch =
    _PurchaseOrderPatchFactory();

final class _PurchaseOrderPatchFactory implements PurchaseOrderPatchFactory {
  const _PurchaseOrderPatchFactory();
  @override
  PurchaseOrderPatch call({
    Object? customerId = _writeAbsent,
    Object? requestKey = _writeAbsent,
    Object? requestPayload = _writeAbsent,
    Object? totalCents = _writeAbsent,
    Object? note = _writeAbsent,
    Object? placedAt = _writeAbsent,
  }) => PurchaseOrderPatch._(
    customerId: _writeLiteral<String, PurchaseOrderFields>(customerId),
    requestKey: _writeLiteral<String, PurchaseOrderFields>(requestKey),
    requestPayload: _writeLiteral<String, PurchaseOrderFields>(requestPayload),
    totalCents: _writeLiteral<int, PurchaseOrderFields>(totalCents),
    note: _writeLiteral<String?, PurchaseOrderFields>(note),
    placedAt: _writeLiteral<DateTime, PurchaseOrderFields>(placedAt),
  );
  @override
  PurchaseOrderPatch values({
    WriteValue<String, PurchaseOrderFields> customerId = const .keep(),
    WriteValue<String, PurchaseOrderFields> requestKey = const .keep(),
    WriteValue<String, PurchaseOrderFields> requestPayload = const .keep(),
    WriteValue<int, PurchaseOrderFields> totalCents = const .keep(),
    WriteValue<String?, PurchaseOrderFields> note = const .keep(),
    WriteValue<DateTime, PurchaseOrderFields> placedAt = const .keep(),
  }) => PurchaseOrderPatch._(
    customerId: customerId,
    requestKey: requestKey,
    requestPayload: requestPayload,
    totalCents: totalCents,
    note: note,
    placedAt: placedAt,
  );
  @override
  PurchaseOrderPatch overlay(Iterable<PurchaseOrderPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = PurchaseOrderPatch._(
        customerId: WriteValue.overlay(earlier.customerId, later.customerId),
        requestKey: WriteValue.overlay(earlier.requestKey, later.requestKey),
        requestPayload: WriteValue.overlay(
          earlier.requestPayload,
          later.requestPayload,
        ),
        totalCents: WriteValue.overlay(earlier.totalCents, later.totalCents),
        note: WriteValue.overlay(earlier.note, later.note),
        placedAt: WriteValue.overlay(earlier.placedAt, later.placedAt),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(PurchaseOrderPatch input) =>
      input.customerId.isMissing &&
      input.requestKey.isMissing &&
      input.requestPayload.isMissing &&
      input.totalCents.isMissing &&
      input.note.isMissing &&
      input.placedAt.isMissing;
}

/// Immutable input data; composition belongs to [purchaseOrderInsert], not field names.
final class PurchaseOrderInsert {
  final WriteValue<int, PurchaseOrderFields> id;
  final WriteValue<String, PurchaseOrderFields> customerId;
  final WriteValue<String, PurchaseOrderFields> requestKey;
  final WriteValue<String, PurchaseOrderFields> requestPayload;
  final WriteValue<int, PurchaseOrderFields> totalCents;
  final WriteValue<String?, PurchaseOrderFields> note;
  final WriteValue<DateTime, PurchaseOrderFields> placedAt;
  PurchaseOrderInsert._({
    required this.id,
    required this.customerId,
    required this.requestKey,
    required this.requestPayload,
    required this.totalCents,
    required this.note,
    required this.placedAt,
  }) {
    if (customerId.isMissing) {
      throw ArgumentError.value(customerId, 'customerId', 'Must be supplied.');
    }
    if (requestKey.isMissing) {
      throw ArgumentError.value(requestKey, 'requestKey', 'Must be supplied.');
    }
    if (requestPayload.isMissing) {
      throw ArgumentError.value(
        requestPayload,
        'requestPayload',
        'Must be supplied.',
      );
    }
    if (totalCents.isMissing) {
      throw ArgumentError.value(totalCents, 'totalCents', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(PurchaseOrderFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.customerId.write(customerId, fields),
    ...fields.requestKey.write(requestKey, fields),
    ...fields.requestPayload.write(requestPayload, fields),
    ...fields.totalCents.write(totalCents, fields),
    ...fields.note.write(note, fields),
    ...fields.placedAt.write(placedAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PurchaseOrderInsertFactory {
  PurchaseOrderInsert call({
    int id,
    required String customerId,
    required String requestKey,
    required String requestPayload,
    required int totalCents,
    String? note,
    DateTime placedAt,
  });
  PurchaseOrderInsert values({
    WriteValue<int, PurchaseOrderFields> id = const .keep(),
    required WriteValue<String, PurchaseOrderFields> customerId,
    required WriteValue<String, PurchaseOrderFields> requestKey,
    required WriteValue<String, PurchaseOrderFields> requestPayload,
    required WriteValue<int, PurchaseOrderFields> totalCents,
    WriteValue<String?, PurchaseOrderFields> note = const .keep(),
    WriteValue<DateTime, PurchaseOrderFields> placedAt = const .keep(),
  });
  PurchaseOrderInsert overlay(
    PurchaseOrderInsert earlier,
    Iterable<PurchaseOrderPatch> layers,
  );
}

const PurchaseOrderInsertFactory purchaseOrderInsert =
    _PurchaseOrderInsertFactory();

final class _PurchaseOrderInsertFactory implements PurchaseOrderInsertFactory {
  const _PurchaseOrderInsertFactory();
  @override
  PurchaseOrderInsert call({
    Object? id = _writeAbsent,
    required String customerId,
    required String requestKey,
    required String requestPayload,
    required int totalCents,
    Object? note = _writeAbsent,
    Object? placedAt = _writeAbsent,
  }) => PurchaseOrderInsert._(
    id: _writeLiteral<int, PurchaseOrderFields>(id),
    customerId: .set(customerId),
    requestKey: .set(requestKey),
    requestPayload: .set(requestPayload),
    totalCents: .set(totalCents),
    note: _writeLiteral<String?, PurchaseOrderFields>(note),
    placedAt: _writeLiteral<DateTime, PurchaseOrderFields>(placedAt),
  );
  @override
  PurchaseOrderInsert values({
    WriteValue<int, PurchaseOrderFields> id = const .keep(),
    required WriteValue<String, PurchaseOrderFields> customerId,
    required WriteValue<String, PurchaseOrderFields> requestKey,
    required WriteValue<String, PurchaseOrderFields> requestPayload,
    required WriteValue<int, PurchaseOrderFields> totalCents,
    WriteValue<String?, PurchaseOrderFields> note = const .keep(),
    WriteValue<DateTime, PurchaseOrderFields> placedAt = const .keep(),
  }) => PurchaseOrderInsert._(
    id: id,
    customerId: customerId,
    requestKey: requestKey,
    requestPayload: requestPayload,
    totalCents: totalCents,
    note: note,
    placedAt: placedAt,
  );
  @override
  PurchaseOrderInsert overlay(
    PurchaseOrderInsert earlier,
    Iterable<PurchaseOrderPatch> layers,
  ) {
    for (final later in layers) {
      earlier = PurchaseOrderInsert._(
        id: earlier.id,
        customerId: WriteValue.overlay(earlier.customerId, later.customerId),
        requestKey: WriteValue.overlay(earlier.requestKey, later.requestKey),
        requestPayload: WriteValue.overlay(
          earlier.requestPayload,
          later.requestPayload,
        ),
        totalCents: WriteValue.overlay(earlier.totalCents, later.totalCents),
        note: WriteValue.overlay(earlier.note, later.note),
        placedAt: WriteValue.overlay(earlier.placedAt, later.placedAt),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.PurchaseOrder from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class PurchaseOrderCreator {
  Future<models.PurchaseOrder> call({
    int id,
    required String customerId,
    required String requestKey,
    required String requestPayload,
    required int totalCents,
    String? note,
    DateTime placedAt,
  });
}

final class _PurchaseOrderCreator implements PurchaseOrderCreator {
  final PurchaseOrderTableSet _table;
  const _PurchaseOrderCreator(this._table);
  @override
  Future<models.PurchaseOrder> call({
    Object? id = _writeAbsent,
    required String customerId,
    required String requestKey,
    required String requestPayload,
    required int totalCents,
    Object? note = _writeAbsent,
    Object? placedAt = _writeAbsent,
  }) async => _table.plan
      .insert(
        PurchaseOrderInsert._(
          id: _writeLiteral<int, PurchaseOrderFields>(id),
          customerId: .set(customerId),
          requestKey: .set(requestKey),
          requestPayload: .set(requestPayload),
          totalCents: .set(totalCents),
          note: _writeLiteral<String?, PurchaseOrderFields>(note),
          placedAt: _writeLiteral<DateTime, PurchaseOrderFields>(placedAt),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class PurchaseOrderPatcher {
  Future<int> call({
    String customerId,
    String requestKey,
    String requestPayload,
    int totalCents,
    String? note,
    DateTime placedAt,
  });
}

final class _PurchaseOrderPatcher implements PurchaseOrderPatcher {
  final orm_model.ModelQuery<
    models.PurchaseOrder,
    PurchaseOrderFields,
    PurchaseOrderPatch
  >
  _query;
  const _PurchaseOrderPatcher(this._query);
  @override
  Future<int> call({
    Object? customerId = _writeAbsent,
    Object? requestKey = _writeAbsent,
    Object? requestPayload = _writeAbsent,
    Object? totalCents = _writeAbsent,
    Object? note = _writeAbsent,
    Object? placedAt = _writeAbsent,
  }) => _query.update(
    PurchaseOrderPatch._(
      customerId: _writeLiteral<String, PurchaseOrderFields>(customerId),
      requestKey: _writeLiteral<String, PurchaseOrderFields>(requestKey),
      requestPayload: _writeLiteral<String, PurchaseOrderFields>(
        requestPayload,
      ),
      totalCents: _writeLiteral<int, PurchaseOrderFields>(totalCents),
      note: _writeLiteral<String?, PurchaseOrderFields>(note),
      placedAt: _writeLiteral<DateTime, PurchaseOrderFields>(placedAt),
    ),
  );
}

/// Named literal updates on a complete models.PurchaseOrder query.
extension PurchaseOrderWrites
    on
        orm_model.ModelQuery<
          models.PurchaseOrder,
          PurchaseOrderFields,
          PurchaseOrderPatch
        > {
  /// Executes one update; omitted fields remain unchanged.
  PurchaseOrderPatcher get patch => _PurchaseOrderPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class PurchaseOrderTableSet
    extends
        orm_model.ModelTable<
          models.PurchaseOrder,
          PurchaseOrderFields,
          PurchaseOrderInsert,
          PurchaseOrderPatch
        > {
  PurchaseOrderTableSet(QueryContext db)
    : super(
        db,
        purchaseOrderTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final PurchaseOrderCreator create = _PurchaseOrderCreator(this);

  orm_model.ModelQuery<
    models.PurchaseOrder,
    PurchaseOrderFields,
    PurchaseOrderPatch
  >
  byId(int id) => where((row) => row.id.eq(.value(id)));
}

final _orderItemSlot0 = orm_projection.Slot<String>("sku");
final _orderItemSlot1 = orm_projection.Slot<String>("label");
final _orderItemSlot2 = orm_projection.Slot<int>("quantity");
final _orderItemSlot3 = orm_projection.Slot<int>("unitPriceCents");

final class OrderItemFields extends orm_projection.ProjectionOutput {
  OrderItemFields._(orm_projection.ProjectionFields fields)
    : sku = fields.read(_orderItemSlot0),
      label = fields.read(_orderItemSlot1),
      quantity = fields.read(_orderItemSlot2),
      unitPriceCents = fields.read(_orderItemSlot3),
      super(fields.table);
  final Expr<String> sku;
  final Expr<String> label;
  final Expr<int> quantity;
  final Expr<int> unitPriceCents;
}

final _orderItemProjection =
    orm_projection.ProjectionType<types0.OrderItem, OrderItemFields>(
      slots: [
        _orderItemSlot0,
        _orderItemSlot1,
        _orderItemSlot2,
        _orderItemSlot3,
      ],
      assemble: (values) => types0.OrderItem(
        sku: values[0] as String,
        label: values[1] as String,
        quantity: values[2] as int,
        unitPriceCents: values[3] as int,
      ),
      fields: OrderItemFields._,
    );
const orderItem = _OrderItemSelectionFactory();

/// Named result binding; .sql explicitly requires scalar SQL expressions.
final class _OrderItemSelectionFactory {
  const _OrderItemSelectionFactory();
  Selection<types0.OrderItem> call({
    required Selection<String> sku,
    required Selection<String> label,
    required Selection<int> quantity,
    required Selection<int> unitPriceCents,
  }) => (sku, label, quantity, unitPriceCents)
      .map(
        (v0, v1, v2, v3) =>
            (sku: v0, label: v1, quantity: v2, unitPriceCents: v3),
      )
      .map(
        (result) => types0.OrderItem(
          sku: result.sku,
          label: result.label,
          quantity: result.quantity,
          unitPriceCents: result.unitPriceCents,
        ),
      );
  orm_projection.Projection<types0.OrderItem, OrderItemFields> sql({
    required Expr<String> sku,
    required Expr<String> label,
    required Expr<int> quantity,
    required Expr<int> unitPriceCents,
  }) => _orderItemProjection.bind([
    _orderItemSlot0.bind(sku),
    _orderItemSlot1.bind(label),
    _orderItemSlot2.bind(quantity),
    _orderItemSlot3.bind(unitPriceCents),
  ]);
}

final _orderReceiptSlot0 = orm_projection.Slot<int>("id");
final _orderReceiptSlot1 = orm_projection.Slot<String>("customerId");
final _orderReceiptSlot2 = orm_projection.Slot<String>("requestKey");
final _orderReceiptSlot3 = orm_projection.Slot<int>("totalCents");
final _orderReceiptSlot4 = orm_projection.Slot<String?>("note");
final _orderReceiptSlot5 = orm_projection.Slot<DateTime>("placedAt");
final _orderReceiptSlot6 = orm_projection.Slot<List<types0.OrderItem>>("items");

final class OrderReceiptFields extends orm_projection.ProjectionOutput {
  OrderReceiptFields._(orm_projection.ProjectionFields fields)
    : id = fields.read(_orderReceiptSlot0),
      customerId = fields.read(_orderReceiptSlot1),
      requestKey = fields.read(_orderReceiptSlot2),
      totalCents = fields.read(_orderReceiptSlot3),
      note = fields.read(_orderReceiptSlot4),
      placedAt = fields.read(_orderReceiptSlot5),
      items = fields.read(_orderReceiptSlot6),
      super(fields.table);
  final Expr<int> id;
  final Expr<String> customerId;
  final Expr<String> requestKey;
  final Expr<int> totalCents;
  final Expr<String?> note;
  final Expr<DateTime> placedAt;
  final Expr<List<types0.OrderItem>> items;
}

final _orderReceiptProjection =
    orm_projection.ProjectionType<types0.OrderReceipt, OrderReceiptFields>(
      slots: [
        _orderReceiptSlot0,
        _orderReceiptSlot1,
        _orderReceiptSlot2,
        _orderReceiptSlot3,
        _orderReceiptSlot4,
        _orderReceiptSlot5,
        _orderReceiptSlot6,
      ],
      assemble: (values) => types0.OrderReceipt(
        id: values[0] as int,
        customerId: values[1] as String,
        requestKey: values[2] as String,
        totalCents: values[3] as int,
        note: values[4] as String?,
        placedAt: values[5] as DateTime,
        items: values[6] as List<types0.OrderItem>,
      ),
      fields: OrderReceiptFields._,
    );
const orderReceipt = _OrderReceiptSelectionFactory();

/// Named result binding; .sql explicitly requires scalar SQL expressions.
final class _OrderReceiptSelectionFactory {
  const _OrderReceiptSelectionFactory();
  Selection<types0.OrderReceipt> call({
    required Selection<int> id,
    required Selection<String> customerId,
    required Selection<String> requestKey,
    required Selection<int> totalCents,
    required Selection<String?> note,
    required Selection<DateTime> placedAt,
    required Selection<List<types0.OrderItem>> items,
  }) =>
      (
            (id, customerId, requestKey, totalCents, note).map(
              (v0, v1, v2, v3, v4) => (
                id: v0,
                customerId: v1,
                requestKey: v2,
                totalCents: v3,
                note: v4,
              ),
            ),
            (placedAt, items).map((v0, v1) => (placedAt: v0, items: v1)),
          )
          .map(
            (left, right) => (
              id: left.id,
              customerId: left.customerId,
              requestKey: left.requestKey,
              totalCents: left.totalCents,
              note: left.note,
              placedAt: right.placedAt,
              items: right.items,
            ),
          )
          .map(
            (result) => types0.OrderReceipt(
              id: result.id,
              customerId: result.customerId,
              requestKey: result.requestKey,
              totalCents: result.totalCents,
              note: result.note,
              placedAt: result.placedAt,
              items: result.items,
            ),
          );
  orm_projection.Projection<types0.OrderReceipt, OrderReceiptFields> sql({
    required Expr<int> id,
    required Expr<String> customerId,
    required Expr<String> requestKey,
    required Expr<int> totalCents,
    required Expr<String?> note,
    required Expr<DateTime> placedAt,
    required Expr<List<types0.OrderItem>> items,
  }) => _orderReceiptProjection.bind([
    _orderReceiptSlot0.bind(id),
    _orderReceiptSlot1.bind(customerId),
    _orderReceiptSlot2.bind(requestKey),
    _orderReceiptSlot3.bind(totalCents),
    _orderReceiptSlot4.bind(note),
    _orderReceiptSlot5.bind(placedAt),
    _orderReceiptSlot6.bind(items),
  ]);
}

final appSchema = List<TableSchema>.unmodifiable([
  inventorySchema,
  orderLineSchema,
  purchaseOrderSchema,
]);

extension AppTables on QueryContext {
  InventoryTableSet get inventory => InventoryTableSet(this);
  OrderLineTableSet get orderLine => OrderLineTableSet(this);
  PurchaseOrderTableSet get purchaseOrder => PurchaseOrderTableSet(this);
}
