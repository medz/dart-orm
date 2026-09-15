import 'dart:io';

import 'package:orm/migrate_cli.dart';
import 'package:orm/sqlite.dart';

import 'migrations/migrations.g.dart';
import 'schema.snapshot.dart';

// This application owns a SQLite history. Only its file path varies by environment.
Future<void> main(List<String> args) => runMigrationCli(
  args,
  directory: 'example/migrations',
  history: migrationHistory,
  schema: schema,
  connect: ({required readOnly}) {
    final path = Platform.environment['ORM_SQLITE_PATH'] ?? 'app.sqlite';
    return sqlite(
      readOnly ? SqliteOptions.readOnly(path) : SqliteOptions.file(path),
    );
  },
);
