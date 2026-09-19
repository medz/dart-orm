// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "nominal_accounts",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("email", Codecs.text),
      Column("display_name", Codecs.text.nullable(), nullable: true),
      Column("enabled", Codecs.boolean, defaultSql: "false"),
      Column("marker", Codecs.text),
      Column("a", Codecs.integer),
      Column("b", Codecs.integer),
      Column("c", Codecs.integer),
      Column(
        "total",
        Codecs.integer,

        computed: ComputedColumn("a + b", storage: ComputedStorage.stored),
      ),
    ],
    primaryKey: ["id"],
    uniqueKeys: [
      ["email"],
    ],
  ),
  TableSchema(
    "nominal_notes",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("account_id", Codecs.integer),
      Column("body", Codecs.text),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(
        ["account_id"],
        "nominal_accounts",
        ["id"],
        onDelete: "CASCADE",
      ),
    ],
  ),
]);
