// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "wallets",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("amount", Codecs.decimal, decimalPrecision: 5, decimalScale: 2),
      Column("hundreds", Codecs.decimal, decimalPrecision: 3, decimalScale: -2),
      Column("fraction", Codecs.decimal, decimalPrecision: 3, decimalScale: 5),
      Column(
        "defaulted",
        Codecs.decimal,

        defaultSql: "'1.235'",

        decimalPrecision: 5,
        decimalScale: 2,
      ),
      Column(
        "optional",
        Codecs.decimal.nullable(),
        nullable: true,

        decimalPrecision: 5,
        decimalScale: 2,
      ),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "prices",
    columns: [
      Column("id", Codecs.decimal, decimalPrecision: 4, decimalScale: 2),
      Column("label", Codecs.text),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "receipts",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("price_id", Codecs.decimal, decimalPrecision: 4, decimalScale: 2),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["price_id"], "prices", ["id"], onDelete: "RESTRICT"),
    ],
  ),
]);
