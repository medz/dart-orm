import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';

import '../../tool/src/build_fixture.dart';

/// Compiled migration history for tests that deliberately crash a child process.
final class MigrationProject {
  final BuildFixture fixture;
  MigrationProject._(this.fixture);
  String get path => fixture.directory.path;
  String get migrationDirectory => '$path/lib/migrations';

  static Future<MigrationProject> create({
    SqlDialect dialect = SqlDialect.sqlite,
  }) async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    final project = MigrationProject._(fixture);
    try {
      await writeMigrationRegistry(
        project.migrationDirectory,
        dialect: dialect,
      );
      return project;
    } catch (_) {
      await fixture.dispose();
      rethrow;
    }
  }

  Future<void> append(Migration migration) async {
    await fixture.write(
      'lib/migrations/m${migration.id}.dart',
      migrationSource(migration),
    );
    await writeMigrationRegistry(migrationDirectory);
  }

  Future<void> dispose() => fixture.dispose();
}
