// Generated physical schema. Keep historical copies with their migration.
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
      CheckSchema("stock_nonnegative", "stock >= 0"),
      CheckSchema("nonnegative_price", "price >= 0"),
      CheckSchema("valid_discount", "discount >= 0 AND discount <= price"),
      CheckSchema("valid_state", "state IN ('draft', 'published')"),
      CheckSchema.forDialects(
        "short_label",
        sqlite: "length(label) <= 20",
        postgres: "char_length(label) <= 20",
        mysql: "length(label) <= 20",
        mariadb: "length(label) <= 20",
      ),
      CheckSchema(null, "label <> '; CHECK (0)'"),
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
