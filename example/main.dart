import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(db).apply([Migration.create('0001_initial', appSchema)]);
    final user = await db.transaction((tx) async {
      final user = await tx.users.create(email: 'seven@example.com');
      await tx.posts.create(
        authorId: user.id,
        title: 'Hello Dart',
        createdAt: DateTime.now(),
      );
      return user;
    });
    await db.users.byId(user.id).patch(nickname: .set('Seven'));
    final cards = await db.users
        .select(
          (u) => (
            u.email,
            u.posts
                .orderBy((p) => [p.createdAt.desc(), p.id.desc()])
                .take(3)
                .select((p) => p.title)
                .many(),
          ).map((email, titles) => (email: email, titles: titles)),
        )
        .get();
    print(cards);
  } finally {
    await db.close();
  }
}
