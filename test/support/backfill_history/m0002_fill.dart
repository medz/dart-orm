// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

const migrationChecksum =
    "f79463cf4d8de945c22f390e27c1c0b428a45abd7fe1111b040adf8c66e3920f";
final migration = Migration.steps(
  "0002_fill",
  {
    SqlDialect.sqlite: [
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
    SqlDialect.postgres: [
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
  },
  previous: "1128370fc398415be97d11f7d44184eb3ec9b2d8e9fce8e7106e1a3cb6b68026",
);
