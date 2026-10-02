// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';

import "models.dart" as models;
export "models.dart" show User, Post;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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
final _userName = Column<String>(
  "display_name",
  Codecs.text,
  nullable: false,
  generated: false,
  clientDefault: () => "Anonymous",
);
final _userNickname = Column<String?>(
  "nickname",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
  clientDefault: () => "guest",
);
final _userActive = Column<bool>(
  "active",
  Codecs.boolean,
  nullable: false,
  generated: false,
  defaultSql: "true",
);
final _userMarker = Column<String>(
  "marker",
  Codecs.text,
  nullable: false,
  generated: false,
  defaultSql: "'server-marker'",
  clientDefault: models.nextMarker,
);
final _userScore = Column<int>(
  "score",
  Codecs.integer,
  nullable: false,
  generated: false,
  clientDefault: () => 7,
);
final userSchema = TableSchema(
  "User",
  columns: [
    _userId,
    _userEmail,
    _userName,
    _userNickname,
    _userActive,
    _userMarker,
    _userScore,
  ],
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
  late final name = column(_userName);
  late final nickname = column(_userNickname);
  late final active = column(_userActive);
  late final marker = column(_userMarker);
  late final score = column(_userScore);
  Relation<models.Post, PostFields> get posts =>
      Relation(postTable, parent: [id], child: (row) => [row.authorId]);
}

final userTable = Table<models.User, UserFields>(
  userSchema,
  UserFields.new,
  (row) =>
      (
        (row.id, row.email, row.name, row.nickname, row.active).map(
          (id, email, name, nickname, active) => (
            id: id,
            email: email,
            name: name,
            nickname: nickname,
            active: active,
          ),
        ),
        (
          row.marker,
          row.score,
        ).map((marker, score) => (marker: marker, score: score)),
      ).map(
        (left, right) => models.User(
          id: left.id,
          email: left.email,
          name: left.name,
          nickname: left.nickname,
          active: left.active,
          marker: right.marker,
          score: right.score,
        ),
      ),
);

/// Immutable input data; composition belongs to [userPatch], not field names.
final class UserPatch {
  final WriteValue<String, UserFields> email;
  final WriteValue<String, UserFields> name;
  final WriteValue<String?, UserFields> nickname;
  final WriteValue<bool, UserFields> active;
  final WriteValue<String, UserFields> marker;
  final WriteValue<int, UserFields> score;
  UserPatch._({
    required this.email,
    required this.name,
    required this.nickname,
    required this.active,
    required this.marker,
    required this.score,
  });

  List<Assignment> _assignments(UserFields fields) => [
    ...fields.email.write(email, fields),
    ...fields.name.write(name, fields),
    ...fields.nickname.write(nickname, fields),
    ...fields.active.write(active, fields),
    ...fields.marker.write(marker, fields),
    ...fields.score.write(score, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserPatchFactory {
  UserPatch call({
    String email,
    String name,
    String? nickname,
    bool active,
    String marker,
    int score,
  });
  UserPatch values({
    WriteValue<String, UserFields> email = const .keep(),
    WriteValue<String, UserFields> name = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<bool, UserFields> active = const .keep(),
    WriteValue<String, UserFields> marker = const .keep(),
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
    Object? name = _writeAbsent,
    Object? nickname = _writeAbsent,
    Object? active = _writeAbsent,
    Object? marker = _writeAbsent,
    Object? score = _writeAbsent,
  }) => UserPatch._(
    email: _writeLiteral<String, UserFields>(email),
    name: _writeLiteral<String, UserFields>(name),
    nickname: _writeLiteral<String?, UserFields>(nickname),
    active: _writeLiteral<bool, UserFields>(active),
    marker: _writeLiteral<String, UserFields>(marker),
    score: _writeLiteral<int, UserFields>(score),
  );
  @override
  UserPatch values({
    WriteValue<String, UserFields> email = const .keep(),
    WriteValue<String, UserFields> name = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<bool, UserFields> active = const .keep(),
    WriteValue<String, UserFields> marker = const .keep(),
    WriteValue<int, UserFields> score = const .keep(),
  }) => UserPatch._(
    email: email,
    name: name,
    nickname: nickname,
    active: active,
    marker: marker,
    score: score,
  );
  @override
  UserPatch overlay(Iterable<UserPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = UserPatch._(
        email: WriteValue.overlay(earlier.email, later.email),
        name: WriteValue.overlay(earlier.name, later.name),
        nickname: WriteValue.overlay(earlier.nickname, later.nickname),
        active: WriteValue.overlay(earlier.active, later.active),
        marker: WriteValue.overlay(earlier.marker, later.marker),
        score: WriteValue.overlay(earlier.score, later.score),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(UserPatch input) =>
      input.email.isMissing &&
      input.name.isMissing &&
      input.nickname.isMissing &&
      input.active.isMissing &&
      input.marker.isMissing &&
      input.score.isMissing;
}

/// Immutable input data; composition belongs to [userInsert], not field names.
final class UserInsert {
  final WriteValue<int, UserFields> id;
  final WriteValue<String, UserFields> email;
  final WriteValue<String, UserFields> name;
  final WriteValue<String?, UserFields> nickname;
  final WriteValue<bool, UserFields> active;
  final WriteValue<String, UserFields> marker;
  final WriteValue<int, UserFields> score;
  UserInsert._({
    required this.id,
    required this.email,
    required this.name,
    required this.nickname,
    required this.active,
    required this.marker,
    required this.score,
  }) {
    if (email.isMissing) {
      throw ArgumentError.value(email, 'email', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(UserFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.email.write(email, fields),
    ...fields.name.write(name, fields),
    ...fields.nickname.write(nickname, fields),
    ...fields.active.write(active, fields),
    ...fields.marker.write(marker, fields),
    ...fields.score.write(score, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserInsertFactory {
  UserInsert call({
    int id,
    required String email,
    String name,
    String? nickname,
    bool active,
    String marker,
    int score,
  });
  UserInsert values({
    WriteValue<int, UserFields> id = const .keep(),
    required WriteValue<String, UserFields> email,
    WriteValue<String, UserFields> name = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<bool, UserFields> active = const .keep(),
    WriteValue<String, UserFields> marker = const .keep(),
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
    Object? name = _writeAbsent,
    Object? nickname = _writeAbsent,
    Object? active = _writeAbsent,
    Object? marker = _writeAbsent,
    Object? score = _writeAbsent,
  }) => UserInsert._(
    id: _writeLiteral<int, UserFields>(id),
    email: .set(email),
    name: _writeLiteral<String, UserFields>(name),
    nickname: _writeLiteral<String?, UserFields>(nickname),
    active: _writeLiteral<bool, UserFields>(active),
    marker: _writeLiteral<String, UserFields>(marker),
    score: _writeLiteral<int, UserFields>(score),
  );
  @override
  UserInsert values({
    WriteValue<int, UserFields> id = const .keep(),
    required WriteValue<String, UserFields> email,
    WriteValue<String, UserFields> name = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<bool, UserFields> active = const .keep(),
    WriteValue<String, UserFields> marker = const .keep(),
    WriteValue<int, UserFields> score = const .keep(),
  }) => UserInsert._(
    id: id,
    email: email,
    name: name,
    nickname: nickname,
    active: active,
    marker: marker,
    score: score,
  );
  @override
  UserInsert overlay(UserInsert earlier, Iterable<UserPatch> layers) {
    for (final later in layers) {
      earlier = UserInsert._(
        id: earlier.id,
        email: WriteValue.overlay(earlier.email, later.email),
        name: WriteValue.overlay(earlier.name, later.name),
        nickname: WriteValue.overlay(earlier.nickname, later.nickname),
        active: WriteValue.overlay(earlier.active, later.active),
        marker: WriteValue.overlay(earlier.marker, later.marker),
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
    String name,
    String? nickname,
    bool active,
    String marker,
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
    Object? name = _writeAbsent,
    Object? nickname = _writeAbsent,
    Object? active = _writeAbsent,
    Object? marker = _writeAbsent,
    Object? score = _writeAbsent,
  }) async => _table.plan
      .insert(
        UserInsert._(
          id: _writeLiteral<int, UserFields>(id),
          email: .set(email),
          name: _writeLiteral<String, UserFields>(name),
          nickname: _writeLiteral<String?, UserFields>(nickname),
          active: _writeLiteral<bool, UserFields>(active),
          marker: _writeLiteral<String, UserFields>(marker),
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
  Future<int> call({
    String email,
    String name,
    String? nickname,
    bool active,
    String marker,
    int score,
  });
}

final class _UserPatcher implements UserPatcher {
  final orm_model.ModelQuery<models.User, UserFields, UserPatch> _query;
  const _UserPatcher(this._query);
  @override
  Future<int> call({
    Object? email = _writeAbsent,
    Object? name = _writeAbsent,
    Object? nickname = _writeAbsent,
    Object? active = _writeAbsent,
    Object? marker = _writeAbsent,
    Object? score = _writeAbsent,
  }) => _query.update(
    UserPatch._(
      email: _writeLiteral<String, UserFields>(email),
      name: _writeLiteral<String, UserFields>(name),
      nickname: _writeLiteral<String?, UserFields>(nickname),
      active: _writeLiteral<bool, UserFields>(active),
      marker: _writeLiteral<String, UserFields>(marker),
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
  clientDefault: models.nextInstant,
);
final _postStatus = Column<String>(
  "status",
  Codecs.text,
  nullable: false,
  generated: false,
  defaultSql: "'draft'",
);
final postSchema = TableSchema(
  "posts",
  columns: [_postId, _postAuthorId, _postTitle, _postCreatedAt, _postStatus],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [
    IndexSchema("posts_author_created", [
      "author_id",
      "created_at",
    ], unique: false),
  ],
  foreignKeys: [
    ForeignKey(["author_id"], "User", ["id"], onDelete: "CASCADE"),
  ],
);

final class PostFields extends Fields {
  PostFields(super.table);
  late final id = column(_postId);
  late final authorId = column(_postAuthorId);
  late final title = column(_postTitle);
  late final createdAt = column(_postCreatedAt);
  late final status = column(_postStatus);
  Relation<models.User, UserFields> get author =>
      Relation(userTable, parent: [authorId], child: (row) => [row.id]);
}

final postTable = Table<models.Post, PostFields>(
  postSchema,
  PostFields.new,
  (row) => (row.id, row.authorId, row.title, row.createdAt, row.status).map(
    (v0, v1, v2, v3, v4) =>
        models.Post(id: v0, authorId: v1, title: v2, createdAt: v3, status: v4),
  ),
);

/// Immutable input data; composition belongs to [postPatch], not field names.
final class PostPatch {
  final WriteValue<int, PostFields> authorId;
  final WriteValue<String, PostFields> title;
  final WriteValue<DateTime, PostFields> createdAt;
  final WriteValue<String, PostFields> status;
  PostPatch._({
    required this.authorId,
    required this.title,
    required this.createdAt,
    required this.status,
  });

  List<Assignment> _assignments(PostFields fields) => [
    ...fields.authorId.write(authorId, fields),
    ...fields.title.write(title, fields),
    ...fields.createdAt.write(createdAt, fields),
    ...fields.status.write(status, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PostPatchFactory {
  PostPatch call({
    int authorId,
    String title,
    DateTime createdAt,
    String status,
  });
  PostPatch values({
    WriteValue<int, PostFields> authorId = const .keep(),
    WriteValue<String, PostFields> title = const .keep(),
    WriteValue<DateTime, PostFields> createdAt = const .keep(),
    WriteValue<String, PostFields> status = const .keep(),
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
    Object? status = _writeAbsent,
  }) => PostPatch._(
    authorId: _writeLiteral<int, PostFields>(authorId),
    title: _writeLiteral<String, PostFields>(title),
    createdAt: _writeLiteral<DateTime, PostFields>(createdAt),
    status: _writeLiteral<String, PostFields>(status),
  );
  @override
  PostPatch values({
    WriteValue<int, PostFields> authorId = const .keep(),
    WriteValue<String, PostFields> title = const .keep(),
    WriteValue<DateTime, PostFields> createdAt = const .keep(),
    WriteValue<String, PostFields> status = const .keep(),
  }) => PostPatch._(
    authorId: authorId,
    title: title,
    createdAt: createdAt,
    status: status,
  );
  @override
  PostPatch overlay(Iterable<PostPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = PostPatch._(
        authorId: WriteValue.overlay(earlier.authorId, later.authorId),
        title: WriteValue.overlay(earlier.title, later.title),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
        status: WriteValue.overlay(earlier.status, later.status),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(PostPatch input) =>
      input.authorId.isMissing &&
      input.title.isMissing &&
      input.createdAt.isMissing &&
      input.status.isMissing;
}

/// Immutable input data; composition belongs to [postInsert], not field names.
final class PostInsert {
  final WriteValue<int, PostFields> id;
  final WriteValue<int, PostFields> authorId;
  final WriteValue<String, PostFields> title;
  final WriteValue<DateTime, PostFields> createdAt;
  final WriteValue<String, PostFields> status;
  PostInsert._({
    required this.id,
    required this.authorId,
    required this.title,
    required this.createdAt,
    required this.status,
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
    ...fields.createdAt.write(createdAt, fields),
    ...fields.status.write(status, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class PostInsertFactory {
  PostInsert call({
    int id,
    required int authorId,
    required String title,
    DateTime createdAt,
    String status,
  });
  PostInsert values({
    WriteValue<int, PostFields> id = const .keep(),
    required WriteValue<int, PostFields> authorId,
    required WriteValue<String, PostFields> title,
    WriteValue<DateTime, PostFields> createdAt = const .keep(),
    WriteValue<String, PostFields> status = const .keep(),
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
    Object? createdAt = _writeAbsent,
    Object? status = _writeAbsent,
  }) => PostInsert._(
    id: _writeLiteral<int, PostFields>(id),
    authorId: .set(authorId),
    title: .set(title),
    createdAt: _writeLiteral<DateTime, PostFields>(createdAt),
    status: _writeLiteral<String, PostFields>(status),
  );
  @override
  PostInsert values({
    WriteValue<int, PostFields> id = const .keep(),
    required WriteValue<int, PostFields> authorId,
    required WriteValue<String, PostFields> title,
    WriteValue<DateTime, PostFields> createdAt = const .keep(),
    WriteValue<String, PostFields> status = const .keep(),
  }) => PostInsert._(
    id: id,
    authorId: authorId,
    title: title,
    createdAt: createdAt,
    status: status,
  );
  @override
  PostInsert overlay(PostInsert earlier, Iterable<PostPatch> layers) {
    for (final later in layers) {
      earlier = PostInsert._(
        id: earlier.id,
        authorId: WriteValue.overlay(earlier.authorId, later.authorId),
        title: WriteValue.overlay(earlier.title, later.title),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
        status: WriteValue.overlay(earlier.status, later.status),
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
    DateTime createdAt,
    String status,
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
    Object? createdAt = _writeAbsent,
    Object? status = _writeAbsent,
  }) async => _table.plan
      .insert(
        PostInsert._(
          id: _writeLiteral<int, PostFields>(id),
          authorId: .set(authorId),
          title: .set(title),
          createdAt: _writeLiteral<DateTime, PostFields>(createdAt),
          status: _writeLiteral<String, PostFields>(status),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class PostPatcher {
  Future<int> call({
    int authorId,
    String title,
    DateTime createdAt,
    String status,
  });
}

final class _PostPatcher implements PostPatcher {
  final orm_model.ModelQuery<models.Post, PostFields, PostPatch> _query;
  const _PostPatcher(this._query);
  @override
  Future<int> call({
    Object? authorId = _writeAbsent,
    Object? title = _writeAbsent,
    Object? createdAt = _writeAbsent,
    Object? status = _writeAbsent,
  }) => _query.update(
    PostPatch._(
      authorId: _writeLiteral<int, PostFields>(authorId),
      title: _writeLiteral<String, PostFields>(title),
      createdAt: _writeLiteral<DateTime, PostFields>(createdAt),
      status: _writeLiteral<String, PostFields>(status),
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

final appSchema = List<TableSchema>.unmodifiable([userSchema, postSchema]);

extension AppTables on QueryContext {
  UserTableSet get user => UserTableSet(this);
  PostTableSet get post => PostTableSet(this);
}
