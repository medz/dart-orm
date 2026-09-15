// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;

final _walletsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _walletsAmount = Column<Decimal>(
  "amount",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 5,
  decimalScale: 2,
);
final _walletsHundreds = Column<Decimal>(
  "hundreds",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 3,
  decimalScale: -2,
);
final _walletsFraction = Column<Decimal>(
  "fraction",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 3,
  decimalScale: 5,
);
final _walletsDefaulted = Column<Decimal>(
  "defaulted",
  Codecs.decimal,
  nullable: false,
  generated: false,
  defaultSql: "'1.235'",
  decimalPrecision: 5,
  decimalScale: 2,
);
final _walletsOptional = Column<Decimal?>(
  "optional",
  Codecs.decimal.nullable(),
  nullable: true,
  generated: false,
  decimalPrecision: 5,
  decimalScale: 2,
);
final walletsSchema = TableSchema(
  "wallets",
  columns: [
    _walletsId,
    _walletsAmount,
    _walletsHundreds,
    _walletsFraction,
    _walletsDefaulted,
    _walletsOptional,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class WalletsFields extends Fields {
  WalletsFields(super.table);
  late final id = column(_walletsId);
  late final amount = column(_walletsAmount);
  late final hundreds = column(_walletsHundreds);
  late final fraction = column(_walletsFraction);
  late final defaulted = column(_walletsDefaulted);
  late final optional = column(_walletsOptional);
}

final walletsTable = Table<models.Wallet, WalletsFields>(
  walletsSchema,
  WalletsFields.new,
  (row) =>
      (
        row.id,
        row.amount,
        row.hundreds,
        row.fraction,
        row.defaulted,
        row.optional,
      ).map(
        (id, amount, hundreds, fraction, defaulted, optional) => (
          id: id,
          amount: amount,
          hundreds: hundreds,
          fraction: fraction,
          defaulted: defaulted,
          optional: optional,
        ),
      ),
);

final class WalletsTableSet extends TableSet<models.Wallet, WalletsFields> {
  WalletsTableSet(Database<Backend> db) : super(db, walletsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Wallet> create({
    Change<int> id = const Change.keep(),
    required Decimal amount,
    required Decimal hundreds,
    required Decimal fraction,
    Change<Decimal> defaulted = const Change.keep(),
    Decimal? optional,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.amount.set(amount),
      row.hundreds.set(hundreds),
      row.fraction.set(fraction),
      ...row.defaulted.change(defaulted),
      row.optional.set(optional),
    ],
  );
  Query<models.Wallet, WalletsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension WalletsUpdates on Query<models.Wallet, WalletsFields> {
  Future<int> patch({
    Change<Decimal> amount = const Change.keep(),
    Change<Decimal> hundreds = const Change.keep(),
    Change<Decimal> fraction = const Change.keep(),
    Change<Decimal> defaulted = const Change.keep(),
    Change<Decimal?> optional = const Change.keep(),
  }) => update(
    (row) => [
      ...row.amount.change(amount),
      ...row.hundreds.change(hundreds),
      ...row.fraction.change(fraction),
      ...row.defaulted.change(defaulted),
      ...row.optional.change(optional),
    ],
  ).execute();
}

final _pricesId = Column<Decimal>(
  "id",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 4,
  decimalScale: 2,
);
final _pricesLabel = Column<String>(
  "label",
  Codecs.text,
  nullable: false,
  generated: false,
);
final pricesSchema = TableSchema(
  "prices",
  columns: [_pricesId, _pricesLabel],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class PricesFields extends Fields {
  PricesFields(super.table);
  late final id = column(_pricesId);
  late final label = column(_pricesLabel);
  Relation<models.Receipt, ReceiptsFields> get receipts =>
      Relation(receiptsTable, parent: [id], child: (row) => [row.priceId]);
}

final pricesTable = Table<models.Price, PricesFields>(
  pricesSchema,
  PricesFields.new,
  (row) => (row.id, row.label).map((id, label) => (id: id, label: label)),
);

final class PricesTableSet extends TableSet<models.Price, PricesFields> {
  PricesTableSet(Database<Backend> db) : super(db, pricesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Price> create({required Decimal id, required String label}) =>
      createRow((row) => [row.id.set(id), row.label.set(label)]);
  Query<models.Price, PricesFields> byId(Decimal id) =>
      where((row) => row.id.eq(id));
}

extension PricesUpdates on Query<models.Price, PricesFields> {
  Future<int> patch({
    Change<Decimal> id = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.label.change(label)])
          .execute();
}

final _receiptsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _receiptsPriceId = Column<Decimal>(
  "price_id",
  Codecs.decimal,
  nullable: false,
  generated: false,
  decimalPrecision: 4,
  decimalScale: 2,
);
final receiptsSchema = TableSchema(
  "receipts",
  columns: [_receiptsId, _receiptsPriceId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["price_id"], "prices", ["id"], onDelete: "RESTRICT"),
  ],
);

final class ReceiptsFields extends Fields {
  ReceiptsFields(super.table);
  late final id = column(_receiptsId);
  late final priceId = column(_receiptsPriceId);
  Relation<models.Price, PricesFields> get price =>
      Relation(pricesTable, parent: [priceId], child: (row) => [row.id]);
}

final receiptsTable = Table<models.Receipt, ReceiptsFields>(
  receiptsSchema,
  ReceiptsFields.new,
  (row) =>
      (row.id, row.priceId).map((id, priceId) => (id: id, priceId: priceId)),
);

final class ReceiptsTableSet extends TableSet<models.Receipt, ReceiptsFields> {
  ReceiptsTableSet(Database<Backend> db) : super(db, receiptsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Receipt> create({
    Change<int> id = const Change.keep(),
    required Decimal priceId,
  }) => createRow((row) => [...row.id.change(id), row.priceId.set(priceId)]);
  Query<models.Receipt, ReceiptsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension ReceiptsUpdates on Query<models.Receipt, ReceiptsFields> {
  Future<int> patch({Change<Decimal> priceId = const Change.keep()}) =>
      update((row) => [...row.priceId.change(priceId)]).execute();
}

final appSchema = <TableSchema>[walletsSchema, pricesSchema, receiptsSchema];

extension AppTables<B extends Backend> on Database<B> {
  WalletsTableSet get wallets => WalletsTableSet(this);
  PricesTableSet get prices => PricesTableSet(this);
  ReceiptsTableSet get receipts => ReceiptsTableSet(this);
}
