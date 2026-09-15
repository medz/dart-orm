// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "people",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("email", Codecs.text),
      Column("membership", Codecs.text),
      Column("previous_membership", Codecs.text.nullable(), nullable: true),
      Column("tags", Codecs.json),
      Column("location", Codecs.json.nullable(), nullable: true),
      Column("alternate", Codecs.text),
      Column("details", Codecs.json.nullable(), nullable: true),
    ],
    primaryKey: ["id"],
    uniqueKeys: [
      ["email"],
    ],
  ),
  TableSchema(
    "notes",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("owner_id", Codecs.integer),
      Column("body", Codecs.text),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["owner_id"], "people", ["id"], onDelete: "RESTRICT"),
    ],
  ),
]);
