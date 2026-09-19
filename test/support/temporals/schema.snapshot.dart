// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "appointments",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("day", Codecs.date),
      Column("time", Codecs.time, defaultSql: "'12:30'"),
      Column("starts", Codecs.localDateTime.nullable(), nullable: true),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "holidays",
    columns: [Column("day", Codecs.date), Column("label", Codecs.text)],
    primaryKey: ["day"],
  ),
  TableSchema(
    "visits",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("day", Codecs.date),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["day"], "holidays", ["day"], onDelete: "RESTRICT"),
    ],
  ),
]);
