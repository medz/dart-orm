// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/values.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "sequences",
    columns: [Column("id", Codecs.integer, generated: true)],
    primaryKey: ["id"],
  ),
  TableSchema(
    "tickets",
    columns: [
      Column("id", Codecs.integer),
      Column("name", Codecs.text),
      Column("label", Codecs.text.nullable(), nullable: true),
      Column("state", Codecs.text, defaultSql: "'server'"),
      Column("created_at", Codecs.dateTime),
    ],
    primaryKey: ["id"],
  ),
]);
