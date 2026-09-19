// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show User, Post, Value, Reading;

import 'dart:typed_data';

final _usersId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _usersEmail = Column<String>(
  "email",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _usersNickname = Column<String?>(
  "nickname",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
  clientDefault: models.defaultNickname,
);
final _usersEmailSize = Column<int>(
  "email_size",
  Codecs.integer,
  nullable: false,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "length(email)",
    postgres: "length(email)",
    mysql: "length(email)",
    mariadb: "length(email)",
    storage: ComputedStorage.stored,
  ),
);
final _usersUpperNickname = Column<String?>(
  "upper_nickname",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
  computed: ComputedColumn.forDialects(
    sqlite: "upper(nickname)",
    postgres: "upper(nickname)",
    mysql: "upper(nickname)",
    mariadb: "upper(nickname)",
    storage: ComputedStorage.virtual,
  ),
);
final usersSchema = TableSchema(
  "users",
  columns: [
    _usersId,
    _usersEmail,
    _usersNickname,
    _usersEmailSize,
    _usersUpperNickname,
  ],
  primaryKey: ["id"],
  uniqueKeys: [
    ["email"],
  ],
  indexes: [],
  checks: [
    CheckSchema.forDialects(
      "valid_email",
      sqlite: "length(email) > 0",
      postgres: "length(email) > 0",
      mysql: "length(email) > 0",
      mariadb: "length(email) > 0",
    ),
  ],
  foreignKeys: [],
);

final class UsersFields extends Fields {
  UsersFields(super.table);
  late final id = column(_usersId);
  late final email = column(_usersEmail);
  late final nickname = column(_usersNickname);
  late final emailSize = readColumn(_usersEmailSize);
  late final upperNickname = readColumn(_usersUpperNickname);
  Relation<models.Post, PostsFields> get posts =>
      Relation(postsTable, parent: [id], child: (row) => [row.authorId]);
}

final usersTable = Table<models.User, UsersFields>(
  usersSchema,
  UsersFields.new,
  (row) =>
      (row.id, row.email, row.nickname, row.emailSize, row.upperNickname).map(
        (id, email, nickname, emailSize, upperNickname) => (
          id: id,
          email: email,
          nickname: nickname,
          emailSize: emailSize,
          upperNickname: upperNickname,
        ),
      ),
);

final class UsersTableSet extends TableSet<models.User, UsersFields> {
  UsersTableSet(QueryContext db) : super(db, usersTable) {
    db.registerSchema(appSchema);
  }
  Future<models.User> create({
    Change<int> id = const Change.keep(),
    required String email,
    Change<String?> nickname = const Change.keep(),
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.email.set(email),
      ...row.nickname.change(nickname),
    ],
  );
  Query<models.User, UsersFields> byId(int id) => where((row) => row.id.eq(id));
}

extension UsersUpdates on Query<models.User, UsersFields> {
  Future<int> patch({
    Change<String> email = const Change.keep(),
    Change<String?> nickname = const Change.keep(),
  }) => update(
    (row) => [...row.email.change(email), ...row.nickname.change(nickname)],
  ).execute();
}

final _postsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _postsAuthorId = Column<int>(
  "author_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _postsTitle = Column<String>(
  "title",
  Codecs.text,
  nullable: false,
  generated: false,
);
final postsSchema = TableSchema(
  "posts",
  columns: [_postsId, _postsAuthorId, _postsTitle],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["author_id"], "users", ["id"], onDelete: "CASCADE"),
  ],
);

final class PostsFields extends Fields {
  PostsFields(super.table);
  late final id = column(_postsId);
  late final authorId = column(_postsAuthorId);
  late final title = column(_postsTitle);
  Relation<models.User, UsersFields> get author =>
      Relation(usersTable, parent: [authorId], child: (row) => [row.id]);
}

final postsTable = Table<models.Post, PostsFields>(
  postsSchema,
  PostsFields.new,
  (row) => (
    row.id,
    row.authorId,
    row.title,
  ).map((id, authorId, title) => (id: id, authorId: authorId, title: title)),
);

final class PostsTableSet extends TableSet<models.Post, PostsFields> {
  PostsTableSet(QueryContext db) : super(db, postsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Post> create({
    Change<int> id = const Change.keep(),
    required int authorId,
    required String title,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.authorId.set(authorId),
      row.title.set(title),
    ],
  );
  Query<models.Post, PostsFields> byId(int id) => where((row) => row.id.eq(id));
}

extension PostsUpdates on Query<models.Post, PostsFields> {
  Future<int> patch({
    Change<int> authorId = const Change.keep(),
    Change<String> title = const Change.keep(),
  }) => update(
    (row) => [...row.authorId.change(authorId), ...row.title.change(title)],
  ).execute();
}

final _valuesId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _valuesWide = Column<BigInt>(
  "wide",
  Codecs.bigint,
  nullable: false,
  generated: false,
);
final _valuesBytes = Column<Uint8List>(
  "bytes",
  Codecs.bytes,
  nullable: false,
  generated: false,
);
final _valuesAmount = Column<Decimal>(
  "amount",
  Codecs.decimal,
  nullable: false,
  generated: false,
);
final _valuesDay = Column<LocalDate>(
  "day",
  Codecs.date,
  nullable: false,
  generated: false,
);
final _valuesTime = Column<LocalTime>(
  "time",
  Codecs.time,
  nullable: false,
  generated: false,
);
final _valuesStamp = Column<LocalDateTime>(
  "stamp",
  Codecs.localDateTime,
  nullable: false,
  generated: false,
);
final _valuesInstant = Column<DateTime>(
  "instant",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final valuesSchema = TableSchema(
  "values",
  columns: [
    _valuesId,
    _valuesWide,
    _valuesBytes,
    _valuesAmount,
    _valuesDay,
    _valuesTime,
    _valuesStamp,
    _valuesInstant,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class ValuesFields extends Fields {
  ValuesFields(super.table);
  late final id = column(_valuesId);
  late final wide = column(_valuesWide);
  late final bytes = column(_valuesBytes);
  late final amount = column(_valuesAmount);
  late final day = column(_valuesDay);
  late final time = column(_valuesTime);
  late final stamp = column(_valuesStamp);
  late final instant = column(_valuesInstant);
}

final valuesTable = Table<models.Value, ValuesFields>(
  valuesSchema,
  ValuesFields.new,
  (row) =>
      (
        (row.id, row.wide, row.bytes, row.amount, row.day).map(
          (id, wide, bytes, amount, day) =>
              (id: id, wide: wide, bytes: bytes, amount: amount, day: day),
        ),
        (row.time, row.stamp, row.instant).map(
          (time, stamp, instant) =>
              (time: time, stamp: stamp, instant: instant),
        ),
      ).map(
        (left, right) => (
          id: left.id,
          wide: left.wide,
          bytes: left.bytes,
          amount: left.amount,
          day: left.day,
          time: right.time,
          stamp: right.stamp,
          instant: right.instant,
        ),
      ),
);

final class ValuesTableSet extends TableSet<models.Value, ValuesFields> {
  ValuesTableSet(QueryContext db) : super(db, valuesTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Value> create({
    Change<int> id = const Change.keep(),
    required BigInt wide,
    required Uint8List bytes,
    required Decimal amount,
    required LocalDate day,
    required LocalTime time,
    required LocalDateTime stamp,
    required DateTime instant,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.wide.set(wide),
      row.bytes.set(bytes),
      row.amount.set(amount),
      row.day.set(day),
      row.time.set(time),
      row.stamp.set(stamp),
      row.instant.set(instant),
    ],
  );
  Query<models.Value, ValuesFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension ValuesUpdates on Query<models.Value, ValuesFields> {
  Future<int> patch({
    Change<BigInt> wide = const Change.keep(),
    Change<Uint8List> bytes = const Change.keep(),
    Change<Decimal> amount = const Change.keep(),
    Change<LocalDate> day = const Change.keep(),
    Change<LocalTime> time = const Change.keep(),
    Change<LocalDateTime> stamp = const Change.keep(),
    Change<DateTime> instant = const Change.keep(),
  }) => update(
    (row) => [
      ...row.wide.change(wide),
      ...row.bytes.change(bytes),
      ...row.amount.change(amount),
      ...row.day.change(day),
      ...row.time.change(time),
      ...row.stamp.change(stamp),
      ...row.instant.change(instant),
    ],
  ).execute();
}

final _readingsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _readingsValue = Column<double>(
  "value",
  Codecs.real,
  nullable: false,
  generated: false,
);
final readingsSchema = TableSchema(
  "readings",
  columns: [_readingsId, _readingsValue],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class ReadingsFields extends Fields {
  ReadingsFields(super.table);
  late final id = column(_readingsId);
  late final value = column(_readingsValue);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Reading, ReadingsFields> get peers =>
      Relation(readingsTable, parent: [value], child: (row) => [row.value]);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Reading, ReadingsFields> get sameReading => Relation(
    readingsTable,
    parent: [value, id],
    child: (row) => [row.value, row.id],
  );
}

final readingsTable = Table<models.Reading, ReadingsFields>(
  readingsSchema,
  ReadingsFields.new,
  (row) => (row.id, row.value).map((id, value) => (id: id, value: value)),
);

final class ReadingsTableSet extends TableSet<models.Reading, ReadingsFields> {
  ReadingsTableSet(QueryContext db) : super(db, readingsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Reading> create({required int id, required double value}) =>
      createRow((row) => [row.id.set(id), row.value.set(value)]);
  Query<models.Reading, ReadingsFields> byId(int id) =>
      where((row) => row.id.eq(id));
}

extension ReadingsUpdates on Query<models.Reading, ReadingsFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<double> value = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.value.change(value)])
          .execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  usersSchema,
  postsSchema,
  valuesSchema,
  readingsSchema,
]);

extension AppTables on QueryContext {
  UsersTableSet get users => UsersTableSet(this);
  PostsTableSet get posts => PostsTableSet(this);
  ValuesTableSet get values => ValuesTableSet(this);
  ReadingsTableSet get readings => ReadingsTableSet(this);
}
