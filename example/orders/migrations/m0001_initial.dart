// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/migrate.dart';
import 'package:orm/driver.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/values.dart';

const migrationChecksum =
    "ca93da95678a0a1931f609c5822541f0cf4775fba2c799381b08aaba29718c04";
final migration = Migration.steps(
  "0001_initial",
  [
    ExecuteSql(
      "CREATE TABLE \"inventory\" (\"sku\" TEXT NOT NULL, \"label\" TEXT NOT NULL, \"available\" INTEGER NOT NULL, \"unit_price_cents\" INTEGER NOT NULL, PRIMARY KEY (\"sku\"), CONSTRAINT \"nonnegative_inventory\" CHECK (available >= 0\n), CONSTRAINT \"price_range\" CHECK (unit_price_cents >= 0 AND unit_price_cents <= 100000000\n))",
    ),
    ExecuteSql(
      "CREATE TABLE \"order_lines\" (\"order_id\" INTEGER NOT NULL, \"sku\" TEXT NOT NULL, \"label\" TEXT NOT NULL, \"quantity\" INTEGER NOT NULL, \"unit_price_cents\" INTEGER NOT NULL, PRIMARY KEY (\"order_id\", \"sku\"), CONSTRAINT \"positive_quantity\" CHECK (quantity > 0\n), CONSTRAINT \"nonnegative_line_price\" CHECK (unit_price_cents >= 0\n), FOREIGN KEY (\"order_id\") REFERENCES \"purchase_orders\" (\"id\") ON DELETE CASCADE, FOREIGN KEY (\"sku\") REFERENCES \"inventory\" (\"sku\") ON DELETE RESTRICT)",
    ),
    ExecuteSql(
      "CREATE TABLE \"purchase_orders\" (\"id\" INTEGER PRIMARY KEY NOT NULL, \"customer_id\" TEXT NOT NULL, \"request_key\" TEXT NOT NULL, \"request_payload\" TEXT NOT NULL, \"total_cents\" INTEGER NOT NULL, \"note\" TEXT, \"placed_at\" TEXT COLLATE \"orm_instant_v1\" NOT NULL, UNIQUE (\"customer_id\", \"request_key\"), CONSTRAINT \"nonnegative_total\" CHECK (total_cents >= 0\n))",
    ),
  ],
  dialect: SqlDialect.sqlite,

  snapshot: _schema,
);

final _schema = SchemaSnapshot([
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
