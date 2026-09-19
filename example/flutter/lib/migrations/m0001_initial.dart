// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/migrate.dart';

const migrationChecksum =
    "eb8478c032ecf4fd28752a34ee1b74b503ae8708c0f6ef851856c63ac02c2252";
final migration = Migration.steps(
  "0001_initial",
  [
    ExecuteSql(
      "CREATE TABLE \"notes\" (\"id\" INTEGER PRIMARY KEY NOT NULL, \"body\" TEXT NOT NULL, \"created_at\" TEXT COLLATE \"orm_instant_v1\" NOT NULL)",
    ),
  ],
  dialect: SqlDialect.sqlite,

  snapshot: _schema,
);

final _schema = SchemaSnapshot([
  TableSchema(
    "notes",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("body", Codecs.text),
      Column("created_at", Codecs.dateTime),
    ],
    primaryKey: ["id"],
  ),
]);
