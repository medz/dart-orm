// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';

final schema = SchemaSnapshot([
  TableSchema(
    "users",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("email", Codecs.text),
      Column("nickname", Codecs.text.nullable(), nullable: true),
      Column(
        "email_size",
        Codecs.integer,

        computed: ComputedColumn.forDialects(
          sqlite: "length(email)",
          postgres: "length(email)",
          storage: ComputedStorage.stored,
        ),
      ),
      Column(
        "upper_nickname",
        Codecs.text.nullable(),
        nullable: true,

        computed: ComputedColumn.forDialects(
          sqlite: "upper(nickname)",
          postgres: "upper(nickname)",
          storage: ComputedStorage.virtual,
        ),
      ),
    ],
    primaryKey: ["id"],
    uniqueKeys: [
      ["email"],
    ],

    checks: [
      CheckSchema.forDialects(
        "valid_email",
        sqlite: "length(email) > 0",
        postgres: "length(email) > 0",
      ),
    ],
  ),
  TableSchema(
    "posts",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("author_id", Codecs.integer),
      Column("title", Codecs.text),
    ],
    primaryKey: ["id"],

    foreignKeys: [
      ForeignKey(["author_id"], "users", ["id"], onDelete: "CASCADE"),
    ],
  ),
  TableSchema(
    "values",
    columns: [
      Column("id", Codecs.integer, generated: true),
      Column("wide", Codecs.bigint),
      Column("bytes", Codecs.bytes),
      Column("amount", Codecs.decimal),
      Column("day", Codecs.date),
      Column("time", Codecs.time),
      Column("stamp", Codecs.localDateTime),
      Column("instant", Codecs.dateTime),
    ],
    primaryKey: ["id"],
  ),
  TableSchema(
    "readings",
    columns: [Column("id", Codecs.integer), Column("value", Codecs.real)],
    primaryKey: ["id"],
  ),
]);
