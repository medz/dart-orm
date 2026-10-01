import 'package:orm/schema.dart';

@Model(table: "users")
@Unique(["email"])
@Relation(
  target: Post,
  name: "posts",
  fields: ["id"],
  keys: ["authorId"],
  constraint: false,
)
final class User({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "email") required final String email,
  @Column(name: "nickname") required final String? nickname,
  @Column(name: "score") @DatabaseDefault.sql("0") required final int score,
});

@Model(table: "posts")
@Index(["authorId", "createdAt", "id"], name: "author_timeline", unique: false)
@Relation(
  target: User,
  name: "author",
  fields: ["authorId"],
  keys: ["id"],
  onDelete: .cascade,
)
final class Post({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "author_id") required final int authorId,
  @Column(name: "title") required final String title,
  @Column(name: "created_at") required final DateTime createdAt,
});
