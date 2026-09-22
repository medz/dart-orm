// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

/// A complete immutable row from "wallets".
final class Wallet({
  required final int id,
  required final Decimal amount,
  required final Decimal hundreds,
  required final Decimal fraction,
  required final Decimal defaulted,
  required final Decimal? optional,
});
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

final walletTable = Table<Wallet, WalletFields>(
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
        (v0, v1, v2, v3, v4, v5) => Wallet(
          id: v0,
          amount: v1,
          hundreds: v2,
          fraction: v3,
          defaulted: v4,
          optional: v5,
        ),
      ),
);

final class WalletTableSet extends TableSet<Wallet, WalletFields> {
  WalletTableSet(QueryContext db) : super(db, walletTable) {
    db.registerSchema(appSchema);
  }
  Future<Wallet> create({
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
  Query<Wallet, WalletFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension WalletUpdates on Query<Wallet, WalletFields> {
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

/// A complete immutable row from "prices".
final class Price({required final Decimal id, required final String label});
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
  Relation<Receipt, ReceiptFields> get receipts =>
      Relation(receiptTable, parent: [id], child: (row) => [row.priceId]);
}

final priceTable = Table<Price, PriceFields>(
  priceSchema,
  PriceFields.new,
  (row) => (row.id, row.label).map((v0, v1) => Price(id: v0, label: v1)),
);

final class PriceTableSet extends TableSet<Price, PriceFields> {
  PriceTableSet(QueryContext db) : super(db, priceTable) {
    db.registerSchema(appSchema);
  }
  Future<Price> create({required Decimal id, required String label}) =>
      createRow((row) => [row.id.set(id), row.label.set(label)]);
  Query<Price, PriceFields> byId(Decimal id) =>
      where((row) => row.id.eq(.value(id)));
}

extension PriceUpdates on Query<Price, PriceFields> {
  Future<int> patch({
    Change<Decimal> id = const Change.keep(),
    Change<String> label = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.label.change(label)])
          .execute();
}

/// A complete immutable row from "receipts".
final class Receipt({required final int id, required final Decimal priceId});
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
  Relation<Price, PriceFields> get price =>
      Relation(priceTable, parent: [priceId], child: (row) => [row.id]);
}

final receiptTable = Table<Receipt, ReceiptFields>(
  receiptSchema,
  ReceiptFields.new,
  (row) => (row.id, row.priceId).map((v0, v1) => Receipt(id: v0, priceId: v1)),
);

final class ReceiptTableSet extends TableSet<Receipt, ReceiptFields> {
  ReceiptTableSet(QueryContext db) : super(db, receiptTable) {
    db.registerSchema(appSchema);
  }
  Future<Receipt> create({
    Change<int> id = const Change.keep(),
    required Decimal priceId,
  }) => createRow((row) => [...row.id.change(id), row.priceId.set(priceId)]);
  Query<Receipt, ReceiptFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension ReceiptUpdates on Query<Receipt, ReceiptFields> {
  Future<int> patch({Change<Decimal> priceId = const Change.keep()}) =>
      update((row) => [...row.priceId.change(priceId)]).execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  walletSchema,
  priceSchema,
  receiptSchema,
]);

extension AppTables on QueryContext {
  WalletTableSet get wallet => WalletTableSet(this);
  PriceTableSet get price => PriceTableSet(this);
  ReceiptTableSet get receipt => ReceiptTableSet(this);
}
