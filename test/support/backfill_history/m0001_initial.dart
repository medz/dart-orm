// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

const migrationChecksum =
    "1128370fc398415be97d11f7d44184eb3ec9b2d8e9fce8e7106e1a3cb6b68026";
final migration = Migration.steps("0001_initial", {
  SqlDialect.sqlite: [
    ExecuteSql(
      "CREATE TABLE \"payload\" (\"id\" INTEGER NOT NULL, \"source\" TEXT, \"value\" TEXT, \"touches\" INTEGER NOT NULL DEFAULT (0), PRIMARY KEY (\"id\"))",
    ),
  ],
  SqlDialect.postgres: [
    ExecuteSql(
      "CREATE TABLE \"payload\" (\"id\" BIGINT NOT NULL, \"source\" TEXT, \"value\" TEXT, \"touches\" BIGINT NOT NULL DEFAULT (0), PRIMARY KEY (\"id\"))",
    ),
  ],
}, snapshot: _schema);

final _schema = SchemaSnapshot([
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
]);
