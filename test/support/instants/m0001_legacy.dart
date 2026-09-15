// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

const migrationChecksum =
    "3796f4361abf4ae7a9aaee65f7130958083c34f03e23e92679ecca5dbf19f7d6";
final migration = Migration.steps("0001_legacy", {
  SqlDialect.sqlite: [
    ExecuteSql(
      "CREATE TABLE \"moments\" (\"at\" TEXT NOT NULL, \"label\" TEXT NOT NULL DEFAULT ('pending'), PRIMARY KEY (\"at\"))",
    ),
  ],
  SqlDialect.postgres: [
    ExecuteSql(
      "CREATE TABLE \"moments\" (\"at\" TIMESTAMPTZ NOT NULL, \"label\" TEXT NOT NULL DEFAULT ('pending'), PRIMARY KEY (\"at\"))",
    ),
  ],
}, snapshot: _schema);

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
