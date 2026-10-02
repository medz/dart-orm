// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/values.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "memberships",
    columns: [
      Column("team_id", Codecs.integer),
      Column("user_id", Codecs.integer),
      Column("role", Codecs.text, defaultSql: "'member'"),
    ],
    primaryKey: ["team_id", "user_id"],

    foreignKeys: [
      ForeignKey(["team_id"], "teams", ["id"], onDelete: "RESTRICT"),
      ForeignKey(["user_id"], "users", ["id"], onDelete: "RESTRICT"),
    ],
  ),
  TableSchema(
    "teams",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("name", Codecs.text),
      Column("owner_id", Codecs.integer.nullable(), nullable: true),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["owner_id"], "users", ["id"], onDelete: "SET NULL"),
    ],
  ),
  TableSchema(
    "users",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("email", Codecs.text),
      Column("name", Codecs.text),
      Column("nickname", Codecs.text.nullable(), nullable: true),
      Column("stamp", Codecs.integer),
    ],
    primaryKey: ["id"],
  ),
]);
