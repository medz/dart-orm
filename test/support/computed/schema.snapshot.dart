// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "lines",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("price", Codecs.integer),
      Column("quantity", Codecs.integer),
      Column("label", Codecs.text),
      Column("note", Codecs.text.nullable(), nullable: true),
      Column(
        "total",
        Codecs.integer,

        computed: ComputedColumn(
          "price * quantity",
          storage: ComputedStorage.stored,
        ),
      ),
      Column(
        "label_size",
        Codecs.integer,

        computed: ComputedColumn.forDialects(
          sqlite: "length(label)",
          postgres: "char_length(label)",
          mysql: "length(label)",
          mariadb: "length(label)",
          storage: ComputedStorage.virtual,
        ),
      ),
      Column(
        "normalized_note",
        Codecs.text.nullable(),
        nullable: true,

        computed: ComputedColumn(
          "upper(note)",
          storage: ComputedStorage.stored,
        ),
      ),
    ],
    primaryKey: ["id"],

    indexes: [
      IndexSchema("by_total", ["total"], unique: false),
    ],

    checks: [CheckSchema("nonnegative", "price >= 0 AND quantity >= 0")],
  ),
  TableSchema(
    "bands",
    columns: [Column("id", Codecs.integer), Column("name", Codecs.text)],
    primaryKey: ["id"],
  ),
]);
