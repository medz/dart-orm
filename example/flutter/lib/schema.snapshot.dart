// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "notes",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("body", Codecs.text),
      Column("done", Codecs.boolean, defaultSql: "false"),
      Column("created_at", Codecs.dateTime),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "comments",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("note_id", Codecs.integer),
      Column("text", Codecs.text),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["note_id"], "notes", ["id"], onDelete: "CASCADE"),
    ],
  ),
]);
