import 'dart:io';

import 'package:orm/migrate_cli.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';

import 'migrations/migrations.g.dart';
import 'schema.snapshot.dart';

// Run from the repository root. Set DATABASE_URL for PostgreSQL; otherwise use
// the local SQLite file. Connection secrets remain environment inputs.
Future<void> main(List<String> args) => runMigrationCli(
  args,
  directory: 'example/migrations',
  history: migrationHistory,
  schema: schema,
  connect: ({required readOnly}) {
    final url = Platform.environment['DATABASE_URL'];
    if (url != null) {
      return postgres(
        PostgresOptions(
          url: Uri.parse(url),
          schema: Platform.environment['DATABASE_SCHEMA'] ?? 'public',
        ),
      );
    }
    final path = Platform.environment['ORM_SQLITE_PATH'] ?? 'app.sqlite';
    return sqlite(
      readOnly ? SqliteOptions.readOnly(path) : SqliteOptions.file(path),
    );
  },
);
