// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Wallet, Price, Receipt;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _priceId = Column<Decimal>(
  "id",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 4,
  decimalScale: 2,
);
final _priceLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final priceSchema = TableSchema(
  "prices",
  columns: [_priceId, _priceLabel],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class PriceFields extends Fields {
  PriceFields(super.table);
  late final id = column(_priceId);
  late final label = column(_priceLabel);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Receipt, ReceiptFields> get receipts =>
      Relation(receiptTable, parent: [id], child: (row) => [row.priceId]);
}

final priceTable = Table<models.Price, PriceFields>(
  priceSchema,
  PriceFields.new,
  (row) => (row.id, row.label).map((v0, v1) => models.Price(id: v0, label: v1)),
);

/// Immutable input data; composition belongs to [pricePatch], not field names.
final class PricePatch {
  final WriteValue<Decimal, PriceFields> id;
  final WriteValue<String, PriceFields> label;
  PricePatch._({required this.id, required this.label});

  List<Assignment> _assignments(PriceFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PricePatchFactory {
  PricePatch call({Decimal id, String label});
  PricePatch values({
    WriteValue<Decimal, PriceFields> id = const .keep(),
    WriteValue<String, PriceFields> label = const .keep(),
  });
  PricePatch overlay(Iterable<PricePatch> layers);
  bool isEmpty(PricePatch input);
}

const PricePatchFactory pricePatch = _PricePatchFactory();

final class _PricePatchFactory implements PricePatchFactory {
  const _PricePatchFactory();
  @override
  PricePatch call({Object? id = _writeAbsent, Object? label = _writeAbsent}) =>
      PricePatch._(
        id: _writeLiteral<Decimal, PriceFields>(id),
        label: _writeLiteral<String, PriceFields>(label),
      );
  @override
  PricePatch values({
    WriteValue<Decimal, PriceFields> id = const .keep(),
    WriteValue<String, PriceFields> label = const .keep(),
  }) => PricePatch._(id: id, label: label);
  @override
  PricePatch overlay(Iterable<PricePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = PricePatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(PricePatch input) => input.id.isMissing && input.label.isMissing;
}

/// Immutable input data; composition belongs to [priceInsert], not field names.
final class PriceInsert {
  final WriteValue<Decimal, PriceFields> id;
  final WriteValue<String, PriceFields> label;
  PriceInsert._({required this.id, required this.label}) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (label.isMissing) {
      throw ArgumentError.value(label, 'label', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(PriceFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PriceInsertFactory {
  PriceInsert call({required Decimal id, required String label});
  PriceInsert values({
    required WriteValue<Decimal, PriceFields> id,
    required WriteValue<String, PriceFields> label,
  });
  PriceInsert overlay(PriceInsert earlier, Iterable<PricePatch> layers);
}

const PriceInsertFactory priceInsert = _PriceInsertFactory();

final class _PriceInsertFactory implements PriceInsertFactory {
  const _PriceInsertFactory();
  @override
  PriceInsert call({required Decimal id, required String label}) =>
      PriceInsert._(id: .set(id), label: .set(label));
  @override
  PriceInsert values({
    required WriteValue<Decimal, PriceFields> id,
    required WriteValue<String, PriceFields> label,
  }) => PriceInsert._(id: id, label: label);
  @override
  PriceInsert overlay(PriceInsert earlier, Iterable<PricePatch> layers) {
    for (final later in layers) {
      earlier = PriceInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Price from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class PriceCreator {
  Future<models.Price> call({required Decimal id, required String label});
}

final class _PriceCreator implements PriceCreator {
  final PriceTableSet _table;
  const _PriceCreator(this._table);
  @override
  Future<models.Price> call({
    required Decimal id,
    required String label,
  }) async =>
      _table.plan.insert(PriceInsert._(id: .set(id), label: .set(label))).row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class PricePatcher {
  Future<int> call({Decimal id, String label});
}

final class _PricePatcher implements PricePatcher {
  final orm_model.ModelQuery<models.Price, PriceFields, PricePatch> _query;
  const _PricePatcher(this._query);
  @override
  Future<int> call({Object? id = _writeAbsent, Object? label = _writeAbsent}) =>
      _query.update(
        PricePatch._(
          id: _writeLiteral<Decimal, PriceFields>(id),
          label: _writeLiteral<String, PriceFields>(label),
        ),
      );
}

/// Named literal updates on a complete models.Price query.
extension PriceWrites
    on orm_model.ModelQuery<models.Price, PriceFields, PricePatch> {
  /// Executes one update; omitted fields remain unchanged.
  PricePatcher get patch => _PricePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class PriceTableSet
    extends
        orm_model.ModelTable<
          models.Price,
          PriceFields,
          PriceInsert,
          PricePatch
        > {
  PriceTableSet(QueryContext db)
    : super(
        db,
        priceTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final PriceCreator create = _PriceCreator(this);

  orm_model.ModelQuery<models.Price, PriceFields, PricePatch> byId(
    Decimal id,
  ) => where((row) => row.id.eq(.value(id)));
}

final _receiptId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _receiptPriceId = Column<Decimal>(
  "price_id",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 4,
  decimalScale: 2,
);
final receiptSchema = TableSchema(
  "receipts",
  columns: [_receiptId, _receiptPriceId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["price_id"], "prices", ["id"], onDelete: "RESTRICT"),
  ],
);

final class ReceiptFields extends Fields {
  ReceiptFields(super.table);
  late final id = column(_receiptId);
  late final priceId = column(_receiptPriceId);
  Relation<models.Price, PriceFields> get price =>
      Relation(priceTable, parent: [priceId], child: (row) => [row.id]);
}

final receiptTable = Table<models.Receipt, ReceiptFields>(
  receiptSchema,
  ReceiptFields.new,
  (row) => (
    row.id,
    row.priceId,
  ).map((v0, v1) => models.Receipt(id: v0, priceId: v1)),
);

/// Immutable input data; composition belongs to [receiptPatch], not field names.
final class ReceiptPatch {
  final WriteValue<Decimal, ReceiptFields> priceId;
  ReceiptPatch._({required this.priceId});

  List<Assignment> _assignments(ReceiptFields fields) => [
    ...fields.priceId.write(priceId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ReceiptPatchFactory {
  ReceiptPatch call({Decimal priceId});
  ReceiptPatch values({
    WriteValue<Decimal, ReceiptFields> priceId = const .keep(),
  });
  ReceiptPatch overlay(Iterable<ReceiptPatch> layers);
  bool isEmpty(ReceiptPatch input);
}

const ReceiptPatchFactory receiptPatch = _ReceiptPatchFactory();

final class _ReceiptPatchFactory implements ReceiptPatchFactory {
  const _ReceiptPatchFactory();
  @override
  ReceiptPatch call({Object? priceId = _writeAbsent}) =>
      ReceiptPatch._(priceId: _writeLiteral<Decimal, ReceiptFields>(priceId));
  @override
  ReceiptPatch values({
    WriteValue<Decimal, ReceiptFields> priceId = const .keep(),
  }) => ReceiptPatch._(priceId: priceId);
  @override
  ReceiptPatch overlay(Iterable<ReceiptPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = ReceiptPatch._(
        priceId: WriteValue.overlay(earlier.priceId, later.priceId),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(ReceiptPatch input) => input.priceId.isMissing;
}

/// Immutable input data; composition belongs to [receiptInsert], not field names.
final class ReceiptInsert {
  final WriteValue<int, ReceiptFields> id;
  final WriteValue<Decimal, ReceiptFields> priceId;
  ReceiptInsert._({required this.id, required this.priceId}) {
    if (priceId.isMissing) {
      throw ArgumentError.value(priceId, 'priceId', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(ReceiptFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.priceId.write(priceId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ReceiptInsertFactory {
  ReceiptInsert call({int id, required Decimal priceId});
  ReceiptInsert values({
    WriteValue<int, ReceiptFields> id = const .keep(),
    required WriteValue<Decimal, ReceiptFields> priceId,
  });
  ReceiptInsert overlay(ReceiptInsert earlier, Iterable<ReceiptPatch> layers);
}

const ReceiptInsertFactory receiptInsert = _ReceiptInsertFactory();

final class _ReceiptInsertFactory implements ReceiptInsertFactory {
  const _ReceiptInsertFactory();
  @override
  ReceiptInsert call({Object? id = _writeAbsent, required Decimal priceId}) =>
      ReceiptInsert._(
        id: _writeLiteral<int, ReceiptFields>(id),
        priceId: .set(priceId),
      );
  @override
  ReceiptInsert values({
    WriteValue<int, ReceiptFields> id = const .keep(),
    required WriteValue<Decimal, ReceiptFields> priceId,
  }) => ReceiptInsert._(id: id, priceId: priceId);
  @override
  ReceiptInsert overlay(ReceiptInsert earlier, Iterable<ReceiptPatch> layers) {
    for (final later in layers) {
      earlier = ReceiptInsert._(
        id: earlier.id,
        priceId: WriteValue.overlay(earlier.priceId, later.priceId),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Receipt from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class ReceiptCreator {
  Future<models.Receipt> call({int id, required Decimal priceId});
}

final class _ReceiptCreator implements ReceiptCreator {
  final ReceiptTableSet _table;
  const _ReceiptCreator(this._table);
  @override
  Future<models.Receipt> call({
    Object? id = _writeAbsent,
    required Decimal priceId,
  }) async => _table.plan
      .insert(
        ReceiptInsert._(
          id: _writeLiteral<int, ReceiptFields>(id),
          priceId: .set(priceId),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class ReceiptPatcher {
  Future<int> call({Decimal priceId});
}

final class _ReceiptPatcher implements ReceiptPatcher {
  final orm_model.ModelQuery<models.Receipt, ReceiptFields, ReceiptPatch>
  _query;
  const _ReceiptPatcher(this._query);
  @override
  Future<int> call({Object? priceId = _writeAbsent}) => _query.update(
    ReceiptPatch._(priceId: _writeLiteral<Decimal, ReceiptFields>(priceId)),
  );
}

/// Named literal updates on a complete models.Receipt query.
extension ReceiptWrites
    on orm_model.ModelQuery<models.Receipt, ReceiptFields, ReceiptPatch> {
  /// Executes one update; omitted fields remain unchanged.
  ReceiptPatcher get patch => _ReceiptPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class ReceiptTableSet
    extends
        orm_model.ModelTable<
          models.Receipt,
          ReceiptFields,
          ReceiptInsert,
          ReceiptPatch
        > {
  ReceiptTableSet(QueryContext db)
    : super(
        db,
        receiptTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final ReceiptCreator create = _ReceiptCreator(this);

  orm_model.ModelQuery<models.Receipt, ReceiptFields, ReceiptPatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
}

final _walletId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _walletAmount = Column<Decimal>(
  "amount",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 5,
  decimalScale: 2,
);
final _walletHundreds = Column<Decimal>(
  "hundreds",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 3,
  decimalScale: -2,
);
final _walletFraction = Column<Decimal>(
  "fraction",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 3,
  decimalScale: 5,
);
final _walletDefaulted = Column<Decimal>(
  "defaulted",
  Codecs.decimal,
  nullable: false,
  generated: false,
  defaultSql: "'1.235'",
  decimalPrecision: 5,
  decimalScale: 2,
);
final _walletOptional = Column<Decimal?>(
  "optional",
  Codecs.decimal.nullable(),
  nullable: true,
  generated: false,
  decimalPrecision: 5,
  decimalScale: 2,
);
final walletSchema = TableSchema(
  "wallets",
  columns: [
    _walletId,
    _walletAmount,
    _walletHundreds,
    _walletFraction,
    _walletDefaulted,
    _walletOptional,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class WalletFields extends Fields {
  WalletFields(super.table);
  late final id = column(_walletId);
  late final amount = column(_walletAmount);
  late final hundreds = column(_walletHundreds);
  late final fraction = column(_walletFraction);
  late final defaulted = column(_walletDefaulted);
  late final optional = column(_walletOptional);
}

final walletTable = Table<models.Wallet, WalletFields>(
  walletSchema,
  WalletFields.new,
  (row) =>
      (
        row.id,
        row.amount,
        row.hundreds,
        row.fraction,
        row.defaulted,
        row.optional,
      ).map(
        (v0, v1, v2, v3, v4, v5) => models.Wallet(
          id: v0,
          amount: v1,
          hundreds: v2,
          fraction: v3,
          defaulted: v4,
          optional: v5,
        ),
      ),
);

/// Immutable input data; composition belongs to [walletPatch], not field names.
final class WalletPatch {
  final WriteValue<Decimal, WalletFields> amount;
  final WriteValue<Decimal, WalletFields> hundreds;
  final WriteValue<Decimal, WalletFields> fraction;
  final WriteValue<Decimal, WalletFields> defaulted;
  final WriteValue<Decimal?, WalletFields> optional;
  WalletPatch._({
    required this.amount,
    required this.hundreds,
    required this.fraction,
    required this.defaulted,
    required this.optional,
  });

  List<Assignment> _assignments(WalletFields fields) => [
    ...fields.amount.write(amount, fields),
    ...fields.hundreds.write(hundreds, fields),
    ...fields.fraction.write(fraction, fields),
    ...fields.defaulted.write(defaulted, fields),
    ...fields.optional.write(optional, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class WalletPatchFactory {
  WalletPatch call({
    Decimal amount,
    Decimal hundreds,
    Decimal fraction,
    Decimal defaulted,
    Decimal? optional,
  });
  WalletPatch values({
    WriteValue<Decimal, WalletFields> amount = const .keep(),
    WriteValue<Decimal, WalletFields> hundreds = const .keep(),
    WriteValue<Decimal, WalletFields> fraction = const .keep(),
    WriteValue<Decimal, WalletFields> defaulted = const .keep(),
    WriteValue<Decimal?, WalletFields> optional = const .keep(),
  });
  WalletPatch overlay(Iterable<WalletPatch> layers);
  bool isEmpty(WalletPatch input);
}

const WalletPatchFactory walletPatch = _WalletPatchFactory();

final class _WalletPatchFactory implements WalletPatchFactory {
  const _WalletPatchFactory();
  @override
  WalletPatch call({
    Object? amount = _writeAbsent,
    Object? hundreds = _writeAbsent,
    Object? fraction = _writeAbsent,
    Object? defaulted = _writeAbsent,
    Object? optional = _writeAbsent,
  }) => WalletPatch._(
    amount: _writeLiteral<Decimal, WalletFields>(amount),
    hundreds: _writeLiteral<Decimal, WalletFields>(hundreds),
    fraction: _writeLiteral<Decimal, WalletFields>(fraction),
    defaulted: _writeLiteral<Decimal, WalletFields>(defaulted),
    optional: _writeLiteral<Decimal?, WalletFields>(optional),
  );
  @override
  WalletPatch values({
    WriteValue<Decimal, WalletFields> amount = const .keep(),
    WriteValue<Decimal, WalletFields> hundreds = const .keep(),
    WriteValue<Decimal, WalletFields> fraction = const .keep(),
    WriteValue<Decimal, WalletFields> defaulted = const .keep(),
    WriteValue<Decimal?, WalletFields> optional = const .keep(),
  }) => WalletPatch._(
    amount: amount,
    hundreds: hundreds,
    fraction: fraction,
    defaulted: defaulted,
    optional: optional,
  );
  @override
  WalletPatch overlay(Iterable<WalletPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = WalletPatch._(
        amount: WriteValue.overlay(earlier.amount, later.amount),
        hundreds: WriteValue.overlay(earlier.hundreds, later.hundreds),
        fraction: WriteValue.overlay(earlier.fraction, later.fraction),
        defaulted: WriteValue.overlay(earlier.defaulted, later.defaulted),
        optional: WriteValue.overlay(earlier.optional, later.optional),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(WalletPatch input) =>
      input.amount.isMissing &&
      input.hundreds.isMissing &&
      input.fraction.isMissing &&
      input.defaulted.isMissing &&
      input.optional.isMissing;
}

/// Immutable input data; composition belongs to [walletInsert], not field names.
final class WalletInsert {
  final WriteValue<int, WalletFields> id;
  final WriteValue<Decimal, WalletFields> amount;
  final WriteValue<Decimal, WalletFields> hundreds;
  final WriteValue<Decimal, WalletFields> fraction;
  final WriteValue<Decimal, WalletFields> defaulted;
  final WriteValue<Decimal?, WalletFields> optional;
  WalletInsert._({
    required this.id,
    required this.amount,
    required this.hundreds,
    required this.fraction,
    required this.defaulted,
    required this.optional,
  }) {
    if (amount.isMissing) {
      throw ArgumentError.value(amount, 'amount', 'Must be supplied.');
    }
    if (hundreds.isMissing) {
      throw ArgumentError.value(hundreds, 'hundreds', 'Must be supplied.');
    }
    if (fraction.isMissing) {
      throw ArgumentError.value(fraction, 'fraction', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(WalletFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.amount.write(amount, fields),
    ...fields.hundreds.write(hundreds, fields),
    ...fields.fraction.write(fraction, fields),
    ...fields.defaulted.write(defaulted, fields),
    ...fields.optional.write(optional, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class WalletInsertFactory {
  WalletInsert call({
    int id,
    required Decimal amount,
    required Decimal hundreds,
    required Decimal fraction,
    Decimal defaulted,
    Decimal? optional,
  });
  WalletInsert values({
    WriteValue<int, WalletFields> id = const .keep(),
    required WriteValue<Decimal, WalletFields> amount,
    required WriteValue<Decimal, WalletFields> hundreds,
    required WriteValue<Decimal, WalletFields> fraction,
    WriteValue<Decimal, WalletFields> defaulted = const .keep(),
    WriteValue<Decimal?, WalletFields> optional = const .keep(),
  });
  WalletInsert overlay(WalletInsert earlier, Iterable<WalletPatch> layers);
}

const WalletInsertFactory walletInsert = _WalletInsertFactory();

final class _WalletInsertFactory implements WalletInsertFactory {
  const _WalletInsertFactory();
  @override
  WalletInsert call({
    Object? id = _writeAbsent,
    required Decimal amount,
    required Decimal hundreds,
    required Decimal fraction,
    Object? defaulted = _writeAbsent,
    Object? optional = _writeAbsent,
  }) => WalletInsert._(
    id: _writeLiteral<int, WalletFields>(id),
    amount: .set(amount),
    hundreds: .set(hundreds),
    fraction: .set(fraction),
    defaulted: _writeLiteral<Decimal, WalletFields>(defaulted),
    optional: _writeLiteral<Decimal?, WalletFields>(optional),
  );
  @override
  WalletInsert values({
    WriteValue<int, WalletFields> id = const .keep(),
    required WriteValue<Decimal, WalletFields> amount,
    required WriteValue<Decimal, WalletFields> hundreds,
    required WriteValue<Decimal, WalletFields> fraction,
    WriteValue<Decimal, WalletFields> defaulted = const .keep(),
    WriteValue<Decimal?, WalletFields> optional = const .keep(),
  }) => WalletInsert._(
    id: id,
    amount: amount,
    hundreds: hundreds,
    fraction: fraction,
    defaulted: defaulted,
    optional: optional,
  );
  @override
  WalletInsert overlay(WalletInsert earlier, Iterable<WalletPatch> layers) {
    for (final later in layers) {
      earlier = WalletInsert._(
        id: earlier.id,
        amount: WriteValue.overlay(earlier.amount, later.amount),
        hundreds: WriteValue.overlay(earlier.hundreds, later.hundreds),
        fraction: WriteValue.overlay(earlier.fraction, later.fraction),
        defaulted: WriteValue.overlay(earlier.defaulted, later.defaulted),
        optional: WriteValue.overlay(earlier.optional, later.optional),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Wallet from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class WalletCreator {
  Future<models.Wallet> call({
    int id,
    required Decimal amount,
    required Decimal hundreds,
    required Decimal fraction,
    Decimal defaulted,
    Decimal? optional,
  });
}

final class _WalletCreator implements WalletCreator {
  final WalletTableSet _table;
  const _WalletCreator(this._table);
  @override
  Future<models.Wallet> call({
    Object? id = _writeAbsent,
    required Decimal amount,
    required Decimal hundreds,
    required Decimal fraction,
    Object? defaulted = _writeAbsent,
    Object? optional = _writeAbsent,
  }) async => _table.plan
      .insert(
        WalletInsert._(
          id: _writeLiteral<int, WalletFields>(id),
          amount: .set(amount),
          hundreds: .set(hundreds),
          fraction: .set(fraction),
          defaulted: _writeLiteral<Decimal, WalletFields>(defaulted),
          optional: _writeLiteral<Decimal?, WalletFields>(optional),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class WalletPatcher {
  Future<int> call({
    Decimal amount,
    Decimal hundreds,
    Decimal fraction,
    Decimal defaulted,
    Decimal? optional,
  });
}

final class _WalletPatcher implements WalletPatcher {
  final orm_model.ModelQuery<models.Wallet, WalletFields, WalletPatch> _query;
  const _WalletPatcher(this._query);
  @override
  Future<int> call({
    Object? amount = _writeAbsent,
    Object? hundreds = _writeAbsent,
    Object? fraction = _writeAbsent,
    Object? defaulted = _writeAbsent,
    Object? optional = _writeAbsent,
  }) => _query.update(
    WalletPatch._(
      amount: _writeLiteral<Decimal, WalletFields>(amount),
      hundreds: _writeLiteral<Decimal, WalletFields>(hundreds),
      fraction: _writeLiteral<Decimal, WalletFields>(fraction),
      defaulted: _writeLiteral<Decimal, WalletFields>(defaulted),
      optional: _writeLiteral<Decimal?, WalletFields>(optional),
    ),
  );
}

/// Named literal updates on a complete models.Wallet query.
extension WalletWrites
    on orm_model.ModelQuery<models.Wallet, WalletFields, WalletPatch> {
  /// Executes one update; omitted fields remain unchanged.
  WalletPatcher get patch => _WalletPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class WalletTableSet
    extends
        orm_model.ModelTable<
          models.Wallet,
          WalletFields,
          WalletInsert,
          WalletPatch
        > {
  WalletTableSet(QueryContext db)
    : super(
        db,
        walletTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final WalletCreator create = _WalletCreator(this);

  orm_model.ModelQuery<models.Wallet, WalletFields, WalletPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([
  priceSchema,
  receiptSchema,
  walletSchema,
]);

extension AppTables on QueryContext {
  PriceTableSet get price => PriceTableSet(this);
  ReceiptTableSet get receipt => ReceiptTableSet(this);
  WalletTableSet get wallet => WalletTableSet(this);
}
