/// Project commands with ordinary typed Dart configuration and static history.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

import 'drivers/mysql.dart';
import 'drivers/postgres.dart';
import 'drivers/sqlite.dart';
import 'generate.dart';
import 'migrate.dart';
import 'migrate_cli.dart';
import 'runtime.dart';
import 'src/sqlite/assets_io.dart';

export 'migrate.dart' show MigrationHistory, SchemaRenames, SchemaSnapshot;
export 'migrate_cli.dart' show MigrationConnection;
export 'runtime.dart' show SqlDatabase;

part 'src/cli/commands.dart';
part 'src/cli/init.dart';

final class OrmConfig {
  final String schema;
  final String? output;
  final String migrations;
  final MigrationHistory history;
  final SchemaSnapshot snapshot;
  final MigrationConnection? connect;
  final SchemaRenames renames;
  final Map<String, Map<String, String>> using;
  const OrmConfig({
    this.schema = 'lib/schema.dart',
    this.output,
    this.migrations = 'migrations',
    required this.history,
    required this.snapshot,
    this.connect,
    this.renames = const SchemaRenames(),
    this.using = const {},
  });
}

const _help = <String, String>{
  '': '''Usage: dart run orm <command> [--json] [--config orm.config.dart]
  init --database sqlite|postgres|mysql|mariadb
  generate [schema.dart] [output.orm.dart]
  migrate create|check|plan|apply|status|verify|baseline|record|inspect
  migration registry <directory> [--dialect engine]
  db inspect|import <options>
  queries generate|check <options>
  web-assets [directory]

Run help <command> for details. Project commands use orm.config.dart.
Exit codes: 0 success, 1 execution failure, 2 drift/import issues, 64 usage error.
--json emits machine reports; schema and migration files always remain Dart.''',
  'init': '''Usage: dart run orm init --database sqlite|postgres|mysql|mariadb [--json]
Creates lib/schema.dart, its generated client/snapshot, a static migration
registry and orm.config.dart in an existing Dart project. Never replaces files,
connects to a database or applies DDL. Server URLs are read from DATABASE_URL
only when a connection command runs.''',
  'generate':
      '''Usage: dart run orm generate [schema.dart] [output.orm.dart] [--json]
Without a path, uses OrmConfig.schema or lib/schema.dart. Generates the client
and standalone physical snapshot without connecting to a database.
Use an explicit schema path to recreate a deleted snapshot before loading config.''',
  'migrate': '''Usage: dart run orm migrate <command> [--json]
  create <id> [--allow-destructive]  Generate schema, then save a reviewed diff
  check                             Validate fixed Dart migration history
  plan                              Inspect pending steps without applying
  apply [--max-backfill-batches n]   Apply pending migrations
  status                            Inspect applied history and checkpoints
  verify                            Compare the catalog with the bundled snapshot
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
  'queries': '''Usage: dart run orm queries generate <queries.dart> [output.queries.dart]
       dart run orm queries check --source queries.dart [--output file] <database>
Database options match help db. Generation is offline; check validates queries
against the selected database.''',
  'web-assets': '''Usage: dart run orm web-assets [directory] [--json]
Copies verified SQLite worker/WASM assets to web/orm by default.
Flutter Web bundles these resources automatically.''',
};

/// Called by the package executable or a project's explicit Dart entrypoint.
/// Loading a config is normal Dart execution, never reflection or JSON loading.
Future<void> runOrmCli(List<String> arguments, {OrmConfig? config}) async {
  final json = arguments.contains('--json');
  final output = _CliOutput(json);
  try {
    final args = List<String>.of(arguments);
    if (args.where((a) => a == '--json').length > 1) {
      throw const FormatException('Repeated option --json.');
    }
    args.remove('--json');
    String? configPath;
    final configIndex = args.indexOf('--config');
    if (configIndex >= 0) {
      if (config != null ||
          args.where((a) => a == '--config').length > 1 ||
          configIndex + 1 >= args.length ||
          args[configIndex + 1].startsWith('--')) {
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
      return;
    }
    if (args.first == 'init') {
      if (config != null || configPath != null) {
        throw const FormatException(
          'Run init from the package CLI without --config.',
        );
      }
      await _initializeProject(args.skip(1).toList(), output);
      return;
    }
    final projectCommand =
        args.first == 'migrate' || args.first == 'generate' && args.length == 1;
    if (config == null && projectCommand) {
      final path = configPath ?? 'orm.config.dart';
      if (await File(path).exists()) {
        final child = await Process.start(Platform.resolvedExecutable, [
          'run',
          path,
          ...args,
          if (json) '--json',
        ], mode: ProcessStartMode.inheritStdio);
        exitCode = await child.exitCode;
        return;
      }
      if (configPath != null || args.first == 'migrate') {
        throw FormatException(
          'Missing $path. Run dart run orm init --database <engine>.',
        );
      }
      args.add('lib/schema.dart');
    } else if (configPath != null) {
      throw const FormatException(
        '--config applies to generate without a path and migrate commands.',
      );
    }
    if (config != null && args.first == 'generate' && args.length == 1) {
      await writeGeneratedSchema(config.schema, output: config.output);
      output.report({
        'generated':
            config.output ?? p.setExtension(config.schema, '.orm.dart'),
      });
      return;
    }
    if (config != null && args.first == 'migrate') {
      var snapshot = config.snapshot;
      if (args.length > 1 && args[1] == 'create') {
        if (!(args.length == 3 ||
                args.length == 4 && args.last == '--allow-destructive') ||
            args[2].startsWith('--')) {
          throw const FormatException(
            'Use migrate create <id> [--allow-destructive].',
          );
        }
        // Generate before diffing so an edited model cannot silently use the
        // snapshot compiled into this invocation's configuration.
        final generated = await generateSchema(
          config.schema,
          outputPath: config.output,
        );
        final client =
            config.output ?? p.setExtension(config.schema, '.orm.dart');
        await File(client).parent.create(recursive: true);
        await File(client).writeAsString(generated.dart);
        final snapshotPath = client.endsWith('.orm.dart')
            ? '${client.substring(0, client.length - '.orm.dart'.length)}.snapshot.dart'
            : p.setExtension(client, '.snapshot.dart');
        await File(snapshotPath).writeAsString(generated.snapshotDart);
        snapshot = generated.snapshot;
      }
      await runMigrationCli(
        args.skip(1).toList(),
        history: config.history,
        directory: config.migrations,
        schema: snapshot,
        connect: config.connect,
        renames: config.renames,
        using: config.using,
        json: json,
      );
      return;
    }
    await _runExplicitCli(args, json: json);
  } on FormatException catch (error) {
    output.error(error.message, 64);
  } on ArgumentError catch (_) {
    output.error('Invalid command option or configuration. Use --help.', 64);
  } catch (error) {
    output.error(error.toString(), 1);
  }
}

final class _CliOutput(final bool json) {
  void report(Map<String, Object?> value) {
    if (json) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
    } else {
      for (final entry in value.entries) {
        stdout.writeln(
          '${entry.key}: ${entry.value is String ? entry.value : jsonEncode(entry.value)}',
        );
      }
    }
  }

  void error(String message, int code) {
    stderr.writeln(
      json ? jsonEncode({'error': message, 'exitCode': code}) : message,
    );
    exitCode = code;
  }
}
