// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "models.dart" as models;
export "models.dart" show User, Post;

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

final class UserTableSet extends TableSet<models.User, UserFields> {
  UserTableSet(QueryContext db) : super(db, userTable) {
    db.registerSchema(appSchema);
  }
  Future<models.User> create({
    Change<int> id = const Change.keep(),
    required String email,
    Change<String> name = const Change.keep(),
    Change<String?> nickname = const Change.keep(),
    Change<bool> active = const Change.keep(),
    Change<String> marker = const Change.keep(),
    Change<int> score = const Change.keep(),
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.email.set(email),
      ...row.name.change(name),
      ...row.nickname.change(nickname),
      ...row.active.change(active),
      ...row.marker.change(marker),
      ...row.score.change(score),
    ],
  );
  Query<models.User, UserFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension UserUpdates on Query<models.User, UserFields> {
  Future<int> patch({
    Change<String> email = const Change.keep(),
    Change<String> name = const Change.keep(),
    Change<String?> nickname = const Change.keep(),
    Change<bool> active = const Change.keep(),
    Change<String> marker = const Change.keep(),
    Change<int> score = const Change.keep(),
  }) => update(
    (row) => [
      ...row.email.change(email),
      ...row.name.change(name),
      ...row.nickname.change(nickname),
      ...row.active.change(active),
      ...row.marker.change(marker),
      ...row.score.change(score),
    ],
  ).execute();
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

final class PostTableSet extends TableSet<models.Post, PostFields> {
  PostTableSet(QueryContext db) : super(db, postTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Post> create({
    Change<int> id = const Change.keep(),
    required int authorId,
    required String title,
    Change<DateTime> createdAt = const Change.keep(),
    Change<String> status = const Change.keep(),
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.authorId.set(authorId),
      row.title.set(title),
      ...row.createdAt.change(createdAt),
      ...row.status.change(status),
    ],
  );
  Query<models.Post, PostFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension PostUpdates on Query<models.Post, PostFields> {
  Future<int> patch({
    Change<int> authorId = const Change.keep(),
    Change<String> title = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
    Change<String> status = const Change.keep(),
  }) => update(
    (row) => [
      ...row.authorId.change(authorId),
      ...row.title.change(title),
      ...row.createdAt.change(createdAt),
      ...row.status.change(status),
    ],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([userSchema, postSchema]);

extension AppTables on QueryContext {
  UserTableSet get user => UserTableSet(this);
  PostTableSet get post => PostTableSet(this);
}
