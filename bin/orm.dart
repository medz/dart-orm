import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';
import 'package:path/path.dart' as p;

const _usage = '''Usage: dart run orm <command>
  generate <schema.dart> [output.orm.dart]
  migration registry <directory> [--dialect sqlite|postgres]
  queries generate <queries.dart> [output.queries.dart]
  queries check --source queries.dart [--output queries.queries.dart] <database>
  db inspect --table name <database>
  db import --output schema.dart [--table name] <database>

Migrations use a project Dart entrypoint importing package:orm/migrate_cli.dart.
Database: --sqlite file.db | --postgres-env ENV_NAME
PostgreSQL: [--tls verifyFull|require|disable] [--database-schema name]''';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty ||
        arguments.first == '--help' ||
        arguments.first == 'help') {
      stdout.writeln(_usage);
      return;
    }
    if (arguments.first == 'generate') {
      if (arguments.length < 2 || arguments.length > 3) {
        throw const FormatException(
          'generate expects a schema and optional output path.',
        );
      }
      await writeGeneratedSchema(
        arguments[1],
        output: arguments.length == 3 ? arguments[2] : null,
      );
      stdout.writeln(
        'Generated ${arguments.length == 3 ? arguments[2] : p.setExtension(arguments[1], '.orm.dart')}',
      );
      return;
    }
    if (arguments.length < 2) {
      throw const FormatException('Expected a subcommand.');
    }
    final command = '${arguments[0]} ${arguments[1]}';
    if (command == 'migration registry') {
      if (arguments.length != 3 &&
          !(arguments.length == 5 &&
              arguments[3] == '--dialect' &&
              {'sqlite', 'postgres'}.contains(arguments[4]))) {
        throw const FormatException('migration registry expects a directory.');
      }
      _print({
        'registry': await writeMigrationRegistry(
          arguments[2],
          dialect: arguments.length == 5
              ? SqlDialect.values.byName(arguments[4])
              : null,
        ),
      });
      return;
    }
    if (command == 'queries generate') {
      if (arguments.length < 3 || arguments.length > 4) {
        throw const FormatException(
          'queries generate expects a source and optional output path.',
        );
      }
      await writeGeneratedQueries(
        arguments[2],
        output: arguments.length == 4 ? arguments[3] : null,
      );
      stdout.writeln(
        'Generated ${arguments.length == 4 ? arguments[3] : p.setExtension(arguments[2], '.queries.dart')}',
      );
      return;
    }
    final common = {'sqlite', 'postgres-env', 'tls', 'database-schema'};
    final flags = switch (command) {
      'db inspect' => {...common, 'table'},
      'db import' => {...common, 'output', 'table'},
      'queries check' => {...common, 'source', 'output'},
      _ => throw FormatException('Unknown command: $command'),
    };
    final (positionals, options) = _parse(arguments.skip(2).toList(), flags);
    if (positionals.isNotEmpty) {
      throw const FormatException('Unexpected positional arguments.');
    }
    final queries = command == 'queries check'
        ? await checkGeneratedQueries(
            _required(options, 'source'),
            output: options['output'],
          )
        : null;
    final table = command == 'db inspect' ? _required(options, 'table') : null;
    final importOutput = command == 'db import'
        ? _required(options, 'output')
        : '';
    final importTables = options['table'] == null ? null : [options['table']!];
    if (command == 'db import') {
      if (p.extension(importOutput) != '.dart') {
        throw const FormatException(
          'Import output must be a .dart source file.',
        );
      }
      for (final path in [
        importOutput,
        p.setExtension(importOutput, '.import.json'),
      ]) {
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw FormatException(
            'Import never replaces an existing output: $path',
          );
        }
      }
    }
    _databaseDialect(options);
    final db = await _open(options, readOnly: true);
    try {
      switch (command) {
        case 'queries check':
          _print({'queries': await checkSqlQueries(db, queries!)});
        case 'db inspect':
          final info = await inspectTable(db, table!);
          _print({
            'table': info.name,
            'columns': [
              for (final c in info.columns)
                {
                  'name': c.name,
                  'storageType': c.storageType,
                  'nullable': c.nullable,
                  'default': c.defaultSql,
                  'generated': c.generated,
                  if (c.computed case final computed?)
                    'computed': {
                      'expression': computed.expression(db.dialect),
                      'storage': computed.storage.name,
                    },
                  if (c.integerBits != null) 'integerBits': c.integerBits,
                  if (c.decimalPrecision != null)
                    'decimalPrecision': c.decimalPrecision,
                  if (c.decimalPrecision != null)
                    'decimalScale': c.decimalScale ?? 0,
                  if (c.temporalPrecision != null)
                    'temporalPrecision': c.temporalPrecision,
                  if (c.collation != null) 'collation': c.collation,
                },
            ],
            'primaryKey': info.primaryKey,
            'uniqueKeys': info.uniqueKeys,
            'foreignKeys': [
              for (final k in info.foreignKeys)
                {
                  'columns': k.columns,
                  'target': k.target,
                  'targetColumns': k.targetColumns,
                  'onDelete': k.onDelete,
                },
            ],
            'indexes': [
              for (final i in info.indexes)
                {'name': i.name, 'columns': i.columns, 'unique': i.unique},
            ],
            'checks': [
              for (final check in info.checks)
                {'name': check.name, 'expression': check.expression},
            ],
            'unmanaged': _objects(info.unmanaged),
          });
        case 'db import':
          final result = await importSchema(db, tables: importTables);
          final output = File(importOutput);
          final report = File(p.setExtension(importOutput, '.import.json'));
          await output.parent.create(recursive: true);
          await output.create(exclusive: true);
          var reportCreated = false;
          try {
            await report.create(exclusive: true);
            reportCreated = true;
            await output.writeAsString(result.dart, flush: true);
            await report.writeAsString(
              '${const JsonEncoder.withIndent('  ').convert(result.toJson())}\n',
              flush: true,
            );
          } catch (_) {
            await output.delete();
            if (reportCreated) await report.delete();
            rethrow;
          }
          _print({
            'source': output.path,
            'report': report.path,
            ...result.toJson(),
          });
          if (result.hasBlockingIssues) exitCode = 2;
      }
    } finally {
      await db.close();
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on ArgumentError catch (_) {
    stderr.writeln('Invalid command option or configuration. Use --help.');
    exitCode = 64;
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

(List<String>, Map<String, String>) _parse(
  List<String> args,
  Set<String> allowed,
) {
  final positionals = <String>[], options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final argument = args[i];
    if (!argument.startsWith('--')) {
      positionals.add(argument);
      continue;
    }
    final key = argument.substring(2);
    if (!allowed.contains(key) || options.containsKey(key)) {
      throw FormatException('Unknown or repeated option --$key.');
    }
    if (++i == args.length || args[i].startsWith('--')) {
      throw FormatException('Missing value for --$key.');
    }
    options[key] = args[i];
  }
  return (positionals, options);
}

String _required(Map<String, String> options, String key) =>
    options[key] ?? (throw FormatException('Missing --$key.'));
SqlDialect _databaseDialect(Map<String, String> options) {
  if (options.containsKey('sqlite') == options.containsKey('postgres-env')) {
    throw const FormatException(
      'Choose exactly one of --sqlite and --postgres-env.',
    );
  }
  if (options.containsKey('sqlite')) {
    if (options.containsKey('tls') || options.containsKey('database-schema')) {
      throw const FormatException(
        'PostgreSQL options cannot configure SQLite.',
      );
    }
    if (options['sqlite'] == ':memory:') {
      throw const FormatException(
        'CLI commands need a persistent SQLite file.',
      );
    }
    return SqlDialect.sqlite;
  }
  return SqlDialect.postgres;
}

Future<Database<Backend>> _open(
  Map<String, String> options, {
  required bool readOnly,
}) async {
  if (_databaseDialect(options) == SqlDialect.sqlite) {
    final file = _required(options, 'sqlite');
    return sqlite(
      readOnly ? SqliteOptions.readOnly(file) : SqliteOptions.file(file),
    );
  }
  final name = _required(options, 'postgres-env');
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw FormatException('Environment variable $name is empty or missing.');
  }
  Uri url;
  try {
    url = Uri.parse(value);
  } on FormatException {
    throw const FormatException(
      'PostgreSQL environment value is not a valid URL.',
    );
  }
  return postgres(
    PostgresOptions(
      url: url,
      tls: PostgresTls.values.byName(options['tls'] ?? 'verifyFull'),
      schema: options['database-schema'],
      maxConnections: 1,
    ),
  );
}

List<Object?> _objects(List<CatalogObject> objects) => [
  for (final o in objects)
    {'kind': o.kind, 'name': o.name, 'definition': o.definition},
];
void _print(Object? value) =>
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
