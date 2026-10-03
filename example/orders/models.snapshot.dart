// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/values.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "inventory",
    columns: [
      Column("sku", Codecs.text),
      Column("label", Codecs.text),
      Column("available", Codecs.integer),
      Column("unit_price_cents", Codecs.integer),
    ],
    primaryKey: ["sku"],

    checks: [
      CheckSchema("nonnegative_inventory", "available >= 0"),
      CheckSchema(
        "price_range",
        "unit_price_cents >= 0 AND unit_price_cents <= 100000000",
      ),
    ],
  ),
  TableSchema(
    "order_lines",
    columns: [
      Column("order_id", Codecs.integer),
      Column("sku", Codecs.text),
      Column("label", Codecs.text),
      Column("quantity", Codecs.integer),
      Column("unit_price_cents", Codecs.integer),
    ],
    primaryKey: ["order_id", "sku"],

    foreignKeys: [
      ForeignKey(["order_id"], "purchase_orders", ["id"], onDelete: "CASCADE"),
      ForeignKey(["sku"], "inventory", ["sku"], onDelete: "RESTRICT"),
    ],
    checks: [
      CheckSchema("positive_quantity", "quantity > 0"),
      CheckSchema("nonnegative_line_price", "unit_price_cents >= 0"),
    ],
  ),
  TableSchema(
    "purchase_orders",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("customer_id", Codecs.text),
      Column("request_key", Codecs.text),
      Column("request_payload", Codecs.text),
      Column("total_cents", Codecs.integer),
      Column("note", Codecs.text.nullable(), nullable: true),
      Column("placed_at", Codecs.dateTime),
    ],
    primaryKey: ["id"],
    uniqueKeys: [
      ["customer_id", "request_key"],
    ],

    checks: [CheckSchema("nonnegative_total", "total_cents >= 0")],
  ),
]);
