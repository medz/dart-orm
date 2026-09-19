import 'package:orm/schema.dart';

final class User({
  @Id.generated() required final int id,
  @Unique() required final String email,
  required final String? nickname,
  @Default.sql('0') required final int score,
});

final class Post({
  @Id.generated() required final int id,
  required final int authorId,
  required final String title,
  required final DateTime createdAt,
});

final users = entity<User>();
final posts = entity<Post>();
final author = posts
    .key((p) => p.authorId)
    .references(users.key((u) => u.id), inverse: 'posts', onDelete: .cascade);
final authorTimeline = posts.index((p) => (p.authorId, p.createdAt, p.id));
