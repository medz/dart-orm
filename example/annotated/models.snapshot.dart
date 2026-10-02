// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/values.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "User",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("email", Codecs.text),
      Column("display_name", Codecs.text),
      Column("nickname", Codecs.text.nullable(), nullable: true),
      Column("active", Codecs.boolean, defaultSql: "true"),
      Column("marker", Codecs.text, defaultSql: "'server-marker'"),
      Column("score", Codecs.integer),
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
      Column("status", Codecs.text, defaultSql: "'draft'"),
    ],
    primaryKey: ["id"],

    indexes: [
      IndexSchema("posts_author_created", [
        "author_id",
        "created_at",
      ], unique: false),
    ],
    foreignKeys: [
      ForeignKey(["author_id"], "User", ["id"], onDelete: "CASCADE"),
    ],
  ),
]);
