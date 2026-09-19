import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';

Future<void> crashBackfill(
  List<Migration> migrations,
  List<String> args,
) async {
  final Database<Backend> base = args[0] == 'sqlite'
      ? await sqlite(SqliteOptions.file(args[1]))
      : postgres(
          PostgresOptions(
            url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
            tls: .disable,
            schema: args[1],
            maxConnections: 1,
          ),
        );
  var writes = 0;
  final db = Database(
    base.driver,
    onQuery: (event) {
      if (event.error != null) return;
      if (event.sql.startsWith('UPDATE "payload" SET')) writes++;
      if (writes == 2 && (args[2] == 'write' || event.sql == 'COMMIT')) {
        exit(91);
      }
    },
  );
  try {
    await Migrator(db.sql).apply(migrations);
  } finally {
    await db.close();
  }
  exitCode = 92;
}
