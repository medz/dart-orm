// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "events",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("at", Codecs.dateTime),
      Column("created", Codecs.dateTime, defaultSql: "CURRENT_TIMESTAMP"),
      Column("optional", Codecs.dateTime.nullable(), nullable: true),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "moments",
    columns: [
      Column("at", Codecs.dateTime),
      Column("label", Codecs.text, defaultSql: "'pending'"),
    ],
    primaryKey: ["at"],
  ),
  TableSchema(
    "links",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("at", Codecs.dateTime),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["at"], "moments", ["at"], onDelete: "RESTRICT"),
    ],
  ),
]);
