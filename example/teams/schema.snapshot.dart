// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "users",
    columns: [Column("id", Codecs.integer), Column("name", Codecs.text)],
    primaryKey: ["id"],
  ),
  TableSchema(
    "teams",
    columns: [Column("id", Codecs.integer), Column("name", Codecs.text)],
    primaryKey: ["id"],
  ),
  TableSchema(
    "memberships",
    columns: [
      Column("team_id", Codecs.integer),
      Column("user_id", Codecs.integer),
      Column("role", Codecs.text, defaultSql: "'member'"),
      Column("joined_at", Codecs.dateTime),
    ],
    primaryKey: ["team_id", "user_id"],

    indexes: [
      IndexSchema("user_memberships", [
        "user_id",
        "joined_at",
        "team_id",
      ], unique: false),
    ],
    foreignKeys: [
      ForeignKey(["team_id"], "teams", ["id"], onDelete: "CASCADE"),
      ForeignKey(["user_id"], "users", ["id"], onDelete: "CASCADE"),
    ],
  ),
]);
