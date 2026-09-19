import 'dart:async';
import 'dart:io';

import 'package:orm/sqlite.dart';

import 'tables.dart';

/// Real competing workers, compiled without the test runner for native AOT.
Future<void> main() async {
  final probe = await sqlite(const SqliteOptions.memory());
  try {
    if (!probe.capabilities.cancellation) {
      var entered = false;
      try {
        await probe.transaction((tx) async {
          entered = true;
        }, retry: const TransactionRetry());
        throw StateError('Unsupported bounded retry was accepted');
      } on OrmException catch (error) {
        if (error.code != 'CAPABILITY.CANCEL' || entered) rethrow;
      }
      print(
        'Native AOT: bounded retry unavailable; capability rejection verified.',
      );
      return;
    }
  } finally {
    await probe.close();
  }
  final directory = await Directory.systemTemp.createTemp('orm-native-retry-');
  try {
    for (final journal in [SqliteJournal.wal, SqliteJournal.delete]) {
      final options = SqliteOptions.file(
        '${directory.path}/${journal.name}.sqlite',
        journal: journal,
        busyTimeout: const Duration(milliseconds: 20),
      );
      final base = await sqlite(options), other = await sqlite(options);
      final entered = Completer<void>(), release = Completer<void>();
      Future<void>? reader;
      var callbacks = 0, busy = 0;
      final db = Database(
        base.driver,
        onQuery: (event) {
          if (event.error case final SqliteFailure failure) {
            if (journal == .wal && failure.extendedCode != 517) {
              // onQuery intentionally cannot throw into an SQL operation.
              busy = -100;
            } else {
              busy++;
            }
            if (journal == .delete && event.sql == 'COMMIT') release.complete();
          }
        },
      );
      try {
        await createTables(db);
        await db.table(users).createRow((u) => [u.email.set('initial')]);
        if (journal == .delete) {
          reader = other.transaction((tx) async {
            await tx.table(users).count();
            entered.complete();
            await release.future;
          });
          await entered.future;
        }
        final reads = <int>[];
        await db.transaction((tx) async {
          callbacks++;
          final row = await tx.table(users).single();
          reads.add(row.score);
          if (journal == .wal && callbacks == 1) {
            await other.table(users).update((u) => [u.score.set(10)]).execute();
          }
          await tx
              .table(users)
              .update((u) => [u.score.set(row.score + 1)])
              .execute();
        }, retry: const TransactionRetry(delay: Duration(milliseconds: 20)));
        final score = (await db.table(users).single()).score;
        if (busy != 1 ||
            (journal == .wal &&
                (callbacks != 2 || score != 11 || reads.join(',') != '0,10')) ||
            (journal == .delete && (callbacks != 1 || score != 1))) {
          throw StateError(
            '$journal: callbacks=$callbacks, busy=$busy, score=$score, reads=$reads',
          );
        }
      } finally {
        if (!release.isCompleted) release.complete();
        await reader;
        await other.close();
        await db.close();
      }
    }
    print(
      'Native AOT: SQLite WAL snapshot replay and COMMIT-only busy retry passed.',
    );
  } finally {
    await directory.delete(recursive: true);
  }
}
