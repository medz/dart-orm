import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../driver/driver.dart';
import '../migrate/diff.dart';
import '../migrate/source.dart';
import 'migration.dart' show MigrationConnection;
import 'output.dart';
import 'runner.dart';

// A zone keeps configuration registration isolated from other CLI invocations.
final _invocationKey = Object();

final class ConfigInvocation {
  final String path;
  ProjectConfig? definition;

  ConfigInvocation(String path) : path = p.normalize(p.absolute(path));

  static ConfigInvocation? get current =>
      Zone.current[_invocationKey] as ConfigInvocation?;

  void register(ProjectConfig config) {
    if (definition != null) {
      throw const FormatException('Define exactly one ORM configuration.');
    }
    definition = config;
  }

  String resolve(String value) => p.normalize(p.join(p.dirname(path), value));
}

// The sole runtime representation of defineConfig's registered values.
final class ProjectConfig {
  final SqlDialect database;
  final String models;
  final String? output;
  final String migrations;
  final String? defaultNamespace;
  final MigrationConnection? connect;
  final SchemaRenames renames;
  final Map<String, Map<String, String>> using;

  const ProjectConfig({
    required this.database,
    this.models = 'lib/models.dart',
    this.output,
    this.migrations = 'migrations',
    this.defaultNamespace,
    this.connect,
    this.renames = const SchemaRenames(),
    this.using = const {},
  });

  ProjectConfig resolve(ConfigInvocation invocation) => ProjectConfig(
    database: database,
    models: invocation.resolve(models),
    output: output == null ? null : invocation.resolve(output!),
    migrations: invocation.resolve(migrations),
    defaultNamespace: defaultNamespace,
    connect: connect,
    renames: renames,
    using: using,
  );
}

// Used by the package CLI's short-lived, statically imported config runners.
Future<void> runConfigEntrypoint(
  List<String> arguments,
  Function entrypoint, {
  required String path,
  MigrationHistory? history,
  String? expectedMigrations,
  SqlDialect? expectedDatabase,
}) async {
  final invocation = ConfigInvocation(path);
  final output = CliOutput(arguments.contains('--json'));
  try {
    await runZoned(() async {
      if (entrypoint is! void Function()) {
        throw const FormatException(
          'Use a parameterless main() that calls defineConfig.',
        );
      }
      final result = Function.apply(entrypoint, const []);
      if (result is Future<dynamic>) await result;
      final definition = invocation.definition;
      if (definition == null) {
        throw const FormatException(
          'The configuration main function must call defineConfig.',
        );
      }
      final config = definition.resolve(invocation);
      if (expectedMigrations != null &&
              config.migrations != expectedMigrations ||
          expectedDatabase != null && config.database != expectedDatabase) {
        throw const FormatException(
          'Configuration changed while loading migration history. '
          'Keep its database and migrations path stable during a command.',
        );
      }
      exitCode = await runOrmCommand(
        arguments,
        config: config,
        history: history,
        entrypointPath: invocation.path,
      );
    }, zoneValues: {_invocationKey: invocation});
  } on FormatException catch (error) {
    output.error(error.message, 64);
    exitCode = output.exitCode;
  } catch (error) {
    output.error(error.toString(), 1);
    exitCode = output.exitCode;
  }
}
