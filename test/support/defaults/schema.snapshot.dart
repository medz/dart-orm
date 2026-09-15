// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
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
  TableSchema(
    "sequences",
    columns: [Column("id", Codecs.integer, generated: true)],
    primaryKey: ["id"],
  ),
]);
