// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "samples",
    columns: [
      Column("id", Codecs.integer, generated: true, integerBits: 32),
      Column("small", Codecs.integer, integerBits: 16),
      Column("medium", Codecs.integer, integerBits: 32),
      Column("large", Codecs.integer),
      Column(
        "optional",
        Codecs.integer.nullable(),
        nullable: true,

        integerBits: 16,
      ),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "owners",
    columns: [
      Column("id", Codecs.integer),
      Column("sample_id", Codecs.integer, integerBits: 32),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["sample_id"], "samples", ["id"], onDelete: "RESTRICT"),
    ],
  ),
]);
