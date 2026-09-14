import 'package:orm/schema.dart';

typedef User = ({
  @Id.generated() int id,
  @Unique() String email,
  String? nickname,
  @Default.sql('0') int score,
});

typedef Post = ({
  @Id.generated() int id,
  int authorId,
  String title,
  DateTime createdAt,
});

final users = entity<User>();
final posts = entity<Post>();
final author = posts
    .key((p) => p.authorId)
    .references(users.key((u) => u.id), inverse: 'posts', onDelete: .cascade);
final authorTimeline = posts.index((p) => (p.authorId, p.createdAt, p.id));
