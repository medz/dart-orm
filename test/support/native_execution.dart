import 'dart:async';

import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import '../../example/schema.orm.dart';

Future<void> main() async {
  final db = await sqlite(const SqliteOptions.memory());
  try {
    final initial = Migration.create(
      '0001_initial',
      appSchema,
      dialect: db.dialect,
    );
    await Migrator(db.sql).apply([initial]);
    if ((await Migrator(db.sql).requireVersion([initial])).checksum !=
        initial.checksum) {
      throw StateError('Schema version compatibility failed');
    }
    final pending = Migration(
      '0002_pending',
      ['SELECT 1'],
      previous: initial.checksum,
      dialect: SqlDialect.sqlite,
    );
    try {
      await Migrator(db.sql).requireVersion([initial, pending]);
      throw StateError('Schema version requirement was ignored');
    } on OrmException catch (error) {
      if (error.code != 'MIGRATION.VERSION') rethrow;
    }
    for (var i = 0; i < 5; i++) {
      await db.user.create(email: 'aot$i@example.com');
    }
    await db.post.create(
      authorId: 1,
      title: 'AOT',
      createdAt: DateTime.utc(2026),
    );
    final author = await db.post
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
    final nullable = await db.post
        .select((p) => p.author.select((a) => a.nickname).required())
        .single();
    if (nullable != null) {
      throw StateError('Nullable required projection failed');
    }
    final absent = await db.post
        .select((p) => p.author.where((a) => a.id.eq(.value(99))).one())
        .single();
    if (absent != null) throw StateError('Optional join failed');
    final rows = await db.user
        .orderBy((u) => [u.id.asc()])
        .select((u) => u.email)
        .stream(batchSize: 2)
        .take(3)
        .toList();
    if (rows.length != 3 || rows.last != 'aot2@example.com') {
      throw StateError('Cursor decoding failed');
    }
    final combined = db.user
        .select((u) => (u.id, u.email).row)
        .unionAll(db.post.select((p) => (p.id, p.title).row))
        .orderBy(
          (u) => [u.ref((u) => u.id).asc(), u.ref((u) => u.email).asc()],
        );
    final List<(int, String)> combinedRows = await combined
        .stream(batchSize: 2)
        .toList();
    if (combinedRows.length != 6 || combinedRows.first != (1, 'AOT')) {
      throw StateError('UNION Record decoding failed');
    }
    final acquired = Completer<void>(), release = Completer<void>();
    final held = db.session((session) async {
      acquired.complete();
      await release.future;
    });
    await acquired.future;
    try {
      await db.user
          .insert((u) => [u.email.set('must-not-execute@example.com')])
          .execute(
            options: const ExecutionOptions(
              acquireTimeout: Duration(milliseconds: 40),
            ),
          );
      throw StateError('Connection acquisition should time out');
    } on OrmException catch (error) {
      if (error.code != 'CONNECTION.TIMEOUT') rethrow;
    } finally {
      release.complete();
      await held;
    }
    if (await db.user.count() != 5) throw StateError('Abandoned SQL executed');
    final resume = Completer<void>();
    var deadlineCallback = false;
    try {
      await db.transaction((tx) async {
        deadlineCallback = true;
        await tx.user.create(email: 'deadline@example.com');
        await resume.future;
      }, timeout: const Duration(milliseconds: 60));
      throw StateError('Transaction deadline failed');
    } on OrmException catch (error) {
      if (error.code !=
          (db.capabilities.cancellation
              ? 'TRANSACTION.TIMEOUT'
              : 'CAPABILITY.CANCEL')) {
        rethrow;
      }
    } finally {
      resume.complete();
    }
    if (!db.capabilities.cancellation && deadlineCallback) {
      throw StateError('Unsupported transaction deadline entered the callback');
    }
    if (await db.user.count() != 5) {
      throw StateError('Timed-out transaction persisted');
    }
    try {
      await db.transaction((tx) async {
        await tx.user.create(email: 'rollback@example.com');
        try {
          await tx.savepoint(
            (child) => child.execute(
              SqlCommand(
                "INSERT OR ROLLBACK INTO users(email) VALUES ('aot0@example.com')",
              ),
            ),
          );
        } on SqliteFailure {
          /* The outer transaction has also ended. */
        }
      });
      throw StateError('Automatic rollback went undetected');
    } on OrmException catch (error) {
      if (error.code != 'TRANSACTION.FAILED') rethrow;
    }
    if (await db.user.count() != 5) {
      throw StateError('Automatic rollback lost connection state');
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
      if (error.code !=
          (db.capabilities.cancellation
              ? 'OPERATION.CANCELLED'
              : 'CAPABILITY.CANCEL')) {
        rethrow;
      }
    } finally {
      timer.cancel();
    }
    if (await db.user.count() != 5) {
      throw StateError('Connection recovery failed');
    }
    final changes = StreamIterator(db.user.select((u) => u.email).watch());
    if (!await changes.moveNext() || changes.current.length != 5) {
      throw StateError('Initial watch snapshot failed');
    }
    final changed = changes.moveNext();
    await db.transaction((tx) async {
      await tx.user.create(email: 'watch1@example.com');
      await tx.user.create(email: 'watch2@example.com');
    });
    if (!await changed || changes.current.length != 7) {
      throw StateError('Committed watch snapshot failed');
    }
    await changes.cancel();
    print(
      'Native AOT: schema version compatibility, joined projections, typed UNION records, acquisition deadlines, automatic rollback, cursor demand, recovery and committed query watches passed. '
      'Statement/transaction interruption: ${db.capabilities.cancellation ? 'passed' : 'unavailable; capability rejection verified'}.',
    );
  } finally {
    await db.close();
  }
}
