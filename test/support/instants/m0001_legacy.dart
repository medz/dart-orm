// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/migrate.dart';

const migrationChecksum =
    "f7c0a7ff8af0bf106e3deabaa36c4816337ae6937350dc14a44edcaab34456ab";
final migration = Migration.steps(
  "0001_legacy",
  [
    ExecuteSql(
      "CREATE TABLE \"moments\" (\"at\" TEXT NOT NULL, \"label\" TEXT NOT NULL DEFAULT ('pending'), PRIMARY KEY (\"at\"))",
    ),
  ],
  dialect: SqlDialect.sqlite,

  snapshot: _schema,
);

final _schema = SchemaSnapshot([
  TableSchema(
    "moments",
    columns: [
      Column("at", Codec<Object?>('timestamp', (v) => v, (v) => v)),
      Column("label", Codecs.text, defaultSql: "'pending'"),
    ],
    primaryKey: ["at"],
  ),
]);
