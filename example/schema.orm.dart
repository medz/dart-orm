// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';

import "schema.dart" as models;
export "schema.dart" show User, Post;

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

final class PostTableSet extends TableSet<models.Post, PostFields> {
  PostTableSet(QueryContext db) : super(db, postTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Post> create({
    Change<int> id = const Change.keep(),
    required int authorId,
    required String title,
    required DateTime createdAt,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.authorId.set(authorId),
      row.title.set(title),
      row.createdAt.set(createdAt),
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
  }) => update(
    (row) => [
      ...row.authorId.change(authorId),
      ...row.title.change(title),
      ...row.createdAt.change(createdAt),
    ],
  ).execute();
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

final class UserTableSet extends TableSet<models.User, UserFields> {
  UserTableSet(QueryContext db) : super(db, userTable) {
    db.registerSchema(appSchema);
  }
  Future<models.User> create({
    Change<int> id = const Change.keep(),
    required String email,
    String? nickname,
    Change<int> score = const Change.keep(),
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.email.set(email),
      row.nickname.set(nickname),
      ...row.score.change(score),
    ],
  );
  Query<models.User, UserFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension UserUpdates on Query<models.User, UserFields> {
  Future<int> patch({
    Change<String> email = const Change.keep(),
    Change<String?> nickname = const Change.keep(),
    Change<int> score = const Change.keep(),
  }) => update(
    (row) => [
      ...row.email.change(email),
      ...row.nickname.change(nickname),
      ...row.score.change(score),
    ],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([postSchema, userSchema]);

extension AppTables on QueryContext {
  PostTableSet get post => PostTableSet(this);
  UserTableSet get user => UserTableSet(this);
}
