// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "accounts",
    columns: [
      Column("tenant", Codecs.integer),
      Column("id", Codecs.integer),
      Column("label", Codecs.text.nullable(), nullable: true),
      Column("note", Codecs.text.nullable(), nullable: true),
      Column("manager_id", Codecs.integer.nullable(), nullable: true),
      Column("_ORM_PRESENT", Codecs.text.nullable(), nullable: true),
    ],
    primaryKey: ["tenant", "id"],

    foreignKeys: [
      ForeignKey(
        ["tenant", "manager_id"],
        "accounts",
        ["tenant", "id"],
        onDelete: "RESTRICT",
      ),
    ],
  ),
  TableSchema(
    "events",
    columns: [
      Column("id", Codecs.integer),
      Column("tenant", Codecs.integer.nullable(), nullable: true),
      Column("owner", Codecs.integer.nullable(), nullable: true),
      Column("reviewer", Codecs.integer.nullable(), nullable: true),
      Column("title", Codecs.text),
      Column("score", Codecs.integer),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(
        ["tenant", "owner"],
        "accounts",
        ["tenant", "id"],
        onDelete: "RESTRICT",
      ),
      ForeignKey(
        ["tenant", "reviewer"],
        "accounts",
        ["tenant", "id"],
        onDelete: "RESTRICT",
      ),
    ],
  ),
]);
