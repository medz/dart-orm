import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:path/path.dart' as p;

const _usage = '''Usage: dart run orm <command>
  generate <schema.dart> [output.orm.dart]
  migration create <id> --schema snapshot.json [--dir migrations]
    [--renames renames.json] [--using conversions.json] [--allow-destructive]
  migration check [--dir migrations] [--dialect sqlite|postgres]
  migrate plan|apply [--dir migrations] <database>
    apply: [--max-backfill-batches count]
  migrate status <database>
  db inspect --table name <database>
  db import --output schema.dart [--tables tables.json] <database>
  db verify --schema snapshot.json <database>
  db baseline [--dir migrations] <database>

Database: --sqlite file.db | --postgres-env ENV_NAME
PostgreSQL: [--tls verifyFull|require|disable] [--database-schema name]
Output is JSON except for generate. Applied migration files must remain immutable.''';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.first == '--help' ||
      arguments.first == 'help') {
    stdout.writeln(_usage);
    return;
  }
  try {
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
    final common = {'sqlite', 'postgres-env', 'tls', 'database-schema'};
    final flags = switch (command) {
      'migration create' => {
        'schema',
        'dir',
        'renames',
        'using',
        'allow-destructive',
      },
      'migration check' => {'dir', 'dialect'},
      'migrate apply' => {...common, 'dir', 'max-backfill-batches'},
      'migrate plan' || 'db baseline' => {...common, 'dir'},
      'migrate status' => common,
      'db verify' => {...common, 'schema'},
      'db inspect' => {...common, 'table'},
      'db import' => {...common, 'output', 'tables'},
      _ => throw FormatException('Unknown command: $command'),
    };
    final (positionals, options) = _parse(arguments.skip(2).toList(), flags);
    final maxBatches = options['max-backfill-batches'] == null
        ? null
        : int.tryParse(options['max-backfill-batches']!);
    if (options.containsKey('max-backfill-batches') &&
        (maxBatches == null || maxBatches < 1)) {
      throw const FormatException(
        '--max-backfill-batches must be a positive integer.',
      );
    }
    if (positionals.length != (command == 'migration create' ? 1 : 0)) {
      throw const FormatException('Unexpected positional arguments.');
    }
    if (command == 'migration create') {
      final migrations = await _readMigrations(
        options['dir'] ?? 'migrations',
        allowMissing: true,
      );
      final target = SchemaSnapshot.fromJson(
        await _jsonFile(_required(options, 'schema')),
      );
      final previous = migrations.lastOrNull;
      if (previous != null && previous.snapshot == null) {
        throw const FormatException(
          'The preceding migration needs a snapshot before generating a diff.',
        );
      }
      final renames = options['renames'] == null
          ? <String, Object?>{}
          : await _jsonFile(options['renames']!);
      if (renames.keys.any((k) => !{'tables', 'columns'}.contains(k))) {
        throw const FormatException('Renames support tables and columns only.');
      }
      final conversions = options['using'] == null
          ? <String, Object?>{}
          : await _jsonFile(options['using']!);
      final migration = Migration.diff(
        positionals.single,
        from: previous?.snapshot ?? SchemaSnapshot([]),
        to: target,
        previous: previous?.checksum,
        allowDestructive: options.containsKey('allow-destructive'),
        renames: SchemaRenames(
          tables:
              ((renames['tables'] ?? <String, Object?>{})
                      as Map<String, Object?>)
                  .cast<String, String>(),
          columns: _columnMap(
            (renames['columns'] ?? <String, Object?>{}) as Map<String, Object?>,
          ),
        ),
        using: {
          for (final entry in conversions.entries)
            SqlDialect.values.byName(entry.key): _columnMap(
              entry.value as Map<String, Object?>,
            ),
        },
      );
      for (final dialect in SqlDialect.values) {
        validateMigrations([...migrations, migration], dialect: dialect);
      }
      if (migration.steps.values.every((steps) => steps.isEmpty)) {
        _print({'created': null, 'reason': 'Schema is unchanged.'});
        return;
      }
      final directory = Directory(options['dir'] ?? 'migrations');
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, '${migration.id}.json'));
      await file.create(exclusive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(migration.toJson())}\n',
        flush: true,
      );
      _print({'created': file.path, 'checksum': migration.checksum});
      return;
    }
    if (command == 'migration check') {
      final migrations = await _readMigrations(options['dir'] ?? 'migrations');
      final dialect = SqlDialect.values.byName(options['dialect'] ?? 'sqlite');
      validateMigrations(migrations, dialect: dialect);
      _print({
        'valid': true,
        'dialect': dialect.name,
        'migrations': migrations.map((m) => m.id).toList(),
      });
      return;
    }
    // Validate inputs before opening a database or creating a SQLite file.
    final snapshot = command == 'db verify'
        ? SchemaSnapshot.fromJson(await _jsonFile(_required(options, 'schema')))
        : null;
    final table = command == 'db inspect' ? _required(options, 'table') : null;
    final importOutput = command == 'db import'
        ? _required(options, 'output')
        : null;
    List<String>? importTables;
    if (importOutput != null) {
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
      if (options['tables'] case final path?) {
        final value = jsonDecode(await File(path).readAsString());
        if (value is! List<Object?> ||
            value.isEmpty ||
            value.any((v) => v is! String) ||
            value.toSet().length != value.length) {
          throw const FormatException(
            '--tables must contain a JSON array of distinct physical table names.',
          );
        }
        importTables = value.cast<String>();
      }
    }
    final migrations =
        {'migrate plan', 'migrate apply', 'db baseline'}.contains(command)
        ? await _readMigrations(options['dir'] ?? 'migrations')
        : <Migration>[];
    if (command == 'db baseline' &&
        (migrations.isEmpty || migrations.last.snapshot == null)) {
      throw const FormatException(
        'Baseline requires a final migration snapshot.',
      );
    }
    final dialect = _databaseDialect(options);
    if (migrations.isNotEmpty) validateMigrations(migrations, dialect: dialect);
    final readOnly = {
      'migrate plan',
      'migrate status',
      'db inspect',
      'db verify',
      'db import',
    }.contains(command);
    final db = await _open(options, readOnly: readOnly);
    try {
      final migrator = Migrator(db);
      switch (command) {
        case 'migrate plan':
          final pending = await migrator.plan(migrations);
          _print({
            'atomic': !pending.any(
              (m) => m.steps[db.dialect]!.any(
                (s) => s is CheckedSql || s is Backfill,
              ),
            ),
            'progress': (await migrator.progress())
                .map((p) => p.toJson())
                .toList(),
            'pending': [
              for (final m in pending)
                {
                  'id': m.id,
                  'checksum': m.checksum,
                  'steps': m.steps[db.dialect]!.map((s) => s.toJson()).toList(),
                },
            ],
          });
        case 'migrate apply':
          final applied = await migrator.apply(
            migrations,
            maxBackfillBatches: maxBatches,
          );
          _print({
            'applied': applied,
            if (maxBatches != null)
              'complete': (await migrator.plan(migrations)).isEmpty,
          });
        case 'migrate status':
          _print({
            'progress': (await migrator.progress())
                .map((p) => p.toJson())
                .toList(),
            'applied': [
              for (final m in await migrator.history())
                {'id': m.id, 'checksum': m.checksum},
            ],
          });
        case 'db baseline':
          _print(
            _verification(
              await migrator.baseline(
                migrations,
                expected: migrations.last.snapshot!,
              ),
            ),
          );
        case 'db verify':
          final result = await verifySchema(db, snapshot!);
          _print(_verification(result));
          if (!result.matches) exitCode = 2;
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
                  if (c.integerBits != null) 'integerBits': c.integerBits,
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
            'unmanaged': _objects(info.unmanaged),
          });
        case 'db import':
          final result = await importSchema(db, tables: importTables);
          final output = File(importOutput!);
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
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
  } on ArgumentError catch (_) {
    stderr.writeln(
      'Invalid command option or configuration. Use --help for supported values.',
    );
    exitCode = 64;
  } catch (e) {
    stderr.writeln(e);
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
    if (key == 'allow-destructive') {
      options[key] = 'true';
      continue;
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
Future<Map<String, Object?>> _jsonFile(String path) async =>
    jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
Map<String, Map<String, String>> _columnMap(Map<String, Object?> json) => {
  for (final e in json.entries)
    e.key: (e.value as Map<String, Object?>).cast<String, String>(),
};
Future<List<Migration>> _readMigrations(
  String path, {
  bool allowMissing = false,
}) async {
  final directory = Directory(path);
  if (!await directory.exists() && allowMissing) return [];
  final files = await directory
      .list(followLinks: false)
      .where((f) => f is File && p.extension(f.path) == '.json')
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));
  final result = <Migration>[];
  for (final file in files) {
    final migration = Migration.fromJson(await _jsonFile(file.path));
    if (p.basenameWithoutExtension(file.path) != migration.id) {
      throw FormatException(
        'Migration filename must match its id: ${file.path}',
      );
    }
    result.add(migration);
  }
  return result;
}

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
Map<String, Object?> _verification(SchemaVerification result) => {
  'matches': result.matches,
  'differences': result.differences,
  'unmanaged': _objects(result.unmanaged),
};
void _print(Object? value) =>
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));
