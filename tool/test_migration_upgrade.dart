import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Applies a beta.6 migration, then checks the same SQLite database with beta.7.
/// Pass safely unpacked package roots and an optional JSON report destination.
Future<void> main(List<String> args) async {
  if (args.length < 2 || args.length > 3) {
    throw ArgumentError('Use <beta6-package> <beta7-package> [report.json].');
  }
  final packages = [
    for (final path in args.take(2))
      await Directory(path).resolveSymbolicLinks(),
  ];
  for (var i = 0; i < packages.length; i++) {
    final spec = await File('${packages[i]}/pubspec.yaml').readAsString();
    _check(spec.contains('version: 6.0.0-beta.${i + 6}\n'), 'Package version');
  }
  final directory = await Directory.systemTemp.createTemp('orm-upgrade-');
  final root = await directory.resolveSymbolicLinks();
  final logs = StringBuffer();
  final commands = <String>[];
  File file(String name) => File('$root/$name');
  Future<String> run(List<String> arguments, {bool failure = false}) async {
    final command = 'dart ${arguments.join(' ')}';
    stdout.writeln(command);
    commands.add(command);
    final result = await Process.run(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: root,
    );
    final output = '${result.stdout}\n${result.stderr}';
    logs.writeln('$command\n$output');
    _check(
      failure ? result.exitCode != 0 : result.exitCode == 0,
      '$command (${result.exitCode}):\n$output',
    );
    return failure ? output : '${result.stdout}';
  }

  Future<void> dependency(String package) async {
    await file('pubspec.yaml').writeAsString('''
name: migration_upgrade_consumer
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  orm:
    path: ${jsonEncode(package)}
''');
    await run(['pub', 'get', '--offline']);
    final configFile = file('.dart_tool/package_config.json');
    final config = _json(await configFile.readAsString());
    final orm = (config['packages'] as List)
        .cast<Map<String, Object?>>()
        .singleWhere((entry) => entry['name'] == 'orm');
    final actual = configFile.uri.resolve(orm['rootUri'] as String);
    _check(
      await Directory.fromUri(actual).resolveSymbolicLinks() == package,
      'Resolve only the selected unpacked package',
    );
  }

  Future<void> probe({required bool beta7}) async {
    await file('bin/probe.dart').parent.create(recursive: true);
    await file('bin/probe.dart').writeAsString(
      _probe
          .replaceFirst('RUNTIME', beta7 ? 'sql' : 'runtime')
          .replaceFirst(
            'DATABASE',
            beta7
                ? "Database.fromSql(await sqlite(const SqliteOptions.file('app.sqlite')))"
                : "await sqlite(const SqliteOptions.file('app.sqlite'))",
          ),
    );
  }

  Future<Map<String, Object?>> snapshot({bool seed = false}) async =>
      _json(await run(['run', 'bin/probe.dart', if (seed) 'seed']));
  Future<Map<String, Object?>> migration(String command) async =>
      _json(await run(['run', 'orm', 'migrate', command, '--json']));
  try {
    await dependency(packages[0]);
    await run(['run', 'orm', 'init', '--database', 'sqlite']);
    await run(['run', 'orm', 'migrate', 'create', '0001_initial']);
    final migrationFile = file('migrations/m0001_initial.dart');
    final registry = file('migrations/migrations.g.dart');
    final originalMigration = await migrationFile.readAsString();
    final originalRegistry = await registry.readAsString();
    final initialApply = await migration('apply');
    _check(
      (initialApply['applied'] as List).single == '0001_initial',
      'Beta.6 must actually apply the migration',
    );
    await probe(beta7: false);
    final before = await snapshot(seed: true);
    final databaseShaBefore =
        (await sha256.bind(file('app.sqlite').openRead()).first).toString();

    await dependency(packages[1]);
    final config = file('orm.config.dart');
    await config.writeAsString(
      (await config.readAsString()).replaceFirst(
        "import 'package:orm/drivers/sqlite.dart';",
        "import 'package:orm/sqlite.dart';\nimport 'package:orm/sql.dart';",
      ),
    );
    await run(['run', 'orm', 'generate']);
    await probe(beta7: true);
    final unpatched = await run([
      'run',
      'orm',
      'migrate',
      'check',
      '--json',
    ], failure: true);
    _check(
      unpatched.contains('SqlDialect') &&
          unpatched.contains('TableSchema') &&
          unpatched.contains('Codecs'),
      'Negative control must identify the old history imports',
    );
    const migrationImports =
        "import 'package:orm/driver.dart';\n"
        "import 'package:orm/schema_model.dart';\n"
        "import 'package:orm/values.dart';\n";
    const registryImport = "import 'package:orm/driver.dart';\n";
    await migrationFile.writeAsString('$migrationImports$originalMigration');
    await registry.writeAsString('$registryImport$originalRegistry');
    _check(
      (await migrationFile.readAsString()).substring(migrationImports.length) ==
              originalMigration &&
          (await registry.readAsString()).substring(registryImport.length) ==
              originalRegistry,
      'Only add imports to historical libraries',
    );
    final results = <String, Map<String, Object?>>{};
    for (final command in ['check', 'status', 'verify', 'apply']) {
      results[command] = await migration(command);
    }
    _check(
      (results['apply']!['applied'] as List).isEmpty,
      'Already applied history must not run again',
    );
    final after = await snapshot();
    _check(jsonEncode(before) == jsonEncode(after), 'History, data and schema');
    final databaseShaAfter =
        (await sha256.bind(file('app.sqlite').openRead()).first).toString();
    _check(
      databaseShaBefore == databaseShaAfter,
      'SQLite file stays unchanged',
    );
    final report = {
      'passed': true,
      'sdk': Platform.version,
      'beta6Package': packages[0],
      'beta7Package': packages[1],
      'commands': commands,
      'unpatchedHistoryRejected': true,
      'historicalChanges': {
        'migrationAddedImports': migrationImports.trim().split('\n'),
        'registryAddedImports': registryImport.trim(),
        'originalMigrationSha256': sha256
            .convert(utf8.encode(originalMigration))
            .toString(),
        'originalRegistrySha256': sha256
            .convert(utf8.encode(originalRegistry))
            .toString(),
        'remainingSourceBytesUnchanged': true,
      },
      'databaseSha256': databaseShaAfter,
      'before': before,
      'after': after,
      'beta7MigrationCommands': results,
    };
    final json = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
    stdout.write(json);
    if (args.length == 3) await File(args[2]).writeAsString(json);
  } finally {
    try {
      if (args.length == 3) {
        await File('${args[2]}.log').writeAsString(logs.toString());
      }
    } on FileSystemException catch (error) {
      stderr.writeln('Could not save the optional command log: $error');
    } finally {
      await directory.delete(recursive: true);
    }
  }
}

Map<String, Object?> _json(String output) =>
    (jsonDecode(output.substring(output.indexOf('{')).trim()) as Map)
        .cast<String, Object?>();

void _check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

const _probe = r'''
import 'dart:convert';
import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/RUNTIME.dart';
import 'package:orm/sqlite.dart';
import '../lib/models.orm.dart';
import '../migrations/migrations.g.dart' as saved;
Future<void> main(List<String> args) async {
  final db = DATABASE;
  try {
    if (args.contains('seed')) await db.task.create(title: 'Persisted beta.6');
    final tasks = await db.task.get();
    final history = await db.sql.execute(SqlCommand('SELECT id, checksum, applied_at FROM "_orm_migrations" ORDER BY id'));
    final schema = await db.sql.execute(SqlCommand("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name"));
    final migrations = saved.migrationHistory.checked;
    print(jsonEncode({
      'tasks': [for (final task in tasks) {'id': task.id, 'title': task.title, 'done': task.done}],
      'journal': history.rows,
      'schema': schema.rows,
      'recordedChecksums': [for (final entry in saved.migrationHistory.entries) entry.$2],
      'calculatedChecksums': [for (final migration in migrations) migration.checksum],
      'definitions': [for (final migration in migrations) migration.toJson()],
    }));
  } finally { await db.close(); }
}
''';
