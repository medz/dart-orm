import 'dart:async';

import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import '../../example/schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    if (!db.capabilities.cancellation) throw StateError('No native interrupt');
    await Migrator(db).apply([Migration.create('0001_initial', appSchema)]);
    for (var i = 0; i < 5; i++) {
      await db.users.create(email: 'aot$i@example.com');
    }
    await db.posts.create(
      authorId: 1,
      title: 'AOT',
      createdAt: DateTime.utc(2026),
    );
    final author = await db.posts
        .select(
          (p) => p.author
              .select(
                (a) =>
                    (a.id, a.nickname).map((id, name) => (id: id, name: name)),
              )
              .required(),
        )
        .single();
    if (author != (id: 1, name: null)) throw StateError('Joined record failed');
    final nullable = await db.posts
        .select((p) => p.author.select((a) => a.nickname).required())
        .single();
    if (nullable != null) {
      throw StateError('Nullable required projection failed');
    }
    final absent = await db.posts
        .select((p) => p.author.where((a) => a.id.eq(99)).one())
        .single();
    if (absent != null) throw StateError('Optional join failed');
    final rows = await db.users
        .orderBy((u) => [u.id.asc()])
        .select((u) => u.email)
        .stream(batchSize: 2)
        .take(3)
        .toList();
    if (rows.length != 3 || rows.last != 'aot2@example.com') {
      throw StateError('Cursor decoding failed');
    }
    final token = CancellationToken();
    final timer = Timer(const Duration(milliseconds: 40), token.cancel);
    try {
      await db.execute(
        SqlCommand(
          'WITH RECURSIVE n(x) AS ('
          'SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1000000000) '
          'SELECT sum(x) FROM n',
        ),
        options: ExecutionOptions(cancellation: token),
      );
      throw StateError('Cancellation failed');
    } on OrmException catch (error) {
      if (error.code != 'OPERATION.CANCELLED') rethrow;
    } finally {
      timer.cancel();
    }
    if (await db.users.count() != 5) {
      throw StateError('Connection recovery failed');
    }
    print(
      'Native AOT: joined projections, cursor demand, sqlite3_interrupt and connection recovery passed.',
    );
  } finally {
    await db.close();
  }
}
