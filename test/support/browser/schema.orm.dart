// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show User, Post, Value, Reading;

import 'dart:typed_data';

final _postId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _postAuthorId = Column<int>(
  "author_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _postTitle = Column<String>(
  "title",
  Codecs.text,
  nullable: false,
  generated: false,
);
final postSchema = TableSchema(
  "posts",
  columns: [_postId, _postAuthorId, _postTitle],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["author_id"], "users", ["id"], onDelete: "CASCADE"),
  ],
);

final class PostFields extends Fields {
  PostFields(super.table);
  late final id = column(_postId);
  late final authorId = column(_postAuthorId);
  late final title = column(_postTitle);
  Relation<models.User, UserFields> get author =>
      Relation(userTable, parent: [authorId], child: (row) => [row.id]);
}

final postTable = Table<models.Post, PostFields>(
  postSchema,
  PostFields.new,
  (row) => (
    row.id,
    row.authorId,
    row.title,
  ).map((v0, v1, v2) => models.Post(id: v0, authorId: v1, title: v2)),
);

final class PostTableSet extends TableSet<models.Post, PostFields> {
  PostTableSet(QueryContext db) : super(db, postTable) {
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
  Query<models.Post, PostFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension PostUpdates on Query<models.Post, PostFields> {
  Future<int> patch({
    Change<int> authorId = const Change.keep(),
    Change<String> title = const Change.keep(),
  }) => update(
    (row) => [...row.authorId.change(authorId), ...row.title.change(title)],
  ).execute();
}

final _readingId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _readingValue = Column<double>(
  "value",
  Codecs.real,
  nullable: false,
  generated: false,
);
final readingSchema = TableSchema(
  "readings",
  columns: [_readingId, _readingValue],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class ReadingFields extends Fields {
  ReadingFields(super.table);
  late final id = column(_readingId);
  late final value = column(_readingValue);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Reading, ReadingFields> get peers =>
      Relation(readingTable, parent: [value], child: (row) => [row.value]);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Reading, ReadingFields> get sameReading => Relation(
    readingTable,
    parent: [id, value],
    child: (row) => [row.id, row.value],
  );
}

final readingTable = Table<models.Reading, ReadingFields>(
  readingSchema,
  ReadingFields.new,
  (row) =>
      (row.id, row.value).map((v0, v1) => models.Reading(id: v0, value: v1)),
);

final class ReadingTableSet extends TableSet<models.Reading, ReadingFields> {
  ReadingTableSet(QueryContext db) : super(db, readingTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Reading> create({required int id, required double value}) =>
      createRow((row) => [row.id.set(id), row.value.set(value)]);
  Query<models.Reading, ReadingFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension ReadingUpdates on Query<models.Reading, ReadingFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<double> value = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.value.change(value)])
          .execute();
}

final _userId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _userEmail = Column<String>(
  "email",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _userNickname = Column<String?>(
  "nickname",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
  clientDefault: models.defaultNickname,
);
final _userEmailSize = Column<int>(
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
final _userUpperNickname = Column<String?>(
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
final userSchema = TableSchema(
  "users",
  columns: [
    _userId,
    _userEmail,
    _userNickname,
    _userEmailSize,
    _userUpperNickname,
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

final class UserFields extends Fields {
  UserFields(super.table);
  late final id = column(_userId);
  late final email = column(_userEmail);
  late final nickname = column(_userNickname);
  late final emailSize = readColumn(_userEmailSize);
  late final upperNickname = readColumn(_userUpperNickname);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Post, PostFields> get posts =>
      Relation(postTable, parent: [id], child: (row) => [row.authorId]);
}

final userTable = Table<models.User, UserFields>(
  userSchema,
  UserFields.new,
  (row) =>
      (row.id, row.email, row.nickname, row.emailSize, row.upperNickname).map(
        (v0, v1, v2, v3, v4) => models.User(
          id: v0,
          email: v1,
          nickname: v2,
          emailSize: v3,
          upperNickname: v4,
        ),
      ),
);

final class UserTableSet extends TableSet<models.User, UserFields> {
  UserTableSet(QueryContext db) : super(db, userTable) {
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
  Query<models.User, UserFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension UserUpdates on Query<models.User, UserFields> {
  Future<int> patch({
    Change<String> email = const Change.keep(),
    Change<String?> nickname = const Change.keep(),
  }) => update(
    (row) => [...row.email.change(email), ...row.nickname.change(nickname)],
  ).execute();
}

final _valueId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _valueWide = Column<BigInt>(
  "wide",
  Codecs.bigint,
  nullable: false,
  generated: false,
);
final _valueBytes = Column<Uint8List>(
  "bytes",
  Codecs.bytes,
  nullable: false,
  generated: false,
);
final _valueAmount = Column<Decimal>(
  "amount",
  Codecs.decimal,
  nullable: false,
  generated: false,
);
final _valueDay = Column<LocalDate>(
  "day",
  Codecs.date,
  nullable: false,
  generated: false,
);
final _valueTime = Column<LocalTime>(
  "time",
  Codecs.time,
  nullable: false,
  generated: false,
);
final _valueStamp = Column<LocalDateTime>(
  "stamp",
  Codecs.localDateTime,
  nullable: false,
  generated: false,
);
final _valueInstant = Column<DateTime>(
  "instant",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final valueSchema = TableSchema(
  "values",
  columns: [
    _valueId,
    _valueWide,
    _valueBytes,
    _valueAmount,
    _valueDay,
    _valueTime,
    _valueStamp,
    _valueInstant,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class ValueFields extends Fields {
  ValueFields(super.table);
  late final id = column(_valueId);
  late final wide = column(_valueWide);
  late final bytes = column(_valueBytes);
  late final amount = column(_valueAmount);
  late final day = column(_valueDay);
  late final time = column(_valueTime);
  late final stamp = column(_valueStamp);
  late final instant = column(_valueInstant);
}

final valueTable = Table<models.Value, ValueFields>(
  valueSchema,
  ValueFields.new,
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
        (left, right) => models.Value(
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

final class ValueTableSet extends TableSet<models.Value, ValueFields> {
  ValueTableSet(QueryContext db) : super(db, valueTable) {
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
  Query<models.Value, ValueFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension ValueUpdates on Query<models.Value, ValueFields> {
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

final appSchema = List<TableSchema>.unmodifiable([
  postSchema,
  readingSchema,
  userSchema,
  valueSchema,
]);

extension AppTables on QueryContext {
  PostTableSet get post => PostTableSet(this);
  ReadingTableSet get reading => ReadingTableSet(this);
  UserTableSet get user => UserTableSet(this);
  ValueTableSet get value => ValueTableSet(this);
}
