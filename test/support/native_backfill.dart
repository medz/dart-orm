import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'backfill.dart';
import 'backfill_history/migrations.g.dart' as historical;

final initial = initialFor(SqlDialect.sqlite);

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp(
    'orm-native-backfill-',
  );
  final options = SqliteOptions.file('${directory.path}/db.sqlite');
  final db = await sqlite(options), other = await sqlite(options);
  try {
    await seed(db, count: 25);
    final migration = historical.migrationHistory.checked.last;
    final runner = Migrator(db.sql);
    await runner.apply([initial, migration], maxBackfillBatches: 1);
    if ((await runner.progress()).single.backfill!.rows != 3) {
      throw StateError('Backfill pause failed');
    }
    final results = await Future.wait([
      runner.apply([initial, migration]),
      Migrator(other.sql).apply([initial, migration]),
    ]);
    if (results.expand((r) => r).length != 1) {
      throw StateError('Concurrent history recording failed');
    }
    final rows = await db.execute(SqlCommand('SELECT touches FROM payload'));
    if (rows.rows.length != 25 || rows.rows.any((r) => r.single != 1)) {
      throw StateError('Backfill replayed or skipped data');
    }
    await runner.requireVersion([initial, migration]);
    print(
      'Native AOT: historical backfill declaration, bounded pause, concurrent resume and startup compatibility passed.',
    );
  } finally {
    await other.close();
    await db.close();
    await directory.delete(recursive: true);
  }
}
