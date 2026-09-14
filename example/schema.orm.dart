// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;

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
);
final _usersScore = Column<int>(
  "score",
  Codecs.integer,
  nullable: false,
  generated: false,
  defaultSql: "0",
);
final usersSchema = TableSchema(
  "users",
  columns: [_usersId, _usersEmail, _usersNickname, _usersScore],
  primaryKey: ["id"],
  uniqueKeys: [
    ["email"],
  ],
  indexes: [],
  foreignKeys: [],
);

final class UsersFields extends Fields {
  UsersFields(super.table);
  late final id = column(_usersId);
  late final email = column(_usersEmail);
  late final nickname = column(_usersNickname);
  late final score = column(_usersScore);
  Relation<models.Post, PostsFields> get posts =>
      Relation(postsTable, parent: [id], child: (row) => [row.authorId]);
}

final usersTable = Table<models.User, UsersFields>(
  usersSchema,
  UsersFields.new,
  (row) => (row.id, row.email, row.nickname, row.score).map(
    (id, email, nickname, score) =>
        (id: id, email: email, nickname: nickname, score: score),
  ),
);

final class UsersTableSet extends TableSet<models.User, UsersFields> {
  UsersTableSet(Database<Backend> db) : super(db, usersTable);
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
  Query<models.User, UsersFields> byId(int id) => where((row) => row.id.eq(id));
}

extension UsersUpdates on Query<models.User, UsersFields> {
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
final _postsCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final postsSchema = TableSchema(
  "posts",
  columns: [_postsId, _postsAuthorId, _postsTitle, _postsCreatedAt],
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

final class PostsFields extends Fields {
  PostsFields(super.table);
  late final id = column(_postsId);
  late final authorId = column(_postsAuthorId);
  late final title = column(_postsTitle);
  late final createdAt = column(_postsCreatedAt);
  Relation<models.User, UsersFields> get author =>
      Relation(usersTable, parent: [authorId], child: (row) => [row.id]);
}

final postsTable = Table<models.Post, PostsFields>(
  postsSchema,
  PostsFields.new,
  (row) => (row.id, row.authorId, row.title, row.createdAt).map(
    (id, authorId, title, createdAt) =>
        (id: id, authorId: authorId, title: title, createdAt: createdAt),
  ),
);

final class PostsTableSet extends TableSet<models.Post, PostsFields> {
  PostsTableSet(Database<Backend> db) : super(db, postsTable);
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
  Query<models.Post, PostsFields> byId(int id) => where((row) => row.id.eq(id));
}

extension PostsUpdates on Query<models.Post, PostsFields> {
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

final appSchema = <TableSchema>[usersSchema, postsSchema];

extension AppTables<B extends Backend> on Database<B> {
  UsersTableSet get users => UsersTableSet(this);
  PostsTableSet get posts => PostsTableSet(this);
}
