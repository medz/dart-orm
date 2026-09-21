// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

/// A complete immutable row from "entries".
final class Entry({
  required final int id,
  required final Decimal amount,
  required final Decimal? fee,
  required final Decimal tax,
  required final String bucket,
});
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

final entryTable = Table<Entry, EntryFields>(
  entrySchema,
  EntryFields.new,
  (row) => (row.id, row.amount, row.fee, row.tax, row.bucket).map(
    (v0, v1, v2, v3, v4) =>
        Entry(id: v0, amount: v1, fee: v2, tax: v3, bucket: v4),
  ),
);

final class EntryTableSet extends TableSet<Entry, EntryFields> {
  EntryTableSet(QueryContext db) : super(db, entryTable) {
    db.registerSchema(appSchema);
  }
  Future<Entry> create({
    Change<int> id = const Change.keep(),
    required Decimal amount,
    Decimal? fee,
    Change<Decimal> tax = const Change.keep(),
    required String bucket,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.amount.set(amount),
      row.fee.set(fee),
      ...row.tax.change(tax),
      row.bucket.set(bucket),
    ],
  );
  Query<Entry, EntryFields> byId(int id) => where((row) => row.id.eq(id));
}

extension EntryUpdates on Query<Entry, EntryFields> {
  Future<int> patch({
    Change<Decimal> amount = const Change.keep(),
    Change<Decimal?> fee = const Change.keep(),
    Change<Decimal> tax = const Change.keep(),
    Change<String> bucket = const Change.keep(),
  }) => update(
    (row) => [
      ...row.amount.change(amount),
      ...row.fee.change(fee),
      ...row.tax.change(tax),
      ...row.bucket.change(bucket),
    ],
  ).execute();
}

/// A complete immutable row from "rates".
final class Rate({required final Decimal id, required final String label});
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
  Relation<Allocation, AllocationFields> get allocations =>
      Relation(allocationTable, parent: [id], child: (row) => [row.rateId]);
}

final rateTable = Table<Rate, RateFields>(
  rateSchema,
  RateFields.new,
  (row) => (row.id, row.label).map((v0, v1) => Rate(id: v0, label: v1)),
);

final class RateTableSet extends TableSet<Rate, RateFields> {
  RateTableSet(QueryContext db) : super(db, rateTable) {
    db.registerSchema(appSchema);
  }
  Future<Rate> create({required Decimal id, required String label}) =>
      createRow((row) => [row.id.set(id), row.label.set(label)]);
  Query<Rate, RateFields> byId(Decimal id) => where((row) => row.id.eq(id));
}

extension RateUpdates on Query<Rate, RateFields> {
  Future<int> patch({
    Change<Decimal> id = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.label.change(label)])
          .execute();
}

/// A complete immutable row from "allocations".
final class Allocation({required final int id, required final Decimal rateId});
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
  Relation<Rate, RateFields> get rate =>
      Relation(rateTable, parent: [rateId], child: (row) => [row.id]);
}

final allocationTable = Table<Allocation, AllocationFields>(
  allocationSchema,
  AllocationFields.new,
  (row) => (row.id, row.rateId).map((v0, v1) => Allocation(id: v0, rateId: v1)),
);

final class AllocationTableSet extends TableSet<Allocation, AllocationFields> {
  AllocationTableSet(QueryContext db) : super(db, allocationTable) {
    db.registerSchema(appSchema);
  }
  Future<Allocation> create({
    Change<int> id = const Change.keep(),
    required Decimal rateId,
  }) => createRow((row) => [...row.id.change(id), row.rateId.set(rateId)]);
  Query<Allocation, AllocationFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension AllocationUpdates on Query<Allocation, AllocationFields> {
  Future<int> patch({Change<Decimal> rateId = const Change.keep()}) =>
      update((row) => [...row.rateId.change(rateId)]).execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  entrySchema,
  rateSchema,
  allocationSchema,
]);

extension AppTables on QueryContext {
  EntryTableSet get entry => EntryTableSet(this);
  RateTableSet get rate => RateTableSet(this);
  AllocationTableSet get allocation => AllocationTableSet(this);
}
