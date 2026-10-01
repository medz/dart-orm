import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'models.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(
      db.sql,
    ).apply([Migration.create('0001_initial', appSchema, dialect: db.dialect)]);
    final User user = await db.user.create(
      email: 'seven@example.com',
      name: .set('Seven'),
      nickname: .set(null),
    );
    final Post post = await db.post.create(
      authorId: user.id,
      title: 'Ordinary Dart models',
    );
    print(user.greeting());
    print(post.summary());
    await db.user.byId(user.id).patch(score: .set(8));
    final List<Post> posts = await db.user
        .byId(user.id)
        .select((u) => u.posts.many())
        .single();
    print(posts.map((p) => p.title).toList());
  } finally {
    await db.close();
  }
}
