// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "users",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("email", Codecs.text),
      Column("nickname", Codecs.text.nullable(), nullable: true),
      Column("score", Codecs.integer, defaultSql: "0"),
    ],
    primaryKey: ["id"],
    uniqueKeys: [
      ["email"],
    ],
  ),
  TableSchema(
    "posts",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("author_id", Codecs.integer),
      Column("title", Codecs.text),
      Column("created_at", Codecs.dateTime),
    ],
    primaryKey: ["id"],

    indexes: [
      IndexSchema("author_timeline", [
        "author_id",
        "created_at",
        "id",
      ], unique: false),
    ],
    foreignKeys: [
      ForeignKey(["author_id"], "users", ["id"], onDelete: "CASCADE"),
    ],
  ),
]);
