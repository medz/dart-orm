import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';
import 'package:test/test.dart';

import '../../tool/src/build_fixture.dart';

/// A real consumer entrypoint. It compiles Dart history instead of loading files
/// through an in-process test substitute for the public command workflow.
final class MigrationProject {
  final BuildFixture fixture;
  final SqlDialect dialect;
  MigrationProject._(this.fixture, this.dialect);
  String get path => fixture.directory.path;
  String get databasePath => '$path/database.sqlite';
  String get migrationDirectory => '$path/lib/migrations';

  static Future<MigrationProject> create({
    String? postgresSchema,
    String? sqlitePath,
  }) async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    final project = MigrationProject._(
      fixture,
      postgresSchema == null ? SqlDialect.sqlite : SqlDialect.postgres,
    );
    try {
      await writeMigrationRegistry(
        project.migrationDirectory,
        dialect: project.dialect,
      );
      await fixture.write('bin/migrate.dart', '''
${postgresSchema == null ? '' : "import 'dart:io';"}
import 'package:orm/migrate_cli.dart';
import 'package:orm/${postgresSchema == null ? 'sqlite' : 'postgres'}.dart';
import '../lib/target.dart';
import '../lib/migrations/migrations.g.dart';
Future<void> main(List<String> args) => runMigrationCli(args,
  directory: 'lib/migrations', history: migrationHistory, schema: schema,
  connect: ({required readOnly}) => ${postgresSchema == null ? "sqlite(readOnly ? SqliteOptions.readOnly(${jsonEncode(sqlitePath ?? 'database.sqlite')}) : SqliteOptions.file(${jsonEncode(sqlitePath ?? 'database.sqlite')}))" : "postgres(PostgresOptions(url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!), tls: .disable, schema: ${jsonEncode(postgresSchema)}, maxConnections: 1))"},
);
''');
      return project;
    } catch (_) {
      await fixture.dispose();
      rethrow;
    }
  }

  Future<void> target(SchemaSnapshot schema) =>
      fixture.write('lib/target.dart', schemaSource(schema));

  Future<void> append(Migration migration) async {
    await fixture.write(
      'lib/migrations/m${migration.id}.dart',
      migrationSource(migration),
    );
    await writeMigrationRegistry(migrationDirectory);
  }

  Future<Map<String, Object?>> run(List<String> args, {int code = 0}) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/migrate.dart',
      ...args,
    ], workingDirectory: path);
    expect(
      result.exitCode,
      code,
      reason: '${args.join(' ')}\n${result.stdout}\n${result.stderr}',
    );
    return code == 0 || code == 2
        ? jsonDecode(result.stdout as String) as Map<String, Object?>
        : {};
  }

  Future<void> dispose() => fixture.dispose();
}
