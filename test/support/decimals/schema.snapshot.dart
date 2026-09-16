// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "entries",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("amount", Codecs.decimal),
      Column("fee", Codecs.decimal.nullable(), nullable: true),
      Column("tax", Codecs.decimal, defaultSql: "'0.10'"),
      Column("bucket", Codecs.text),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "rates",
    columns: [Column("id", Codecs.decimal), Column("label", Codecs.text)],
    primaryKey: ["id"],
  ),
  TableSchema(
    "allocations",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("rate_id", Codecs.decimal),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["rate_id"], "rates", ["id"], onDelete: "RESTRICT"),
    ],
  ),
]);
