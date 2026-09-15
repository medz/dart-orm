// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "products",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("stock", Codecs.integer, defaultSql: "0", integerBits: 16),
      Column("price", Codecs.real),
      Column("discount", Codecs.real.nullable(), nullable: true),
      Column("state", Codecs.text),
      Column("label", Codecs.text.nullable(), nullable: true),
    ],
    primaryKey: ["id"],

    checks: [
      CheckSchema.forDialects(
        "stock_nonnegative",
        sqlite: "stock >= 0",
        postgres: "stock >= 0",
      ),
      CheckSchema.forDialects(
        "nonnegative_price",
        sqlite: "price >= 0",
        postgres: "price >= 0",
      ),
      CheckSchema.forDialects(
        "valid_discount",
        sqlite: "discount >= 0 AND discount <= price",
        postgres: "discount >= 0 AND discount <= price",
      ),
      CheckSchema.forDialects(
        "valid_state",
        sqlite: "state IN ('draft', 'published')",
        postgres: "state IN ('draft', 'published')",
      ),
      CheckSchema.forDialects(
        "short_label",
        sqlite: "length(label) <= 20",
        postgres: "char_length(label) <= 20",
      ),
      CheckSchema.forDialects(
        null,
        sqlite: "label <> '; CHECK (0)'",
        postgres: "label <> '; CHECK (0)'",
      ),
    ],
  ),
  TableSchema(
    "lines",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("product_id", Codecs.integer),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["product_id"], "products", ["id"], onDelete: "RESTRICT"),
    ],
  ),
]);
