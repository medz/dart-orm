import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';

Future<void> main(List<String> args) async {
  final migrations =
      (jsonDecode(await File(args[0]).readAsString()) as List<Object?>)
          .map((v) => Migration.fromJson(v as Map<String, Object?>))
          .toList();
  final Database<Backend> base = args[1] == 'sqlite'
      ? await sqlite(SqliteOptions.file(args[2]))
      : postgres(
          PostgresOptions(
            url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
            tls: .disable,
            schema: args[2],
            maxConnections: 1,
          ),
        );
  var writes = 0;
  final db = Database(
    base.driver,
    onQuery: (event) {
      if (event.error != null) return;
      if (event.sql.startsWith('UPDATE "payload" SET')) writes++;
      if (writes == 2 && (args[3] == 'write' || event.sql == 'COMMIT')) {
        exit(91);
      }
    },
  );
  try {
    await Migrator(db).apply(migrations);
  } finally {
    await db.close();
  }
  exitCode = 92;
}
