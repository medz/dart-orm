import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    await Migrator(
      db.sql,
    ).apply([Migration.create('0001_initial', appSchema, dialect: db.dialect)]);
    final User user = await db.transaction((tx) async {
      final User user = await tx.user.create(email: 'seven@example.com');
      await tx.post.create(
        authorId: user.id,
        title: 'Hello Dart',
        createdAt: DateTime.now(),
      );
      return user;
    });
    await db.user.byId(user.id).patch(nickname: .set('Seven'));
    final cards = await db.user
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
