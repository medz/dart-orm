// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

const migrationChecksum =
    "096e374467b15d9025274fd9599e4f38f3ea76aa0c29e95d9d3d383119973509";
final migration = Migration.steps(
  "0001_initial",
  [
    ExecuteSql(
      "CREATE TABLE \"users\" (\"id\" INTEGER PRIMARY KEY NOT NULL, \"email\" TEXT NOT NULL, \"nickname\" TEXT, \"score\" INTEGER NOT NULL DEFAULT (0), UNIQUE (\"email\"))",
    ),
    ExecuteSql(
      "CREATE TABLE \"posts\" (\"id\" INTEGER PRIMARY KEY NOT NULL, \"author_id\" INTEGER NOT NULL, \"title\" TEXT NOT NULL, \"created_at\" TEXT COLLATE \"orm_instant_v1\" NOT NULL, FOREIGN KEY (\"author_id\") REFERENCES \"users\" (\"id\") ON DELETE CASCADE)",
    ),
    ExecuteSql(
      "CREATE INDEX \"author_timeline\" ON \"posts\" (\"author_id\", \"created_at\", \"id\")",
    ),
  ],
  dialect: SqlDialect.sqlite,

  snapshot: _schema,
);

final _schema = SchemaSnapshot([
  TableSchema(
    "users",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("email", Codecs.text),
      Column("nickname", Codecs.text.nullable(), nullable: true),
      Column("score", Codecs.integer, defaultSql: "0"),
    ],
    primaryKey: ["id"],
    uniqueKeys: [
      ["email"],
    ],
  ),
  TableSchema(
    "posts",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("author_id", Codecs.integer),
      Column("title", Codecs.text),
      Column("created_at", Codecs.dateTime),
    ],
    primaryKey: ["id"],

    indexes: [
      IndexSchema("author_timeline", [
        "author_id",
        "created_at",
        "id",
      ], unique: false),
    ],
    foreignKeys: [
      ForeignKey(["author_id"], "users", ["id"], onDelete: "CASCADE"),
    ],
  ),
]);
