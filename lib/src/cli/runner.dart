import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../generate.dart';
import '../../migrate.dart';
import '../generate/schema/layout.dart';
import 'commands.dart';
import 'config_entrypoint.dart';
import 'init.dart';
import 'migration.dart';
import 'output.dart';

const _help = <String, String>{
  '': '''Usage: dart run orm <command> [--json] [--config orm.config.dart]
  init --database sqlite|postgres|mysql|mariadb
  generate [schema-path] [output.orm.dart] [--database engine]
  migrate create|check|plan|apply|status|verify|baseline|record|inspect
  migration registry <directory> [--dialect engine]
  db inspect|import <options>
  web-assets [directory]

Run help <command> for details. Project commands use orm.config.dart.
Exit codes: 0 success, 1 execution failure, 2 drift/import issues, 64 usage error.
--json emits machine reports; schema and migration files always remain Dart.''',
  'init': '''Usage: dart run orm init --database sqlite|postgres|mysql|mariadb [--json]
Creates lib/models.dart, its generated client/snapshot, a static migration
registry and orm.config.dart in an existing Dart project. Never replaces files,
connects to a database or applies DDL. Server URLs are read from DATABASE_URL
only when a connection command runs.''',
  'generate': '''Usage: dart run orm generate [schema-path] [output.orm.dart] [--database engine] [--json]
Without a path, uses defineConfig.models or lib/models.dart.
Generates the client and physical snapshot without connecting to a database.
Configuration paths are relative to orm.config.dart; --config is relative to cwd.
New projects can use void main() { defineConfig(database: .sqlite); } from
package:orm/config.dart without generated snapshot or history imports.
Model directories are discovered recursively; folder names do not select namespaces.
--database selects the engine without loading the default configuration.''',
  'migrate': '''Usage: dart run orm migrate <command> [--json]
  create <id> [--allow-destructive]  Generate schema, then save a reviewed diff
  check                             Validate fixed Dart migration history
  plan                              Inspect pending steps without applying
  apply [--max-backfill-batches n]   Apply pending migrations
  status                            Inspect applied history and checkpoints
  verify                            Compare the catalog with the current models
  baseline                          Verify and register an existing schema
  record <id>                       Record an unpublished migration edit
  inspect <table>                   Inspect physical table metadata
Configuration, fixed engine, connections, renames and conversions belong in
orm.config.dart. create/check/record do not connect. No command except explicit
apply/baseline changes database state. Review generated migrations before apply.''',
  'migration': '''Usage: dart run orm migration registry <directory> [--dialect sqlite|postgres|mysql|mariadb]
Rebuild static imports without updating reviewed migration fingerprints.''',
  'db': '''Usage: dart run orm db inspect --table name <database>
       dart run orm db import --output schema.dart [--table name] <database>
Database: --sqlite file | --postgres-env NAME | --mysql-env NAME | --mariadb-env NAME
Server options: --tls verifyFull|require|disable; PostgreSQL: --database-schema name
Inspection and catalog import do not apply DDL or replace output files.''',
  'web-assets': '''Usage: dart run orm web-assets [directory] [--json]
Copies verified SQLite worker/WASM assets to web/orm by default.
Flutter Web bundles these resources automatically.''',
};

/// Runs package commands using the project's runnable Dart configuration.
///
/// Project commands load `orm.config.dart` in a child Dart process. Generation
/// and migration creation stay offline. Reports go to stdout; failures go to
/// stderr and set the process exit code. Pass `--json` for machine reports.
Future<void> runOrmCli(List<String> arguments) async {
  exitCode = await runOrmCommand(arguments);
}

Future<int> runOrmCommand(
  List<String> arguments, {
  ProjectConfig? config,
  MigrationHistory? history,
  String? entrypointPath,
}) async {
  final json = arguments.contains('--json');
  final output = CliOutput(json);
  try {
    final args = List<String>.of(arguments);
    final configured = config != null;
    if (args.where((a) => a == '--json').length > 1) {
      throw const FormatException('Repeated option --json.');
    }
    args.remove('--json');
    String? configPath;
    final configIndex = args.indexOf('--config');
    if (configIndex >= 0) {
      if (configured ||
          args.where((a) => a == '--config').length > 1 ||
          configIndex + 1 >= args.length ||
          args[configIndex + 1].startsWith('--') ||
          args[configIndex + 1].trim().isEmpty) {
        throw const FormatException(
          'Use --config <project-entrypoint.dart> once.',
        );
      }
      configPath = args[configIndex + 1];
      args.removeRange(configIndex, configIndex + 2);
    }
    if (args.isEmpty ||
        args.first == 'help' ||
        args.contains('--help') ||
        args.length == 1 && args.first == 'migrate') {
      final topic = args.isEmpty || args.first == '--help'
          ? ''
          : args.first == 'help'
          ? (args.length > 1 ? args[1] : '')
          : args.first;
      final help = _help[topic];
      if (help == null) throw FormatException('Unknown command: $topic.');
      if (json) {
        output.report({'help': help});
      } else {
        stdout.writeln(help);
      }
      return 0;
    }
    if (args.first == 'init') {
      if (configured || configPath != null) {
        throw const FormatException(
          'Run init from the package CLI without --config.',
        );
      }
      await initializeProject(args.skip(1).toList(), output);
      return 0;
    }
    final projectCommand =
        args.first == 'migrate' ||
        args.first == 'generate' &&
            (!args.contains('--database') || configPath != null);
    if (!configured && projectCommand) {
      final path = configPath ?? 'orm.config.dart';
      if (await File(path).exists()) {
        return await _runConfigFile(path, [...args, if (json) '--json']);
      }
      if (configPath != null || args.first == 'migrate') {
        throw FormatException(
          'Missing $path. Run dart run orm init --database <engine>.',
        );
      }
      if (args.length == 1) args.add('lib/models.dart');
    } else if (configPath != null) {
      throw const FormatException(
        '--config applies to generate and migrate commands.',
      );
    }
    if (config != null && args.first == 'generate') {
      return await runExplicitCli(
        args,
        json: json,
        dialect: config.database,
        defaultSource: config.models,
        defaultOutput: config.output,
        defaultNamespace: config.defaultNamespace,
      );
    }
    if (config != null && args.first == 'migrate') {
      final ids = await _migrationIds(config.migrations);
      final registry = p.join(config.migrations, 'migrations.g.dart');
      final registryKind = await FileSystemEntity.type(
        registry,
        followLinks: false,
      );
      if (registryKind != FileSystemEntityType.notFound &&
          registryKind != FileSystemEntityType.file) {
        throw FormatException(
          'Expected a regular migration registry: $registry',
        );
      }
      if (history == null && registryKind == FileSystemEntityType.file) {
        if (entrypointPath == null) {
          throw const FormatException(
            'Load migration history through dart run orm with a runnable configuration.',
          );
        }
        return await _runConfigFile(entrypointPath, [
          ...args,
          if (json) '--json',
        ], historyConfig: config);
      }
      if (history == null && ids.isNotEmpty) {
        throw const FormatException(
          'Migration files exist without a registry. Rebuild static imports with '
          'dart run orm migration registry <directory> --dialect <engine>.',
        );
      }
      history ??= MigrationHistory([], dialect: config.database);
      if (history.dialect != config.database) {
        throw const FormatException(
          'Configuration database must match the fixed migration history engine.',
        );
      }
      final registeredIds = history.entries
          .map((entry) => entry.$1.id)
          .toList();
      if (ids.length != registeredIds.length ||
          Iterable<int>.generate(ids.length)
              .any((index) => ids[index] != registeredIds[index])) {
        throw const FormatException(
          'Migration registry is stale. Rebuild static imports, then run the command again.',
        );
      }
      SchemaSnapshot? snapshot;
      if (args.length > 1 && (args[1] == 'create' || args[1] == 'verify')) {
        final create = args[1] == 'create';
        if (create
            ? (!(args.length == 3 ||
                      args.length == 4 && args.last == '--allow-destructive') ||
                  args[2].startsWith('--'))
            : args.length != 2) {
          throw FormatException(
            create
                ? 'Use migrate create <id> [--allow-destructive].'
                : 'Use migrate verify.',
          );
        }
        // Validate reviewed history before generation can replace any artifacts.
        history.checked;
        final generated = await generateSchema(
          config.models,
          outputPath: config.output,
          dialect: config.database,
          defaultNamespace: config.defaultNamespace,
        );
        if (create) {
          final client =
              config.output ?? '${SchemaLayout.stem(config.models)}.orm.dart';
          await File(client).parent.create(recursive: true);
          await File(client).writeAsString(generated.dart);
          final snapshotPath = client.endsWith('.orm.dart')
              ? '${client.substring(0, client.length - '.orm.dart'.length)}.snapshot.dart'
              : p.setExtension(client, '.snapshot.dart');
          await File(snapshotPath).writeAsString(generated.snapshotDart);
        }
        snapshot = generated.snapshot;
      }
      return await runMigrationCommand(
        args.skip(1).toList(),
        history: history,
        directory: config.migrations,
        schema: snapshot,
        connect: config.connect,
        renames: config.renames,
        using: config.using,
        json: json,
      );
    }
    return await runExplicitCli(args, json: json);
  } on FormatException catch (error) {
    output.error(error.message, 64);
  } on ArgumentError catch (_) {
    output.error('Invalid command option or configuration. Use --help.', 64);
  } catch (error) {
    output.error(error.toString(), 1);
  }
  return output.exitCode;
}

Future<int> _runConfigFile(
  String path,
  List<String> arguments, {
  ProjectConfig? historyConfig,
}) async {
  final config = File(p.normalize(p.absolute(path)));
  var project = config.parent;
  while (!await File(p.join(project.path, 'pubspec.yaml')).exists() &&
      p.dirname(project.path) != project.path) {
    project = project.parent;
  }
  if (!await File(p.join(project.path, 'pubspec.yaml')).exists()) {
    throw const FormatException(
      'Place the configuration inside a Dart project containing pubspec.yaml.',
    );
  }
  final cache = Directory(p.join(project.path, '.dart_tool', 'orm'));
  await cache.create(recursive: true);
  final temporary = await cache.createTemp('config_');
  try {
    // Static imports preserve normal Dart compilation and package resolution.
    // A unique file per invocation prevents concurrent commands from racing.
    String literal(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
    final runner = File(p.join(temporary.path, 'main.dart'));
    await runner.writeAsString(
      "import ${literal(config.uri.toString())} as project;\n"
      "import 'package:orm/src/cli/config_entrypoint.dart';\n"
      '${historyConfig == null ? '' : "import 'package:orm/driver.dart' show SqlDialect;\n"}'
      '${historyConfig == null ? '' : "import ${literal(File(p.join(historyConfig.migrations, 'migrations.g.dart')).uri.toString())} as saved;\n"}'
      'Future<void> main(List<String> args) => runConfigEntrypoint('
      'args, project.main, path: ${literal(config.path)}'
      '${historyConfig == null ? '' : ', history: saved.migrationHistory, expectedMigrations: ${literal(historyConfig.migrations)}, expectedDatabase: SqlDialect.${historyConfig.database.name}'}'
      ');\n',
    );
    final child = await Process.run(Platform.resolvedExecutable, [
      'run',
      runner.path,
      ...arguments,
    ]);
    final childOutput = child.stdout as String;
    final childErrors = child.stderr as String;
    final code = {0, 1, 2, 64}.contains(child.exitCode) ? child.exitCode : 1;
    if (code == 0 || code == 2) {
      stdout.write(childOutput);
      stderr.write(childErrors);
      return code;
    }
    final json = arguments.contains('--json');
    final reporter = CliOutput(json);
    if (json) {
      // Dart can fail before the runner starts (for example a syntax error in
      // config or history). Normalize its launcher code and nested diagnostics
      // instead of leaking an unstructured compiler error through --json.
      final message =
          _childError(childErrors) ??
          'Dart configuration execution failed (exit ${child.exitCode}).\n'
                  '${childErrors.isEmpty ? childOutput : childErrors}'
              .trimRight();
      reporter.error(message, code);
    } else {
      stdout.write(childOutput);
      if (childErrors.isNotEmpty) {
        stderr.write(childErrors);
      } else {
        reporter.error(
          'Dart configuration execution failed (exit ${child.exitCode}).',
          code,
        );
      }
    }
    return code;
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<List<String>> _migrationIds(String path) async {
  final kind = await FileSystemEntity.type(path, followLinks: false);
  if (kind == FileSystemEntityType.notFound) return [];
  if (kind != FileSystemEntityType.directory) {
    throw FormatException('Expected a migration directory: $path');
  }
  final ids = <String>[];
  await for (final entity in Directory(path).list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name == 'migrations.g.dart' || !name.endsWith('.dart')) continue;
    final match = RegExp(r'^m([0-9]+_[a-z][a-z0-9_]*)\.dart$').firstMatch(name);
    if (entity is! File || match == null) {
      throw FormatException(
        'Expected a regular m<id>.dart migration: ${entity.path}',
      );
    }
    ids.add(match.group(1)!);
  }
  return ids..sort();
}

String? _childError(String diagnostics) {
  for (final line in const LineSplitter().convert(diagnostics).reversed) {
    try {
      final value = jsonDecode(line);
      if (value is Map<String, dynamic> &&
          value['error'] is String &&
          value['exitCode'] is int) {
        return value['error'] as String;
      }
    } on FormatException {
      // Launcher/build-hook text is not a CLI report. The caller retains all
      // diagnostics when the child never reached its structured error handler.
    }
  }
  return null;
}
