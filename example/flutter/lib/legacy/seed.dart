import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

Future<void> seedLegacy(Database<Sqlite> db, Migration initial) async {
  await Migrator(db.sql).apply([initial]);
  await db.transaction((tx) async {
    await tx.notes.create(
      body: 'Written by version 1',
      createdAt: DateTime.utc(2026, 9, 15, 1, 2, 3, 123, 456),
    );
    await tx.notes.create(
      body: 'Keep this across the upgrade',
      createdAt: DateTime.utc(2026, 9, 15),
    );
  });
}
