import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';

// Real process termination at a successful SQL/commit boundary. The parent test
// verifies database state and resumes using the unchanged migration files.
Future<void> main(List<String> args) async {
  final migrations =
      (jsonDecode(await File(args[0]).readAsString()) as List<Object?>)
          .map((value) => Migration.fromJson(value as Map<String, Object?>))
          .toList();
  var observed = false;
  final db = postgres(
    PostgresOptions(
      url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
      tls: .disable,
      schema: args[1],
      maxConnections: 1,
    ),
    onQuery: (event) {
      if (event.error != null) return;
      if (event.sql == args[2]) observed = true;
      if (observed && (args[3] == 'statement' || event.sql == 'COMMIT')) {
        exit(91);
      }
    },
  );
  try {
    await Migrator(db).apply(migrations);
  } finally {
    await db.close();
  }
  exitCode = 92; // The requested failure boundary was not reached.
}
