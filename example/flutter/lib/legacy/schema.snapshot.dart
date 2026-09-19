// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "notes",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("body", Codecs.text),
      Column("created_at", Codecs.dateTime),
    ],
    primaryKey: ["id"],
  ),
]);
