// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show Entry, Rate, Allocation;

final _entriesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _entriesAmount = Column<Decimal>(
  "amount",
  Codecs.decimal,
  nullable: false,
  generated: false,
);
final _entriesFee = Column<Decimal?>(
  "fee",
  Codecs.decimal.nullable(),
  nullable: true,
  generated: false,
);
final _entriesTax = Column<Decimal>(
  "tax",
  Codecs.decimal,
  nullable: false,
  generated: false,
  defaultSql: "'0.10'",
);
final _entriesBucket = Column<String>(
  "bucket",
  Codecs.text,
  nullable: false,
  generated: false,
);
final entriesSchema = TableSchema(
  "entries",
  columns: [
    _entriesId,
    _entriesAmount,
    _entriesFee,
    _entriesTax,
    _entriesBucket,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class EntriesFields extends Fields {
  EntriesFields(super.table);
  late final id = column(_entriesId);
  late final amount = column(_entriesAmount);
  late final fee = column(_entriesFee);
  late final tax = column(_entriesTax);
  late final bucket = column(_entriesBucket);
}

final entriesTable = Table<models.Entry, EntriesFields>(
  entriesSchema,
  EntriesFields.new,
  (row) => (row.id, row.amount, row.fee, row.tax, row.bucket).map(
    (id, amount, fee, tax, bucket) =>
        (id: id, amount: amount, fee: fee, tax: tax, bucket: bucket),
  ),
);

final class EntriesTableSet extends TableSet<models.Entry, EntriesFields> {
  EntriesTableSet(QueryContext db) : super(db, entriesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Entry> create({
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
  Query<models.Entry, EntriesFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension EntriesUpdates on Query<models.Entry, EntriesFields> {
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

final _ratesId = Column<Decimal>(
  "id",
  Codecs.decimal,
  nullable: false,
  generated: false,
);
final _ratesLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final ratesSchema = TableSchema(
  "rates",
  columns: [_ratesId, _ratesLabel],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class RatesFields extends Fields {
  RatesFields(super.table);
  late final id = column(_ratesId);
  late final label = column(_ratesLabel);
  Relation<models.Allocation, AllocationsFields> get allocations =>
      Relation(allocationsTable, parent: [id], child: (row) => [row.rateId]);
}

final ratesTable = Table<models.Rate, RatesFields>(
  ratesSchema,
  RatesFields.new,
  (row) => (row.id, row.label).map((id, label) => (id: id, label: label)),
);

final class RatesTableSet extends TableSet<models.Rate, RatesFields> {
  RatesTableSet(QueryContext db) : super(db, ratesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Rate> create({required Decimal id, required String label}) =>
      createRow((row) => [row.id.set(id), row.label.set(label)]);
  Query<models.Rate, RatesFields> byId(Decimal id) =>
      where((row) => row.id.eq(id));
}

extension RatesUpdates on Query<models.Rate, RatesFields> {
  Future<int> patch({
    Change<Decimal> id = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.label.change(label)])
          .execute();
}

final _allocationsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _allocationsRateId = Column<Decimal>(
  "rate_id",
  Codecs.decimal,
  nullable: false,
  generated: false,
);
final allocationsSchema = TableSchema(
  "allocations",
  columns: [_allocationsId, _allocationsRateId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["rate_id"], "rates", ["id"], onDelete: "RESTRICT"),
  ],
);

final class AllocationsFields extends Fields {
  AllocationsFields(super.table);
  late final id = column(_allocationsId);
  late final rateId = column(_allocationsRateId);
  Relation<models.Rate, RatesFields> get rate =>
      Relation(ratesTable, parent: [rateId], child: (row) => [row.id]);
}

final allocationsTable = Table<models.Allocation, AllocationsFields>(
  allocationsSchema,
  AllocationsFields.new,
  (row) => (row.id, row.rateId).map((id, rateId) => (id: id, rateId: rateId)),
);

final class AllocationsTableSet
    extends TableSet<models.Allocation, AllocationsFields> {
  AllocationsTableSet(QueryContext db) : super(db, allocationsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Allocation> create({
    Change<int> id = const Change.keep(),
    required Decimal rateId,
  }) => createRow((row) => [...row.id.change(id), row.rateId.set(rateId)]);
  Query<models.Allocation, AllocationsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension AllocationsUpdates on Query<models.Allocation, AllocationsFields> {
  Future<int> patch({Change<Decimal> rateId = const Change.keep()}) =>
      update((row) => [...row.rateId.change(rateId)]).execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  entriesSchema,
  ratesSchema,
  allocationsSchema,
]);

extension AppTables on QueryContext {
  EntriesTableSet get entries => EntriesTableSet(this);
  RatesTableSet get rates => RatesTableSet(this);
  AllocationsTableSet get allocations => AllocationsTableSet(this);
}
