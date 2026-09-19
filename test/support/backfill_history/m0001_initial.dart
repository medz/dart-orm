// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/migrate.dart';

const migrationChecksum =
    "6ae96fc86455fff28e371472abe7df745f461f67cd4a6fd1fb0600b7cb5dcccb";
final migration = Migration.steps(
  "0001_initial",
  [
    ExecuteSql(
      "CREATE TABLE \"payload\" (\"id\" INTEGER NOT NULL, \"source\" TEXT, \"value\" TEXT, \"touches\" INTEGER NOT NULL DEFAULT (0), PRIMARY KEY (\"id\"))",
    ),
  ],
  dialect: SqlDialect.sqlite,

  snapshot: _schema,
);

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
