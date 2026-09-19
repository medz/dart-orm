// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/migrate.dart';

const migrationChecksum =
    "2967a6b4178d2061acad6451e497c7709f82d674a190caa938a765a32accec26";
final migration = Migration.steps(
  "0002_comments",
  [
    ExecuteSql(
      "CREATE TABLE \"comments\" (\"id\" INTEGER PRIMARY KEY NOT NULL, \"note_id\" INTEGER NOT NULL, \"text\" TEXT NOT NULL, FOREIGN KEY (\"note_id\") REFERENCES \"notes\" (\"id\") ON DELETE CASCADE)",
    ),
    ExecuteSql(
      "ALTER TABLE \"notes\" ADD COLUMN \"done\" INTEGER NOT NULL DEFAULT (false)",
    ),
  ],
  dialect: SqlDialect.sqlite,
  previous: "eb8478c032ecf4fd28752a34ee1b74b503ae8708c0f6ef851856c63ac02c2252",
  snapshot: _schema,
);

final _schema = SchemaSnapshot([
  TableSchema(
    "notes",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("body", Codecs.text),
      Column("done", Codecs.boolean, defaultSql: "false"),
      Column("created_at", Codecs.dateTime),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "comments",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("note_id", Codecs.integer),
      Column("text", Codecs.text),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["note_id"], "notes", ["id"], onDelete: "CASCADE"),
    ],
  ),
]);
