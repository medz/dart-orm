// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

const migrationChecksum =
    "7d8f21cfbd5b8679955009c1df45a46ab5d4dbbfec38b41f19dc5bc0c76864f9";
final migration = Migration.steps(
  "0001_legacy",
  [
    ExecuteSql(
      "CREATE TABLE \"moments\" (\"at\" TIMESTAMPTZ NOT NULL, \"label\" TEXT NOT NULL DEFAULT ('pending'), PRIMARY KEY (\"at\"))",
    ),
  ],
  dialect: SqlDialect.postgres,

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
