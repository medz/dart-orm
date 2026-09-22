import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../drivers/mysql.dart';
import '../../drivers/mariadb.dart';
import '../../drivers/postgres.dart';
import '../../drivers/sqlite.dart';
import '../../generate.dart';
import '../../migrate.dart';
import '../../runtime.dart';
import '../generate/schema/layout.dart';
import '../sqlite/assets_io.dart';
import 'arguments.dart';
import 'output.dart';

Future<void> runExplicitCli(
  List<String> arguments, {
  bool json = false,
  SqlDialect? dialect,
  String defaultSource = 'lib/schema.dart',
  String? defaultOutput,
}) async {
  void report(Map<String, Object?> value) => CliOutput(json).report(value);
  try {
    if (arguments.first == 'web-assets') {
      if (arguments.length > 2 ||
          arguments.skip(1).any((a) => a.startsWith('--'))) {
        throw const FormatException(
          'web-assets expects at most one directory.',
        );
      }
      final directory = Directory(
        arguments.length == 2 ? arguments[1] : 'web/orm',
      );
      await copySqliteWebAssets(directory);
      CliOutput(json).report({'copied': directory.path});
      return;
    }
    if (arguments.first == 'generate') {
      final args = arguments.skip(1).toList();
      final index = args.indexOf('--database');
      if (index >= 0) {
        if (args.where((v) => v == '--database').length != 1 ||
            index + 1 >= args.length ||
            !SqlDialect.values.any((d) => d.name == args[index + 1])) {
          throw const FormatException(
            'Use --database sqlite|postgres|mysql|mariadb once.',
          );
        }
        final selected = SqlDialect.values.byName(args[index + 1]);
        if (dialect != null && selected != dialect) {
          throw const FormatException(
            'Generation engine must match the project migration history.',
          );
        }
        dialect = selected;
        args.removeRange(index, index + 2);
      }
      if (args.length > 2 || args.any((a) => a.startsWith('--'))) {
        throw const FormatException(
          'generate expects a schema path, optional output and --database engine.',
        );
      }
      final source = args.isEmpty ? defaultSource : args.first;
      final output = args.length == 2
          ? args.last
          : args.isEmpty
          ? defaultOutput
          : null;
      await writeGeneratedSchema(source, output: output, dialect: dialect);
      CliOutput(json).report({
        'generated': output ?? '${SchemaLayout.stem(source)}.orm.dart',
      });
      return;
    }
    if (arguments.length < 2) {
      throw const FormatException('Expected a subcommand.');
    }
    final command = '${arguments[0]} ${arguments[1]}';
    if (command == 'migration registry') {
      if (arguments.length < 3 ||
          arguments[2].startsWith('--') ||
          arguments.length != 3 &&
              !(arguments.length == 5 &&
                  arguments[3] == '--dialect' &&
                  {
                    'sqlite',
                    'postgres',
                    'mysql',
                    'mariadb',
                  }.contains(arguments[4]))) {
        throw const FormatException('migration registry expects a directory.');
      }
      report({
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
      if (arguments.length < 3 ||
          arguments.length > 4 ||
          arguments.skip(2).any((a) => a.startsWith('--'))) {
        throw const FormatException(
          'queries generate expects a source and optional output path.',
        );
      }
      await writeGeneratedQueries(
        arguments[2],
        output: arguments.length == 4 ? arguments[3] : null,
      );
      CliOutput(json).report({
        'generated': arguments.length == 4
            ? arguments[3]
            : p.setExtension(arguments[2], '.queries.dart'),
      });
      return;
    }
    final common = {
      'sqlite',
      'postgres-env',
      'mysql-env',
      'mariadb-env',
      'tls',
      'database-schema',
    };
    final flags = switch (command) {
      'db inspect' => {...common, 'table'},
      'db import' => {...common, 'output', 'table'},
      'queries check' => {...common, 'source', 'output'},
      _ => throw FormatException('Unknown command: $command'),
    };
    final (positionals, options) = parseOptions(
      arguments.skip(2).toList(),
      flags,
    );
    if (positionals.isNotEmpty) {
      throw const FormatException('Unexpected positional arguments.');
    }
    final queries = command == 'queries check'
        ? await checkGeneratedQueries(
            requiredOption(options, 'source'),
            output: options['output'],
          )
        : null;
    final table = command == 'db inspect'
        ? requiredOption(options, 'table')
        : null;
    final importOutput = command == 'db import'
        ? requiredOption(options, 'output')
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
          report({'queries': await checkSqlQueries(db, queries!)});
        case 'db inspect':
          final info = await inspectTable(db, table!);
          report({
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
          final importReport = File(
            p.setExtension(importOutput, '.import.json'),
          );
          await output.parent.create(recursive: true);
          await output.create(exclusive: true);
          var reportCreated = false;
          try {
            await importReport.create(exclusive: true);
            reportCreated = true;
            await output.writeAsString(result.dart, flush: true);
            await importReport.writeAsString(
              '${const JsonEncoder.withIndent('  ').convert(result.toJson())}\n',
              flush: true,
            );
          } catch (_) {
            await output.delete();
            if (reportCreated) await importReport.delete();
            rethrow;
          }
          report({
            'source': output.path,
            'report': importReport.path,
            ...result.toJson(),
          });
          if (result.hasBlockingIssues) exitCode = 2;
      }
    } finally {
      await db.close();
    }
  } on FormatException catch (error) {
    CliOutput(json).error(error.message, 64);
  } on ArgumentError catch (_) {
    CliOutput(json)
        .error('Invalid command option or configuration. Use --help.', 64);
  } catch (error) {
    CliOutput(json).error(error.toString(), 1);
  }
}

SqlDialect _databaseDialect(Map<String, String> options) {
  final selected = [
    'sqlite',
    'postgres-env',
    'mysql-env',
    'mariadb-env',
  ].where(options.containsKey).toList();
  if (selected.length != 1) {
    throw const FormatException(
      'Choose exactly one of --sqlite, --postgres-env, --mysql-env and --mariadb-env.',
    );
  }
  if (options.containsKey('sqlite')) {
    if (options.containsKey('tls') || options.containsKey('database-schema')) {
      throw const FormatException('Server options cannot configure SQLite.');
    }
    if (options['sqlite'] == ':memory:') {
      throw const FormatException(
        'CLI commands need a persistent SQLite file.',
      );
    }
    return SqlDialect.sqlite;
  }
  final dialect = SqlDialect.values.byName(
    selected.single.replaceFirst('-env', ''),
  );
  if (dialect != SqlDialect.postgres &&
      options.containsKey('database-schema')) {
    throw const FormatException(
      '--database-schema configures PostgreSQL only.',
    );
  }
  return dialect;
}

Future<SqlDatabase<Backend>> _open(
  Map<String, String> options, {
  required bool readOnly,
}) async {
  final dialect = _databaseDialect(options);
  if (dialect == SqlDialect.sqlite) {
    final file = requiredOption(options, 'sqlite');
    return SqlDatabase(
      await SqliteDriver.open(
        readOnly ? SqliteOptions.readOnly(file) : SqliteOptions.file(file),
      ),
    );
  }
  final name = requiredOption(options, '${dialect.name}-env');
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw FormatException('Environment variable $name is empty or missing.');
  }
  Uri url;
  try {
    url = Uri.parse(value);
  } on FormatException {
    throw const FormatException(
      'Database environment value is not a valid URL.',
    );
  }
  if (dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb) {
    final tls = MysqlTls.values.byName(options['tls'] ?? 'verifyFull');
    return SqlDatabase(
      dialect == SqlDialect.mysql
          ? await MysqlDriver.open(MysqlOptions(url: url, tls: tls))
          : await MariadbDriver.open(MariadbOptions(url: url, tls: tls)),
    );
  }
  return SqlDatabase(
    PostgresDriver(
      PostgresOptions(
        url: url,
        tls: PostgresTls.values.byName(options['tls'] ?? 'verifyFull'),
        schema: options['database-schema'],
        maxConnections: 1,
      ),
    ),
  );
}

List<Object?> _objects(List<CatalogObject> objects) => [
  for (final o in objects)
    {'kind': o.kind, 'name': o.name, 'definition': o.definition},
];
