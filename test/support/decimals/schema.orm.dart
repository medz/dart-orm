// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show Entry, Rate, Allocation;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _allocationId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _allocationRateId = Column<Decimal>(
  "rate_id",
  Codecs.decimal,
  nullable: false,
  generated: false,
);
final allocationSchema = TableSchema(
  "allocations",
  columns: [_allocationId, _allocationRateId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["rate_id"], "rates", ["id"], onDelete: "RESTRICT"),
  ],
);

final class AllocationFields extends Fields {
  AllocationFields(super.table);
  late final id = column(_allocationId);
  late final rateId = column(_allocationRateId);
  Relation<models.Rate, RateFields> get rate =>
      Relation(rateTable, parent: [rateId], child: (row) => [row.id]);
}

final allocationTable = Table<models.Allocation, AllocationFields>(
  allocationSchema,
  AllocationFields.new,
  (row) => (
    row.id,
    row.rateId,
  ).map((v0, v1) => models.Allocation(id: v0, rateId: v1)),
);

/// Immutable input data; composition belongs to [allocationPatch], not field names.
final class AllocationPatch {
  final WriteValue<Decimal, AllocationFields> rateId;
  AllocationPatch._({required this.rateId});

  List<Assignment> _assignments(AllocationFields fields) => [
    ...fields.rateId.write(rateId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AllocationPatchFactory {
  AllocationPatch call({Decimal rateId});
  AllocationPatch values({
    WriteValue<Decimal, AllocationFields> rateId = const .keep(),
  });
  AllocationPatch overlay(Iterable<AllocationPatch> layers);
  bool isEmpty(AllocationPatch input);
}

const AllocationPatchFactory allocationPatch = _AllocationPatchFactory();

final class _AllocationPatchFactory implements AllocationPatchFactory {
  const _AllocationPatchFactory();
  @override
  AllocationPatch call({Object? rateId = _writeAbsent}) => AllocationPatch._(
    rateId: _writeLiteral<Decimal, AllocationFields>(rateId),
  );
  @override
  AllocationPatch values({
    WriteValue<Decimal, AllocationFields> rateId = const .keep(),
  }) => AllocationPatch._(rateId: rateId);
  @override
  AllocationPatch overlay(Iterable<AllocationPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = AllocationPatch._(
        rateId: WriteValue.overlay(earlier.rateId, later.rateId),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(AllocationPatch input) => input.rateId.isMissing;
}

/// Immutable input data; composition belongs to [allocationInsert], not field names.
final class AllocationInsert {
  final WriteValue<int, AllocationFields> id;
  final WriteValue<Decimal, AllocationFields> rateId;
  AllocationInsert._({required this.id, required this.rateId}) {
    if (rateId.isMissing) {
      throw ArgumentError.value(rateId, 'rateId', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(AllocationFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.rateId.write(rateId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class AllocationInsertFactory {
  AllocationInsert call({int id, required Decimal rateId});
  AllocationInsert values({
    WriteValue<int, AllocationFields> id = const .keep(),
    required WriteValue<Decimal, AllocationFields> rateId,
  });
  AllocationInsert overlay(
    AllocationInsert earlier,
    Iterable<AllocationPatch> layers,
  );
}

const AllocationInsertFactory allocationInsert = _AllocationInsertFactory();

final class _AllocationInsertFactory implements AllocationInsertFactory {
  const _AllocationInsertFactory();
  @override
  AllocationInsert call({Object? id = _writeAbsent, required Decimal rateId}) =>
      AllocationInsert._(
        id: _writeLiteral<int, AllocationFields>(id),
        rateId: .set(rateId),
      );
  @override
  AllocationInsert values({
    WriteValue<int, AllocationFields> id = const .keep(),
    required WriteValue<Decimal, AllocationFields> rateId,
  }) => AllocationInsert._(id: id, rateId: rateId);
  @override
  AllocationInsert overlay(
    AllocationInsert earlier,
    Iterable<AllocationPatch> layers,
  ) {
    for (final later in layers) {
      earlier = AllocationInsert._(
        id: earlier.id,
        rateId: WriteValue.overlay(earlier.rateId, later.rateId),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Allocation from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class AllocationCreator {
  Future<models.Allocation> call({int id, required Decimal rateId});
}

final class _AllocationCreator implements AllocationCreator {
  final AllocationTableSet _table;
  const _AllocationCreator(this._table);
  @override
  Future<models.Allocation> call({
    Object? id = _writeAbsent,
    required Decimal rateId,
  }) async => _table.plan
      .insert(
        AllocationInsert._(
          id: _writeLiteral<int, AllocationFields>(id),
          rateId: .set(rateId),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class AllocationPatcher {
  Future<int> call({Decimal rateId});
}

final class _AllocationPatcher implements AllocationPatcher {
  final orm_model.ModelQuery<
    models.Allocation,
    AllocationFields,
    AllocationPatch
  >
  _query;
  const _AllocationPatcher(this._query);
  @override
  Future<int> call({Object? rateId = _writeAbsent}) => _query.update(
    AllocationPatch._(rateId: _writeLiteral<Decimal, AllocationFields>(rateId)),
  );
}

/// Named literal updates on a complete models.Allocation query.
extension AllocationWrites
    on
        orm_model.ModelQuery<
          models.Allocation,
          AllocationFields,
          AllocationPatch
        > {
  /// Executes one update; omitted fields remain unchanged.
  AllocationPatcher get patch => _AllocationPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class AllocationTableSet
    extends
        orm_model.ModelTable<
          models.Allocation,
          AllocationFields,
          AllocationInsert,
          AllocationPatch
        > {
  AllocationTableSet(QueryContext db)
    : super(
        db,
        allocationTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final AllocationCreator create = _AllocationCreator(this);

  orm_model.ModelQuery<models.Allocation, AllocationFields, AllocationPatch>
  byId(int id) => where((row) => row.id.eq(.value(id)));
}

final _entryId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _entryAmount = Column<Decimal>(
  "amount",
  Codecs.decimal,
  nullable: false,
  generated: false,
);
final _entryFee = Column<Decimal?>(
  "fee",
  Codecs.decimal.nullable(),
  nullable: true,
  generated: false,
);
final _entryTax = Column<Decimal>(
  "tax",
  Codecs.decimal,
  nullable: false,
  generated: false,
  defaultSql: "'0.10'",
);
final _entryBucket = Column<String>(
  "bucket",
  Codecs.text,
  nullable: false,
  generated: false,
);
final entrySchema = TableSchema(
  "entries",
  columns: [_entryId, _entryAmount, _entryFee, _entryTax, _entryBucket],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class EntryFields extends Fields {
  EntryFields(super.table);
  late final id = column(_entryId);
  late final amount = column(_entryAmount);
  late final fee = column(_entryFee);
  late final tax = column(_entryTax);
  late final bucket = column(_entryBucket);
}

final entryTable = Table<models.Entry, EntryFields>(
  entrySchema,
  EntryFields.new,
  (row) => (row.id, row.amount, row.fee, row.tax, row.bucket).map(
    (v0, v1, v2, v3, v4) =>
        models.Entry(id: v0, amount: v1, fee: v2, tax: v3, bucket: v4),
  ),
);

/// Immutable input data; composition belongs to [entryPatch], not field names.
final class EntryPatch {
  final WriteValue<Decimal, EntryFields> amount;
  final WriteValue<Decimal?, EntryFields> fee;
  final WriteValue<Decimal, EntryFields> tax;
  final WriteValue<String, EntryFields> bucket;
  EntryPatch._({
    required this.amount,
    required this.fee,
    required this.tax,
    required this.bucket,
  });

  List<Assignment> _assignments(EntryFields fields) => [
    ...fields.amount.write(amount, fields),
    ...fields.fee.write(fee, fields),
    ...fields.tax.write(tax, fields),
    ...fields.bucket.write(bucket, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EntryPatchFactory {
  EntryPatch call({Decimal amount, Decimal? fee, Decimal tax, String bucket});
  EntryPatch values({
    WriteValue<Decimal, EntryFields> amount = const .keep(),
    WriteValue<Decimal?, EntryFields> fee = const .keep(),
    WriteValue<Decimal, EntryFields> tax = const .keep(),
    WriteValue<String, EntryFields> bucket = const .keep(),
  });
  EntryPatch overlay(Iterable<EntryPatch> layers);
  bool isEmpty(EntryPatch input);
}

const EntryPatchFactory entryPatch = _EntryPatchFactory();

final class _EntryPatchFactory implements EntryPatchFactory {
  const _EntryPatchFactory();
  @override
  EntryPatch call({
    Object? amount = _writeAbsent,
    Object? fee = _writeAbsent,
    Object? tax = _writeAbsent,
    Object? bucket = _writeAbsent,
  }) => EntryPatch._(
    amount: _writeLiteral<Decimal, EntryFields>(amount),
    fee: _writeLiteral<Decimal?, EntryFields>(fee),
    tax: _writeLiteral<Decimal, EntryFields>(tax),
    bucket: _writeLiteral<String, EntryFields>(bucket),
  );
  @override
  EntryPatch values({
    WriteValue<Decimal, EntryFields> amount = const .keep(),
    WriteValue<Decimal?, EntryFields> fee = const .keep(),
    WriteValue<Decimal, EntryFields> tax = const .keep(),
    WriteValue<String, EntryFields> bucket = const .keep(),
  }) => EntryPatch._(amount: amount, fee: fee, tax: tax, bucket: bucket);
  @override
  EntryPatch overlay(Iterable<EntryPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = EntryPatch._(
        amount: WriteValue.overlay(earlier.amount, later.amount),
        fee: WriteValue.overlay(earlier.fee, later.fee),
        tax: WriteValue.overlay(earlier.tax, later.tax),
        bucket: WriteValue.overlay(earlier.bucket, later.bucket),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(EntryPatch input) =>
      input.amount.isMissing &&
      input.fee.isMissing &&
      input.tax.isMissing &&
      input.bucket.isMissing;
}

/// Immutable input data; composition belongs to [entryInsert], not field names.
final class EntryInsert {
  final WriteValue<int, EntryFields> id;
  final WriteValue<Decimal, EntryFields> amount;
  final WriteValue<Decimal?, EntryFields> fee;
  final WriteValue<Decimal, EntryFields> tax;
  final WriteValue<String, EntryFields> bucket;
  EntryInsert._({
    required this.id,
    required this.amount,
    required this.fee,
    required this.tax,
    required this.bucket,
  }) {
    if (amount.isMissing) {
      throw ArgumentError.value(amount, 'amount', 'Must be supplied.');
    }
    if (bucket.isMissing) {
      throw ArgumentError.value(bucket, 'bucket', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(EntryFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.amount.write(amount, fields),
    ...fields.fee.write(fee, fields),
    ...fields.tax.write(tax, fields),
    ...fields.bucket.write(bucket, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EntryInsertFactory {
  EntryInsert call({
    int id,
    required Decimal amount,
    Decimal? fee,
    Decimal tax,
    required String bucket,
  });
  EntryInsert values({
    WriteValue<int, EntryFields> id = const .keep(),
    required WriteValue<Decimal, EntryFields> amount,
    WriteValue<Decimal?, EntryFields> fee = const .keep(),
    WriteValue<Decimal, EntryFields> tax = const .keep(),
    required WriteValue<String, EntryFields> bucket,
  });
  EntryInsert overlay(EntryInsert earlier, Iterable<EntryPatch> layers);
}

const EntryInsertFactory entryInsert = _EntryInsertFactory();

final class _EntryInsertFactory implements EntryInsertFactory {
  const _EntryInsertFactory();
  @override
  EntryInsert call({
    Object? id = _writeAbsent,
    required Decimal amount,
    Object? fee = _writeAbsent,
    Object? tax = _writeAbsent,
    required String bucket,
  }) => EntryInsert._(
    id: _writeLiteral<int, EntryFields>(id),
    amount: .set(amount),
    fee: _writeLiteral<Decimal?, EntryFields>(fee),
    tax: _writeLiteral<Decimal, EntryFields>(tax),
    bucket: .set(bucket),
  );
  @override
  EntryInsert values({
    WriteValue<int, EntryFields> id = const .keep(),
    required WriteValue<Decimal, EntryFields> amount,
    WriteValue<Decimal?, EntryFields> fee = const .keep(),
    WriteValue<Decimal, EntryFields> tax = const .keep(),
    required WriteValue<String, EntryFields> bucket,
  }) =>
      EntryInsert._(id: id, amount: amount, fee: fee, tax: tax, bucket: bucket);
  @override
  EntryInsert overlay(EntryInsert earlier, Iterable<EntryPatch> layers) {
    for (final later in layers) {
      earlier = EntryInsert._(
        id: earlier.id,
        amount: WriteValue.overlay(earlier.amount, later.amount),
        fee: WriteValue.overlay(earlier.fee, later.fee),
        tax: WriteValue.overlay(earlier.tax, later.tax),
        bucket: WriteValue.overlay(earlier.bucket, later.bucket),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Entry from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class EntryCreator {
  Future<models.Entry> call({
    int id,
    required Decimal amount,
    Decimal? fee,
    Decimal tax,
    required String bucket,
  });
}

final class _EntryCreator implements EntryCreator {
  final EntryTableSet _table;
  const _EntryCreator(this._table);
  @override
  Future<models.Entry> call({
    Object? id = _writeAbsent,
    required Decimal amount,
    Object? fee = _writeAbsent,
    Object? tax = _writeAbsent,
    required String bucket,
  }) async => _table.plan
      .insert(
        EntryInsert._(
          id: _writeLiteral<int, EntryFields>(id),
          amount: .set(amount),
          fee: _writeLiteral<Decimal?, EntryFields>(fee),
          tax: _writeLiteral<Decimal, EntryFields>(tax),
          bucket: .set(bucket),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class EntryPatcher {
  Future<int> call({Decimal amount, Decimal? fee, Decimal tax, String bucket});
}

final class _EntryPatcher implements EntryPatcher {
  final orm_model.ModelQuery<models.Entry, EntryFields, EntryPatch> _query;
  const _EntryPatcher(this._query);
  @override
  Future<int> call({
    Object? amount = _writeAbsent,
    Object? fee = _writeAbsent,
    Object? tax = _writeAbsent,
    Object? bucket = _writeAbsent,
  }) => _query.update(
    EntryPatch._(
      amount: _writeLiteral<Decimal, EntryFields>(amount),
      fee: _writeLiteral<Decimal?, EntryFields>(fee),
      tax: _writeLiteral<Decimal, EntryFields>(tax),
      bucket: _writeLiteral<String, EntryFields>(bucket),
    ),
  );
}

/// Named literal updates on a complete models.Entry query.
extension EntryWrites
    on orm_model.ModelQuery<models.Entry, EntryFields, EntryPatch> {
  /// Executes one update; omitted fields remain unchanged.
  EntryPatcher get patch => _EntryPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class EntryTableSet
    extends
        orm_model.ModelTable<
          models.Entry,
          EntryFields,
          EntryInsert,
          EntryPatch
        > {
  EntryTableSet(QueryContext db)
    : super(
        db,
        entryTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final EntryCreator create = _EntryCreator(this);

  orm_model.ModelQuery<models.Entry, EntryFields, EntryPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final _rateId = Column<Decimal>(
  "id",
  Codecs.decimal,
  nullable: false,
  generated: false,
);
final _rateLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final rateSchema = TableSchema(
  "rates",
  columns: [_rateId, _rateLabel],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class RateFields extends Fields {
  RateFields(super.table);
  late final id = column(_rateId);
  late final label = column(_rateLabel);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Allocation, AllocationFields> get allocations =>
      Relation(allocationTable, parent: [id], child: (row) => [row.rateId]);
}

final rateTable = Table<models.Rate, RateFields>(
  rateSchema,
  RateFields.new,
  (row) => (row.id, row.label).map((v0, v1) => models.Rate(id: v0, label: v1)),
);

/// Immutable input data; composition belongs to [ratePatch], not field names.
final class RatePatch {
  final WriteValue<Decimal, RateFields> id;
  final WriteValue<String, RateFields> label;
  RatePatch._({required this.id, required this.label});

  List<Assignment> _assignments(RateFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class RatePatchFactory {
  RatePatch call({Decimal id, String label});
  RatePatch values({
    WriteValue<Decimal, RateFields> id = const .keep(),
    WriteValue<String, RateFields> label = const .keep(),
  });
  RatePatch overlay(Iterable<RatePatch> layers);
  bool isEmpty(RatePatch input);
}

const RatePatchFactory ratePatch = _RatePatchFactory();

final class _RatePatchFactory implements RatePatchFactory {
  const _RatePatchFactory();
  @override
  RatePatch call({Object? id = _writeAbsent, Object? label = _writeAbsent}) =>
      RatePatch._(
        id: _writeLiteral<Decimal, RateFields>(id),
        label: _writeLiteral<String, RateFields>(label),
      );
  @override
  RatePatch values({
    WriteValue<Decimal, RateFields> id = const .keep(),
    WriteValue<String, RateFields> label = const .keep(),
  }) => RatePatch._(id: id, label: label);
  @override
  RatePatch overlay(Iterable<RatePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = RatePatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(RatePatch input) => input.id.isMissing && input.label.isMissing;
}

/// Immutable input data; composition belongs to [rateInsert], not field names.
final class RateInsert {
  final WriteValue<Decimal, RateFields> id;
  final WriteValue<String, RateFields> label;
  RateInsert._({required this.id, required this.label}) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (label.isMissing) {
      throw ArgumentError.value(label, 'label', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(RateFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.label.write(label, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class RateInsertFactory {
  RateInsert call({required Decimal id, required String label});
  RateInsert values({
    required WriteValue<Decimal, RateFields> id,
    required WriteValue<String, RateFields> label,
  });
  RateInsert overlay(RateInsert earlier, Iterable<RatePatch> layers);
}

const RateInsertFactory rateInsert = _RateInsertFactory();

final class _RateInsertFactory implements RateInsertFactory {
  const _RateInsertFactory();
  @override
  RateInsert call({required Decimal id, required String label}) =>
      RateInsert._(id: .set(id), label: .set(label));
  @override
  RateInsert values({
    required WriteValue<Decimal, RateFields> id,
    required WriteValue<String, RateFields> label,
  }) => RateInsert._(id: id, label: label);
  @override
  RateInsert overlay(RateInsert earlier, Iterable<RatePatch> layers) {
    for (final later in layers) {
      earlier = RateInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        label: WriteValue.overlay(earlier.label, later.label),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Rate from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class RateCreator {
  Future<models.Rate> call({required Decimal id, required String label});
}

final class _RateCreator implements RateCreator {
  final RateTableSet _table;
  const _RateCreator(this._table);
  @override
  Future<models.Rate> call({
    required Decimal id,
    required String label,
  }) async =>
      _table.plan.insert(RateInsert._(id: .set(id), label: .set(label))).row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class RatePatcher {
  Future<int> call({Decimal id, String label});
}

final class _RatePatcher implements RatePatcher {
  final orm_model.ModelQuery<models.Rate, RateFields, RatePatch> _query;
  const _RatePatcher(this._query);
  @override
  Future<int> call({Object? id = _writeAbsent, Object? label = _writeAbsent}) =>
      _query.update(
        RatePatch._(
          id: _writeLiteral<Decimal, RateFields>(id),
          label: _writeLiteral<String, RateFields>(label),
        ),
      );
}

/// Named literal updates on a complete models.Rate query.
extension RateWrites
    on orm_model.ModelQuery<models.Rate, RateFields, RatePatch> {
  /// Executes one update; omitted fields remain unchanged.
  RatePatcher get patch => _RatePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class RateTableSet
    extends
        orm_model.ModelTable<models.Rate, RateFields, RateInsert, RatePatch> {
  RateTableSet(QueryContext db)
    : super(
        db,
        rateTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final RateCreator create = _RateCreator(this);

  orm_model.ModelQuery<models.Rate, RateFields, RatePatch> byId(Decimal id) =>
      where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([
  allocationSchema,
  entrySchema,
  rateSchema,
]);

extension AppTables on QueryContext {
  AllocationTableSet get allocation => AllocationTableSet(this);
  EntryTableSet get entry => EntryTableSet(this);
  RateTableSet get rate => RateTableSet(this);
}
