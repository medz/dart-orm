// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "moments",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("clock", Codecs.time, temporalPrecision: 3),
      Column("local", Codecs.localDateTime, temporalPrecision: 3),
      Column("instant", Codecs.dateTime, temporalPrecision: 0),
      Column(
        "optional",
        Codecs.time.nullable(),
        nullable: true,

        temporalPrecision: 2,
      ),
      Column(
        "defaulted",
        Codecs.time,

        defaultSql: "'23:59:59.9995'",

        temporalPrecision: 3,
      ),
      Column(
        "rounded",
        Codecs.time,

        computed: ComputedColumn.forDialects(
          sqlite: "\"clock\"",
          postgres: "\"clock\"",
          storage: ComputedStorage.stored,
        ),

        temporalPrecision: 0,
      ),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "slots",
    columns: [
      Column("time", Codecs.time, temporalPrecision: 3),
      Column("label", Codecs.text),
    ],
    primaryKey: ["time"],
  ),
  TableSchema(
    "bookings",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("time", Codecs.time, temporalPrecision: 3),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["time"], "slots", ["time"], onDelete: "RESTRICT"),
    ],
  ),
]);
