// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "schema.dart" as models;
export "schema.dart" show User, Post;

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
final _postCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final postSchema = TableSchema(
  "posts",
  columns: [_postId, _postAuthorId, _postTitle, _postCreatedAt],
  primaryKey: ["id"],
  uniqueKeys: [],
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
);

final class PostFields extends Fields {
  PostFields(super.table);
  late final id = column(_postId);
  late final authorId = column(_postAuthorId);
  late final title = column(_postTitle);
  late final createdAt = column(_postCreatedAt);
  Relation<models.User, UserFields> get author =>
      Relation(userTable, parent: [authorId], child: (row) => [row.id]);
}

final postTable = Table<models.Post, PostFields>(
  postSchema,
  PostFields.new,
  (row) => (row.id, row.authorId, row.title, row.createdAt).map(
    (v0, v1, v2, v3) =>
        models.Post(id: v0, authorId: v1, title: v2, createdAt: v3),
  ),
);

/// Immutable input data; composition belongs to [postPatch], not field names.
final class PostPatch {
  final WriteValue<int, PostFields> authorId;
  final WriteValue<String, PostFields> title;
  final WriteValue<DateTime, PostFields> createdAt;
  PostPatch._({
    required this.authorId,
    required this.title,
    required this.createdAt,
  });

  List<Assignment> _assignments(PostFields fields) => [
    ...fields.authorId.write(authorId, fields),
    ...fields.title.write(title, fields),
    ...fields.createdAt.write(createdAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PostPatchFactory {
  PostPatch call({int authorId, String title, DateTime createdAt});
  PostPatch values({
    WriteValue<int, PostFields> authorId = const .keep(),
    WriteValue<String, PostFields> title = const .keep(),
    WriteValue<DateTime, PostFields> createdAt = const .keep(),
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
    Object? createdAt = _writeAbsent,
  }) => PostPatch._(
    authorId: _writeLiteral<int, PostFields>(authorId),
    title: _writeLiteral<String, PostFields>(title),
    createdAt: _writeLiteral<DateTime, PostFields>(createdAt),
  );
  @override
  PostPatch values({
    WriteValue<int, PostFields> authorId = const .keep(),
    WriteValue<String, PostFields> title = const .keep(),
    WriteValue<DateTime, PostFields> createdAt = const .keep(),
  }) => PostPatch._(authorId: authorId, title: title, createdAt: createdAt);
  @override
  PostPatch overlay(Iterable<PostPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = PostPatch._(
        authorId: WriteValue.overlay(earlier.authorId, later.authorId),
        title: WriteValue.overlay(earlier.title, later.title),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(PostPatch input) =>
      input.authorId.isMissing &&
      input.title.isMissing &&
      input.createdAt.isMissing;
}

/// Immutable input data; composition belongs to [postInsert], not field names.
final class PostInsert {
  final WriteValue<int, PostFields> id;
  final WriteValue<int, PostFields> authorId;
  final WriteValue<String, PostFields> title;
  final WriteValue<DateTime, PostFields> createdAt;
  PostInsert._({
    required this.id,
    required this.authorId,
    required this.title,
    required this.createdAt,
  }) {
    if (authorId.isMissing) {
      throw ArgumentError.value(authorId, 'authorId', 'Must be supplied.');
    }
    if (title.isMissing) {
      throw ArgumentError.value(title, 'title', 'Must be supplied.');
    }
    if (createdAt.isMissing) {
      throw ArgumentError.value(createdAt, 'createdAt', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(PostFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.authorId.write(authorId, fields),
    ...fields.title.write(title, fields),
    ...fields.createdAt.write(createdAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PostInsertFactory {
  PostInsert call({
    int id,
    required int authorId,
    required String title,
    required DateTime createdAt,
  });
  PostInsert values({
    WriteValue<int, PostFields> id = const .keep(),
    required WriteValue<int, PostFields> authorId,
    required WriteValue<String, PostFields> title,
    required WriteValue<DateTime, PostFields> createdAt,
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
    required DateTime createdAt,
  }) => PostInsert._(
    id: _writeLiteral<int, PostFields>(id),
    authorId: .set(authorId),
    title: .set(title),
    createdAt: .set(createdAt),
  );
  @override
  PostInsert values({
    WriteValue<int, PostFields> id = const .keep(),
    required WriteValue<int, PostFields> authorId,
    required WriteValue<String, PostFields> title,
    required WriteValue<DateTime, PostFields> createdAt,
  }) => PostInsert._(
    id: id,
    authorId: authorId,
    title: title,
    createdAt: createdAt,
  );
  @override
  PostInsert overlay(PostInsert earlier, Iterable<PostPatch> layers) {
    for (final later in layers) {
      earlier = PostInsert._(
        id: earlier.id,
        authorId: WriteValue.overlay(earlier.authorId, later.authorId),
        title: WriteValue.overlay(earlier.title, later.title),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
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
    required DateTime createdAt,
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
    required DateTime createdAt,
  }) async => _table.plan
      .insert(
        PostInsert._(
          id: _writeLiteral<int, PostFields>(id),
          authorId: .set(authorId),
          title: .set(title),
          createdAt: .set(createdAt),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class PostPatcher {
  Future<int> call({int authorId, String title, DateTime createdAt});
}

final class _PostPatcher implements PostPatcher {
  final orm_model.ModelQuery<models.Post, PostFields, PostPatch> _query;
  const _PostPatcher(this._query);
  @override
  Future<int> call({
    Object? authorId = _writeAbsent,
    Object? title = _writeAbsent,
    Object? createdAt = _writeAbsent,
  }) => _query.update(
    PostPatch._(
      authorId: _writeLiteral<int, PostFields>(authorId),
      title: _writeLiteral<String, PostFields>(title),
      createdAt: _writeLiteral<DateTime, PostFields>(createdAt),
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
);
final _userScore = Column<int>(
  "score",
  Codecs.integer,
  nullable: false,
  generated: false,
  defaultSql: "0",
);
final userSchema = TableSchema(
  "users",
  columns: [_userId, _userEmail, _userNickname, _userScore],
  primaryKey: ["id"],
  uniqueKeys: [
    ["email"],
  ],
  indexes: [],
  foreignKeys: [],
);

final class UserFields extends Fields {
  UserFields(super.table);
  late final id = column(_userId);
  late final email = column(_userEmail);
  late final nickname = column(_userNickname);
  late final score = column(_userScore);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Post, PostFields> get posts =>
      Relation(postTable, parent: [id], child: (row) => [row.authorId]);
}

final userTable = Table<models.User, UserFields>(
  userSchema,
  UserFields.new,
  (row) => (row.id, row.email, row.nickname, row.score).map(
    (v0, v1, v2, v3) => models.User(id: v0, email: v1, nickname: v2, score: v3),
  ),
);

/// Immutable input data; composition belongs to [userPatch], not field names.
final class UserPatch {
  final WriteValue<String, UserFields> email;
  final WriteValue<String?, UserFields> nickname;
  final WriteValue<int, UserFields> score;
  UserPatch._({
    required this.email,
    required this.nickname,
    required this.score,
  });

  List<Assignment> _assignments(UserFields fields) => [
    ...fields.email.write(email, fields),
    ...fields.nickname.write(nickname, fields),
    ...fields.score.write(score, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserPatchFactory {
  UserPatch call({String email, String? nickname, int score});
  UserPatch values({
    WriteValue<String, UserFields> email = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<int, UserFields> score = const .keep(),
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
    Object? score = _writeAbsent,
  }) => UserPatch._(
    email: _writeLiteral<String, UserFields>(email),
    nickname: _writeLiteral<String?, UserFields>(nickname),
    score: _writeLiteral<int, UserFields>(score),
  );
  @override
  UserPatch values({
    WriteValue<String, UserFields> email = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<int, UserFields> score = const .keep(),
  }) => UserPatch._(email: email, nickname: nickname, score: score);
  @override
  UserPatch overlay(Iterable<UserPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = UserPatch._(
        email: WriteValue.overlay(earlier.email, later.email),
        nickname: WriteValue.overlay(earlier.nickname, later.nickname),
        score: WriteValue.overlay(earlier.score, later.score),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(UserPatch input) =>
      input.email.isMissing &&
      input.nickname.isMissing &&
      input.score.isMissing;
}

/// Immutable input data; composition belongs to [userInsert], not field names.
final class UserInsert {
  final WriteValue<int, UserFields> id;
  final WriteValue<String, UserFields> email;
  final WriteValue<String?, UserFields> nickname;
  final WriteValue<int, UserFields> score;
  UserInsert._({
    required this.id,
    required this.email,
    required this.nickname,
    required this.score,
  }) {
    if (email.isMissing) {
      throw ArgumentError.value(email, 'email', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(UserFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.email.write(email, fields),
    ...fields.nickname.write(nickname, fields),
    ...fields.score.write(score, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserInsertFactory {
  UserInsert call({int id, required String email, String? nickname, int score});
  UserInsert values({
    WriteValue<int, UserFields> id = const .keep(),
    required WriteValue<String, UserFields> email,
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<int, UserFields> score = const .keep(),
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
    Object? score = _writeAbsent,
  }) => UserInsert._(
    id: _writeLiteral<int, UserFields>(id),
    email: .set(email),
    nickname: _writeLiteral<String?, UserFields>(nickname),
    score: _writeLiteral<int, UserFields>(score),
  );
  @override
  UserInsert values({
    WriteValue<int, UserFields> id = const .keep(),
    required WriteValue<String, UserFields> email,
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<int, UserFields> score = const .keep(),
  }) => UserInsert._(id: id, email: email, nickname: nickname, score: score);
  @override
  UserInsert overlay(UserInsert earlier, Iterable<UserPatch> layers) {
    for (final later in layers) {
      earlier = UserInsert._(
        id: earlier.id,
        email: WriteValue.overlay(earlier.email, later.email),
        nickname: WriteValue.overlay(earlier.nickname, later.nickname),
        score: WriteValue.overlay(earlier.score, later.score),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.User from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class UserCreator {
  Future<models.User> call({
    int id,
    required String email,
    String? nickname,
    int score,
  });
}

final class _UserCreator implements UserCreator {
  final UserTableSet _table;
  const _UserCreator(this._table);
  @override
  Future<models.User> call({
    Object? id = _writeAbsent,
    required String email,
    Object? nickname = _writeAbsent,
    Object? score = _writeAbsent,
  }) async => _table.plan
      .insert(
        UserInsert._(
          id: _writeLiteral<int, UserFields>(id),
          email: .set(email),
          nickname: _writeLiteral<String?, UserFields>(nickname),
          score: _writeLiteral<int, UserFields>(score),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class UserPatcher {
  Future<int> call({String email, String? nickname, int score});
}

final class _UserPatcher implements UserPatcher {
  final orm_model.ModelQuery<models.User, UserFields, UserPatch> _query;
  const _UserPatcher(this._query);
  @override
  Future<int> call({
    Object? email = _writeAbsent,
    Object? nickname = _writeAbsent,
    Object? score = _writeAbsent,
  }) => _query.update(
    UserPatch._(
      email: _writeLiteral<String, UserFields>(email),
      nickname: _writeLiteral<String?, UserFields>(nickname),
      score: _writeLiteral<int, UserFields>(score),
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

final appSchema = List<TableSchema>.unmodifiable([postSchema, userSchema]);

extension AppTables on QueryContext {
  PostTableSet get post => PostTableSet(this);
  UserTableSet get user => UserTableSet(this);
}
