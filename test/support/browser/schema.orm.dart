// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show User, Post, Value, Reading;

import 'dart:typed_data';

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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

/// Immutable input data; composition belongs to [postPatch], not field names.
final class PostPatch {
  final WriteValue<int, PostFields> authorId;
  final WriteValue<String, PostFields> title;
  PostPatch._({required this.authorId, required this.title});

  List<Assignment> _assignments(PostFields fields) => [
    ...fields.authorId.write(authorId, fields),
    ...fields.title.write(title, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PostPatchFactory {
  PostPatch call({int authorId, String title});
  PostPatch values({
    WriteValue<int, PostFields> authorId = const .keep(),
    WriteValue<String, PostFields> title = const .keep(),
  });
  PostPatch overlay(Iterable<PostPatch> layers);
  bool isEmpty(PostPatch input);
}

const PostPatchFactory postPatch = _PostPatchFactory();

final class _PostPatchFactory implements PostPatchFactory {
  const _PostPatchFactory();
  @override
  PostPatch call({
    Object? authorId = _writeAbsent,
    Object? title = _writeAbsent,
  }) => PostPatch._(
    authorId: _writeLiteral<int, PostFields>(authorId),
    title: _writeLiteral<String, PostFields>(title),
  );
  @override
  PostPatch values({
    WriteValue<int, PostFields> authorId = const .keep(),
    WriteValue<String, PostFields> title = const .keep(),
  }) => PostPatch._(authorId: authorId, title: title);
  @override
  PostPatch overlay(Iterable<PostPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = PostPatch._(
        authorId: WriteValue.overlay(earlier.authorId, later.authorId),
        title: WriteValue.overlay(earlier.title, later.title),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(PostPatch input) =>
      input.authorId.isMissing && input.title.isMissing;
}

/// Immutable input data; composition belongs to [postInsert], not field names.
final class PostInsert {
  final WriteValue<int, PostFields> id;
  final WriteValue<int, PostFields> authorId;
  final WriteValue<String, PostFields> title;
  PostInsert._({
    required this.id,
    required this.authorId,
    required this.title,
  }) {
    if (authorId.isMissing) {
      throw ArgumentError.value(authorId, 'authorId', 'Must be supplied.');
    }
    if (title.isMissing) {
      throw ArgumentError.value(title, 'title', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(PostFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.authorId.write(authorId, fields),
    ...fields.title.write(title, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PostInsertFactory {
  PostInsert call({int id, required int authorId, required String title});
  PostInsert values({
    WriteValue<int, PostFields> id = const .keep(),
    required WriteValue<int, PostFields> authorId,
    required WriteValue<String, PostFields> title,
  });
  PostInsert overlay(PostInsert earlier, Iterable<PostPatch> layers);
}

const PostInsertFactory postInsert = _PostInsertFactory();

final class _PostInsertFactory implements PostInsertFactory {
  const _PostInsertFactory();
  @override
  PostInsert call({
    Object? id = _writeAbsent,
    required int authorId,
    required String title,
  }) => PostInsert._(
    id: _writeLiteral<int, PostFields>(id),
    authorId: .set(authorId),
    title: .set(title),
  );
  @override
  PostInsert values({
    WriteValue<int, PostFields> id = const .keep(),
    required WriteValue<int, PostFields> authorId,
    required WriteValue<String, PostFields> title,
  }) => PostInsert._(id: id, authorId: authorId, title: title);
  @override
  PostInsert overlay(PostInsert earlier, Iterable<PostPatch> layers) {
    for (final later in layers) {
      earlier = PostInsert._(
        id: earlier.id,
        authorId: WriteValue.overlay(earlier.authorId, later.authorId),
        title: WriteValue.overlay(earlier.title, later.title),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Post from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class PostCreator {
  Future<models.Post> call({
    int id,
    required int authorId,
    required String title,
  });
}

final class _PostCreator implements PostCreator {
  final PostTableSet _table;
  const _PostCreator(this._table);
  @override
  Future<models.Post> call({
    Object? id = _writeAbsent,
    required int authorId,
    required String title,
  }) async => _table.plan
      .insert(
        PostInsert._(
          id: _writeLiteral<int, PostFields>(id),
          authorId: .set(authorId),
          title: .set(title),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class PostPatcher {
  Future<int> call({int authorId, String title});
}

final class _PostPatcher implements PostPatcher {
  final orm_model.ModelQuery<models.Post, PostFields, PostPatch> _query;
  const _PostPatcher(this._query);
  @override
  Future<int> call({
    Object? authorId = _writeAbsent,
    Object? title = _writeAbsent,
  }) => _query.update(
    PostPatch._(
      authorId: _writeLiteral<int, PostFields>(authorId),
      title: _writeLiteral<String, PostFields>(title),
    ),
  );
}

/// Named literal updates on a complete models.Post query.
extension PostWrites
    on orm_model.ModelQuery<models.Post, PostFields, PostPatch> {
  /// Executes one update; omitted fields remain unchanged.
  PostPatcher get patch => _PostPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class PostTableSet
    extends
        orm_model.ModelTable<models.Post, PostFields, PostInsert, PostPatch> {
  PostTableSet(QueryContext db)
    : super(
        db,
        postTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final PostCreator create = _PostCreator(this);

  orm_model.ModelQuery<models.Post, PostFields, PostPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
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

/// Immutable input data; composition belongs to [readingPatch], not field names.
final class ReadingPatch {
  final WriteValue<int, ReadingFields> id;
  final WriteValue<double, ReadingFields> value;
  ReadingPatch._({required this.id, required this.value});

  List<Assignment> _assignments(ReadingFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.value.write(value, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ReadingPatchFactory {
  ReadingPatch call({int id, double value});
  ReadingPatch values({
    WriteValue<int, ReadingFields> id = const .keep(),
    WriteValue<double, ReadingFields> value = const .keep(),
  });
  ReadingPatch overlay(Iterable<ReadingPatch> layers);
  bool isEmpty(ReadingPatch input);
}

const ReadingPatchFactory readingPatch = _ReadingPatchFactory();

final class _ReadingPatchFactory implements ReadingPatchFactory {
  const _ReadingPatchFactory();
  @override
  ReadingPatch call({
    Object? id = _writeAbsent,
    Object? value = _writeAbsent,
  }) => ReadingPatch._(
    id: _writeLiteral<int, ReadingFields>(id),
    value: _writeLiteral<double, ReadingFields>(value),
  );
  @override
  ReadingPatch values({
    WriteValue<int, ReadingFields> id = const .keep(),
    WriteValue<double, ReadingFields> value = const .keep(),
  }) => ReadingPatch._(id: id, value: value);
  @override
  ReadingPatch overlay(Iterable<ReadingPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = ReadingPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        value: WriteValue.overlay(earlier.value, later.value),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(ReadingPatch input) =>
      input.id.isMissing && input.value.isMissing;
}

/// Immutable input data; composition belongs to [readingInsert], not field names.
final class ReadingInsert {
  final WriteValue<int, ReadingFields> id;
  final WriteValue<double, ReadingFields> value;
  ReadingInsert._({required this.id, required this.value}) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (value.isMissing) {
      throw ArgumentError.value(value, 'value', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(ReadingFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.value.write(value, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ReadingInsertFactory {
  ReadingInsert call({required int id, required double value});
  ReadingInsert values({
    required WriteValue<int, ReadingFields> id,
    required WriteValue<double, ReadingFields> value,
  });
  ReadingInsert overlay(ReadingInsert earlier, Iterable<ReadingPatch> layers);
}

const ReadingInsertFactory readingInsert = _ReadingInsertFactory();

final class _ReadingInsertFactory implements ReadingInsertFactory {
  const _ReadingInsertFactory();
  @override
  ReadingInsert call({required int id, required double value}) =>
      ReadingInsert._(id: .set(id), value: .set(value));
  @override
  ReadingInsert values({
    required WriteValue<int, ReadingFields> id,
    required WriteValue<double, ReadingFields> value,
  }) => ReadingInsert._(id: id, value: value);
  @override
  ReadingInsert overlay(ReadingInsert earlier, Iterable<ReadingPatch> layers) {
    for (final later in layers) {
      earlier = ReadingInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        value: WriteValue.overlay(earlier.value, later.value),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Reading from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class ReadingCreator {
  Future<models.Reading> call({required int id, required double value});
}

final class _ReadingCreator implements ReadingCreator {
  final ReadingTableSet _table;
  const _ReadingCreator(this._table);
  @override
  Future<models.Reading> call({required int id, required double value}) async =>
      _table.plan
          .insert(ReadingInsert._(id: .set(id), value: .set(value)))
          .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class ReadingPatcher {
  Future<int> call({int id, double value});
}

final class _ReadingPatcher implements ReadingPatcher {
  final orm_model.ModelQuery<models.Reading, ReadingFields, ReadingPatch>
  _query;
  const _ReadingPatcher(this._query);
  @override
  Future<int> call({Object? id = _writeAbsent, Object? value = _writeAbsent}) =>
      _query.update(
        ReadingPatch._(
          id: _writeLiteral<int, ReadingFields>(id),
          value: _writeLiteral<double, ReadingFields>(value),
        ),
      );
}

/// Named literal updates on a complete models.Reading query.
extension ReadingWrites
    on orm_model.ModelQuery<models.Reading, ReadingFields, ReadingPatch> {
  /// Executes one update; omitted fields remain unchanged.
  ReadingPatcher get patch => _ReadingPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class ReadingTableSet
    extends
        orm_model.ModelTable<
          models.Reading,
          ReadingFields,
          ReadingInsert,
          ReadingPatch
        > {
  ReadingTableSet(QueryContext db)
    : super(
        db,
        readingTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final ReadingCreator create = _ReadingCreator(this);

  orm_model.ModelQuery<models.Reading, ReadingFields, ReadingPatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
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

/// Immutable input data; composition belongs to [userPatch], not field names.
final class UserPatch {
  final WriteValue<String, UserFields> email;
  final WriteValue<String?, UserFields> nickname;
  UserPatch._({required this.email, required this.nickname});

  List<Assignment> _assignments(UserFields fields) => [
    ...fields.email.write(email, fields),
    ...fields.nickname.write(nickname, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserPatchFactory {
  UserPatch call({String email, String? nickname});
  UserPatch values({
    WriteValue<String, UserFields> email = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
  });
  UserPatch overlay(Iterable<UserPatch> layers);
  bool isEmpty(UserPatch input);
}

const UserPatchFactory userPatch = _UserPatchFactory();

final class _UserPatchFactory implements UserPatchFactory {
  const _UserPatchFactory();
  @override
  UserPatch call({
    Object? email = _writeAbsent,
    Object? nickname = _writeAbsent,
  }) => UserPatch._(
    email: _writeLiteral<String, UserFields>(email),
    nickname: _writeLiteral<String?, UserFields>(nickname),
  );
  @override
  UserPatch values({
    WriteValue<String, UserFields> email = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
  }) => UserPatch._(email: email, nickname: nickname);
  @override
  UserPatch overlay(Iterable<UserPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = UserPatch._(
        email: WriteValue.overlay(earlier.email, later.email),
        nickname: WriteValue.overlay(earlier.nickname, later.nickname),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(UserPatch input) =>
      input.email.isMissing && input.nickname.isMissing;
}

/// Immutable input data; composition belongs to [userInsert], not field names.
final class UserInsert {
  final WriteValue<int, UserFields> id;
  final WriteValue<String, UserFields> email;
  final WriteValue<String?, UserFields> nickname;
  UserInsert._({
    required this.id,
    required this.email,
    required this.nickname,
  }) {
    if (email.isMissing) {
      throw ArgumentError.value(email, 'email', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(UserFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.email.write(email, fields),
    ...fields.nickname.write(nickname, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserInsertFactory {
  UserInsert call({int id, required String email, String? nickname});
  UserInsert values({
    WriteValue<int, UserFields> id = const .keep(),
    required WriteValue<String, UserFields> email,
    WriteValue<String?, UserFields> nickname = const .keep(),
  });
  UserInsert overlay(UserInsert earlier, Iterable<UserPatch> layers);
}

const UserInsertFactory userInsert = _UserInsertFactory();

final class _UserInsertFactory implements UserInsertFactory {
  const _UserInsertFactory();
  @override
  UserInsert call({
    Object? id = _writeAbsent,
    required String email,
    Object? nickname = _writeAbsent,
  }) => UserInsert._(
    id: _writeLiteral<int, UserFields>(id),
    email: .set(email),
    nickname: _writeLiteral<String?, UserFields>(nickname),
  );
  @override
  UserInsert values({
    WriteValue<int, UserFields> id = const .keep(),
    required WriteValue<String, UserFields> email,
    WriteValue<String?, UserFields> nickname = const .keep(),
  }) => UserInsert._(id: id, email: email, nickname: nickname);
  @override
  UserInsert overlay(UserInsert earlier, Iterable<UserPatch> layers) {
    for (final later in layers) {
      earlier = UserInsert._(
        id: earlier.id,
        email: WriteValue.overlay(earlier.email, later.email),
        nickname: WriteValue.overlay(earlier.nickname, later.nickname),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.User from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class UserCreator {
  Future<models.User> call({int id, required String email, String? nickname});
}

final class _UserCreator implements UserCreator {
  final UserTableSet _table;
  const _UserCreator(this._table);
  @override
  Future<models.User> call({
    Object? id = _writeAbsent,
    required String email,
    Object? nickname = _writeAbsent,
  }) async => _table.plan
      .insert(
        UserInsert._(
          id: _writeLiteral<int, UserFields>(id),
          email: .set(email),
          nickname: _writeLiteral<String?, UserFields>(nickname),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class UserPatcher {
  Future<int> call({String email, String? nickname});
}

final class _UserPatcher implements UserPatcher {
  final orm_model.ModelQuery<models.User, UserFields, UserPatch> _query;
  const _UserPatcher(this._query);
  @override
  Future<int> call({
    Object? email = _writeAbsent,
    Object? nickname = _writeAbsent,
  }) => _query.update(
    UserPatch._(
      email: _writeLiteral<String, UserFields>(email),
      nickname: _writeLiteral<String?, UserFields>(nickname),
    ),
  );
}

/// Named literal updates on a complete models.User query.
extension UserWrites
    on orm_model.ModelQuery<models.User, UserFields, UserPatch> {
  /// Executes one update; omitted fields remain unchanged.
  UserPatcher get patch => _UserPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class UserTableSet
    extends
        orm_model.ModelTable<models.User, UserFields, UserInsert, UserPatch> {
  UserTableSet(QueryContext db)
    : super(
        db,
        userTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final UserCreator create = _UserCreator(this);

  orm_model.ModelQuery<models.User, UserFields, UserPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
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

/// Immutable input data; composition belongs to [valuePatch], not field names.
final class ValuePatch {
  final WriteValue<BigInt, ValueFields> wide;
  final WriteValue<Uint8List, ValueFields> bytes;
  final WriteValue<Decimal, ValueFields> amount;
  final WriteValue<LocalDate, ValueFields> day;
  final WriteValue<LocalTime, ValueFields> time;
  final WriteValue<LocalDateTime, ValueFields> stamp;
  final WriteValue<DateTime, ValueFields> instant;
  ValuePatch._({
    required this.wide,
    required this.bytes,
    required this.amount,
    required this.day,
    required this.time,
    required this.stamp,
    required this.instant,
  });

  List<Assignment> _assignments(ValueFields fields) => [
    ...fields.wide.write(wide, fields),
    ...fields.bytes.write(bytes, fields),
    ...fields.amount.write(amount, fields),
    ...fields.day.write(day, fields),
    ...fields.time.write(time, fields),
    ...fields.stamp.write(stamp, fields),
    ...fields.instant.write(instant, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ValuePatchFactory {
  ValuePatch call({
    BigInt wide,
    Uint8List bytes,
    Decimal amount,
    LocalDate day,
    LocalTime time,
    LocalDateTime stamp,
    DateTime instant,
  });
  ValuePatch values({
    WriteValue<BigInt, ValueFields> wide = const .keep(),
    WriteValue<Uint8List, ValueFields> bytes = const .keep(),
    WriteValue<Decimal, ValueFields> amount = const .keep(),
    WriteValue<LocalDate, ValueFields> day = const .keep(),
    WriteValue<LocalTime, ValueFields> time = const .keep(),
    WriteValue<LocalDateTime, ValueFields> stamp = const .keep(),
    WriteValue<DateTime, ValueFields> instant = const .keep(),
  });
  ValuePatch overlay(Iterable<ValuePatch> layers);
  bool isEmpty(ValuePatch input);
}

const ValuePatchFactory valuePatch = _ValuePatchFactory();

final class _ValuePatchFactory implements ValuePatchFactory {
  const _ValuePatchFactory();
  @override
  ValuePatch call({
    Object? wide = _writeAbsent,
    Object? bytes = _writeAbsent,
    Object? amount = _writeAbsent,
    Object? day = _writeAbsent,
    Object? time = _writeAbsent,
    Object? stamp = _writeAbsent,
    Object? instant = _writeAbsent,
  }) => ValuePatch._(
    wide: _writeLiteral<BigInt, ValueFields>(wide),
    bytes: _writeLiteral<Uint8List, ValueFields>(bytes),
    amount: _writeLiteral<Decimal, ValueFields>(amount),
    day: _writeLiteral<LocalDate, ValueFields>(day),
    time: _writeLiteral<LocalTime, ValueFields>(time),
    stamp: _writeLiteral<LocalDateTime, ValueFields>(stamp),
    instant: _writeLiteral<DateTime, ValueFields>(instant),
  );
  @override
  ValuePatch values({
    WriteValue<BigInt, ValueFields> wide = const .keep(),
    WriteValue<Uint8List, ValueFields> bytes = const .keep(),
    WriteValue<Decimal, ValueFields> amount = const .keep(),
    WriteValue<LocalDate, ValueFields> day = const .keep(),
    WriteValue<LocalTime, ValueFields> time = const .keep(),
    WriteValue<LocalDateTime, ValueFields> stamp = const .keep(),
    WriteValue<DateTime, ValueFields> instant = const .keep(),
  }) => ValuePatch._(
    wide: wide,
    bytes: bytes,
    amount: amount,
    day: day,
    time: time,
    stamp: stamp,
    instant: instant,
  );
  @override
  ValuePatch overlay(Iterable<ValuePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = ValuePatch._(
        wide: WriteValue.overlay(earlier.wide, later.wide),
        bytes: WriteValue.overlay(earlier.bytes, later.bytes),
        amount: WriteValue.overlay(earlier.amount, later.amount),
        day: WriteValue.overlay(earlier.day, later.day),
        time: WriteValue.overlay(earlier.time, later.time),
        stamp: WriteValue.overlay(earlier.stamp, later.stamp),
        instant: WriteValue.overlay(earlier.instant, later.instant),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(ValuePatch input) =>
      input.wide.isMissing &&
      input.bytes.isMissing &&
      input.amount.isMissing &&
      input.day.isMissing &&
      input.time.isMissing &&
      input.stamp.isMissing &&
      input.instant.isMissing;
}

/// Immutable input data; composition belongs to [valueInsert], not field names.
final class ValueInsert {
  final WriteValue<int, ValueFields> id;
  final WriteValue<BigInt, ValueFields> wide;
  final WriteValue<Uint8List, ValueFields> bytes;
  final WriteValue<Decimal, ValueFields> amount;
  final WriteValue<LocalDate, ValueFields> day;
  final WriteValue<LocalTime, ValueFields> time;
  final WriteValue<LocalDateTime, ValueFields> stamp;
  final WriteValue<DateTime, ValueFields> instant;
  ValueInsert._({
    required this.id,
    required this.wide,
    required this.bytes,
    required this.amount,
    required this.day,
    required this.time,
    required this.stamp,
    required this.instant,
  }) {
    if (wide.isMissing) {
      throw ArgumentError.value(wide, 'wide', 'Must be supplied.');
    }
    if (bytes.isMissing) {
      throw ArgumentError.value(bytes, 'bytes', 'Must be supplied.');
    }
    if (amount.isMissing) {
      throw ArgumentError.value(amount, 'amount', 'Must be supplied.');
    }
    if (day.isMissing) {
      throw ArgumentError.value(day, 'day', 'Must be supplied.');
    }
    if (time.isMissing) {
      throw ArgumentError.value(time, 'time', 'Must be supplied.');
    }
    if (stamp.isMissing) {
      throw ArgumentError.value(stamp, 'stamp', 'Must be supplied.');
    }
    if (instant.isMissing) {
      throw ArgumentError.value(instant, 'instant', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(ValueFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.wide.write(wide, fields),
    ...fields.bytes.write(bytes, fields),
    ...fields.amount.write(amount, fields),
    ...fields.day.write(day, fields),
    ...fields.time.write(time, fields),
    ...fields.stamp.write(stamp, fields),
    ...fields.instant.write(instant, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ValueInsertFactory {
  ValueInsert call({
    int id,
    required BigInt wide,
    required Uint8List bytes,
    required Decimal amount,
    required LocalDate day,
    required LocalTime time,
    required LocalDateTime stamp,
    required DateTime instant,
  });
  ValueInsert values({
    WriteValue<int, ValueFields> id = const .keep(),
    required WriteValue<BigInt, ValueFields> wide,
    required WriteValue<Uint8List, ValueFields> bytes,
    required WriteValue<Decimal, ValueFields> amount,
    required WriteValue<LocalDate, ValueFields> day,
    required WriteValue<LocalTime, ValueFields> time,
    required WriteValue<LocalDateTime, ValueFields> stamp,
    required WriteValue<DateTime, ValueFields> instant,
  });
  ValueInsert overlay(ValueInsert earlier, Iterable<ValuePatch> layers);
}

const ValueInsertFactory valueInsert = _ValueInsertFactory();

final class _ValueInsertFactory implements ValueInsertFactory {
  const _ValueInsertFactory();
  @override
  ValueInsert call({
    Object? id = _writeAbsent,
    required BigInt wide,
    required Uint8List bytes,
    required Decimal amount,
    required LocalDate day,
    required LocalTime time,
    required LocalDateTime stamp,
    required DateTime instant,
  }) => ValueInsert._(
    id: _writeLiteral<int, ValueFields>(id),
    wide: .set(wide),
    bytes: .set(bytes),
    amount: .set(amount),
    day: .set(day),
    time: .set(time),
    stamp: .set(stamp),
    instant: .set(instant),
  );
  @override
  ValueInsert values({
    WriteValue<int, ValueFields> id = const .keep(),
    required WriteValue<BigInt, ValueFields> wide,
    required WriteValue<Uint8List, ValueFields> bytes,
    required WriteValue<Decimal, ValueFields> amount,
    required WriteValue<LocalDate, ValueFields> day,
    required WriteValue<LocalTime, ValueFields> time,
    required WriteValue<LocalDateTime, ValueFields> stamp,
    required WriteValue<DateTime, ValueFields> instant,
  }) => ValueInsert._(
    id: id,
    wide: wide,
    bytes: bytes,
    amount: amount,
    day: day,
    time: time,
    stamp: stamp,
    instant: instant,
  );
  @override
  ValueInsert overlay(ValueInsert earlier, Iterable<ValuePatch> layers) {
    for (final later in layers) {
      earlier = ValueInsert._(
        id: earlier.id,
        wide: WriteValue.overlay(earlier.wide, later.wide),
        bytes: WriteValue.overlay(earlier.bytes, later.bytes),
        amount: WriteValue.overlay(earlier.amount, later.amount),
        day: WriteValue.overlay(earlier.day, later.day),
        time: WriteValue.overlay(earlier.time, later.time),
        stamp: WriteValue.overlay(earlier.stamp, later.stamp),
        instant: WriteValue.overlay(earlier.instant, later.instant),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Value from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class ValueCreator {
  Future<models.Value> call({
    int id,
    required BigInt wide,
    required Uint8List bytes,
    required Decimal amount,
    required LocalDate day,
    required LocalTime time,
    required LocalDateTime stamp,
    required DateTime instant,
  });
}

final class _ValueCreator implements ValueCreator {
  final ValueTableSet _table;
  const _ValueCreator(this._table);
  @override
  Future<models.Value> call({
    Object? id = _writeAbsent,
    required BigInt wide,
    required Uint8List bytes,
    required Decimal amount,
    required LocalDate day,
    required LocalTime time,
    required LocalDateTime stamp,
    required DateTime instant,
  }) async => _table.plan
      .insert(
        ValueInsert._(
          id: _writeLiteral<int, ValueFields>(id),
          wide: .set(wide),
          bytes: .set(bytes),
          amount: .set(amount),
          day: .set(day),
          time: .set(time),
          stamp: .set(stamp),
          instant: .set(instant),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class ValuePatcher {
  Future<int> call({
    BigInt wide,
    Uint8List bytes,
    Decimal amount,
    LocalDate day,
    LocalTime time,
    LocalDateTime stamp,
    DateTime instant,
  });
}

final class _ValuePatcher implements ValuePatcher {
  final orm_model.ModelQuery<models.Value, ValueFields, ValuePatch> _query;
  const _ValuePatcher(this._query);
  @override
  Future<int> call({
    Object? wide = _writeAbsent,
    Object? bytes = _writeAbsent,
    Object? amount = _writeAbsent,
    Object? day = _writeAbsent,
    Object? time = _writeAbsent,
    Object? stamp = _writeAbsent,
    Object? instant = _writeAbsent,
  }) => _query.update(
    ValuePatch._(
      wide: _writeLiteral<BigInt, ValueFields>(wide),
      bytes: _writeLiteral<Uint8List, ValueFields>(bytes),
      amount: _writeLiteral<Decimal, ValueFields>(amount),
      day: _writeLiteral<LocalDate, ValueFields>(day),
      time: _writeLiteral<LocalTime, ValueFields>(time),
      stamp: _writeLiteral<LocalDateTime, ValueFields>(stamp),
      instant: _writeLiteral<DateTime, ValueFields>(instant),
    ),
  );
}

/// Named literal updates on a complete models.Value query.
extension ValueWrites
    on orm_model.ModelQuery<models.Value, ValueFields, ValuePatch> {
  /// Executes one update; omitted fields remain unchanged.
  ValuePatcher get patch => _ValuePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class ValueTableSet
    extends
        orm_model.ModelTable<
          models.Value,
          ValueFields,
          ValueInsert,
          ValuePatch
        > {
  ValueTableSet(QueryContext db)
    : super(
        db,
        valueTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final ValueCreator create = _ValueCreator(this);

  orm_model.ModelQuery<models.Value, ValueFields, ValuePatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
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
