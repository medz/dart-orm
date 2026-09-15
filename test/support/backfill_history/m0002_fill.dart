// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

const migrationChecksum =
    "76c394c428c4609366b3028b1770b0919b48276b037438b9ce2cea878035c08b";
final migration = Migration.steps(
  "0002_fill",
  [
    Backfill(
      TableSchema(
        "payload",
        columns: [
          Column("id", Codecs.integer),
          Column("source", Codecs.text.nullable(), nullable: true),
          Column("value", Codecs.text.nullable(), nullable: true),
          Column("touches", Codecs.integer, defaultSql: "0"),
        ],
        primaryKey: ["id"],
      ),
      set: {"value": "upper(source)", "touches": "touches + 1"},
      where: "value IS NULL",
      doneWhen: "SELECT NOT EXISTS(SELECT 1 FROM payload WHERE value IS NULL OR touches <> 1)",
      batchSize: 3,
    ),
  ],
  dialect: SqlDialect.sqlite,
  previous: "6ae96fc86455fff28e371472abe7df745f461f67cd4a6fd1fb0600b7cb5dcccb",
);
