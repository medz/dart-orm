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
    final combined = db.users
        .select((u) => (u.id, u.email).row)
        .unionAll(db.posts.select((p) => (p.id, p.title).row))
        .orderBy(
          (u) => [u.ref((u) => u.id).asc(), u.ref((u) => u.email).asc()],
        );
    final List<(int, String)> combinedRows = await combined
        .stream(batchSize: 2)
        .toList();
    if (combinedRows.length != 6 || combinedRows.first != (1, 'AOT')) {
      throw StateError('UNION Record decoding failed');
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
    final changes = StreamIterator(db.users.select((u) => u.email).watch());
    if (!await changes.moveNext() || changes.current.length != 5) {
      throw StateError('Initial watch snapshot failed');
    }
    final changed = changes.moveNext();
    await db.transaction((tx) async {
      await tx.users.create(email: 'watch1@example.com');
      await tx.users.create(email: 'watch2@example.com');
    });
    if (!await changed || changes.current.length != 7) {
      throw StateError('Committed watch snapshot failed');
    }
    await changes.cancel();
    print(
      'Native AOT: joined projections, typed UNION records, cursor demand, native cancellation, recovery and committed query watches passed.',
    );
  } finally {
    await db.close();
  }
}
