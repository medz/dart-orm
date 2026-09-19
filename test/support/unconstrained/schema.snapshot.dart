// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "accounts",
    columns: [
      Column("tenant", Codecs.integer),
      Column("id", Codecs.integer),
      Column("display_label", Codecs.text.nullable(), nullable: true),
      Column("manager_id", Codecs.integer.nullable(), nullable: true),
    ],
    primaryKey: ["tenant", "id"],
  ),
  TableSchema(
    "entries",
    columns: [
      Column("id", Codecs.integer),
      Column("tenant", Codecs.integer.nullable(), nullable: true),
      Column("owner", Codecs.integer.nullable(), nullable: true),
      Column("lookup_label", Codecs.text.nullable(), nullable: true),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "readings",
    columns: [Column("id", Codecs.integer), Column("value", Codecs.real)],
    primaryKey: ["id"],
  ),
]);
