import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

import '../../generate.dart';
import '../../migrate.dart';
import 'arguments.dart';
import 'output.dart';

Future<void> initializeProject(
  List<String> args,
  CliOutput output, {
  String directory = '.',
}) async {
  String resolve(String path) => p.join(directory, path);
  final (positionals, options) = parseOptions(args, {'database'});
  if (positionals.isNotEmpty) {
    throw const FormatException('init accepts no positional arguments.');
  }
  final engine = requiredOption(options, 'database');
  if (!{'sqlite', 'postgres', 'mysql', 'mariadb'}.contains(engine)) {
    throw const FormatException(
      'Choose --database sqlite, postgres, mysql or mariadb.',
    );
  }
  if (!await File(resolve('pubspec.yaml')).exists()) {
    throw const FormatException(
      'Run init in a Dart project containing pubspec.yaml and the orm dependency.',
    );
  }
  const source = 'lib/schema.dart';
  const client = 'lib/schema.orm.dart';
  const snapshot = 'lib/schema.snapshot.dart';
  const registry = 'migrations/migrations.g.dart';
  const config = 'orm.config.dart';
  const paths = [source, client, snapshot, registry, config];
  for (final path in paths) {
    if (await FileSystemEntity.type(resolve(path), followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FormatException('init never replaces an existing file: $path');
    }
  }
  final migrations = Directory(resolve('migrations'));
  if (await migrations.exists() &&
      !await migrations.list(followLinks: false).isEmpty) {
    throw const FormatException(
      'init requires an empty migrations directory; existing history needs explicit configuration.',
    );
  }
  final saved = <File>[];
  Future<void> save(String path, String content) async {
    final file = File(resolve(path));
    await file.parent.create(recursive: true);
    await file.create(exclusive: true);
    saved.add(file);
    await file.writeAsString(content, flush: true);
  }

  try {
    await save(source, _initialSchema);
    final dialect = SqlDialect.values.byName(engine);
    final generated = await generateSchema(
      resolve(source),
      outputPath: resolve(client),
      dialect: dialect,
    );
    await save(client, generated.dart);
    await save(snapshot, generated.snapshotDart);
    final formatter = DartFormatter(
      languageVersion: DartFormatter.latestLanguageVersion,
    );
    await save(
      registry,
      formatter.format(migrationHistorySource([], dialect: dialect)),
    );
    await save(config, formatter.format(_initialConfig(engine)));
  } catch (_) {
    for (final file in saved.reversed) {
      await file.delete();
    }
    rethrow;
  }
  output.report({
    'database': engine,
    'created': paths,
    'next': [
      'dart run orm migrate create 0001_initial',
      'dart run orm migrate apply',
    ],
  });
}

const _initialSchema = '''import 'package:orm/schema.dart';

final task = model('tasks', (
  id: identity(),
  title: text(),
  done: boolean(defaultValue: false),
));
''';

String _initialConfig(String engine) {
  final connection = switch (engine) {
    'sqlite' =>
      '''return SqlDatabase(await SqliteDriver.open(
      readOnly
          ? const SqliteOptions.readOnly('app.sqlite')
          : const SqliteOptions.file('app.sqlite'),
    ));''',
    'postgres' =>
      '''return SqlDatabase(PostgresDriver(PostgresOptions(
      url: databaseUrl(),
      maxConnections: 1,
    )));''',
    'mysql' =>
      '''return SqlDatabase(await MysqlDriver.open(MysqlOptions(
      url: databaseUrl(),
    )));''',
    'mariadb' =>
      '''return SqlDatabase(await MariadbDriver.open(MariadbOptions(
      url: databaseUrl(),
    )));''',
    _ => throw ArgumentError.value(engine),
  };
  return '''${engine == 'sqlite' ? '' : "import 'dart:io';"}
import 'package:orm/cli.dart';
import 'package:orm/drivers/$engine.dart';
import 'lib/schema.snapshot.dart' as target;
import 'migrations/migrations.g.dart';

Future<void> main(List<String> args) => runOrmCli(args, config: OrmConfig(
  schema: 'lib/schema.dart',
  migrations: 'migrations',
  history: migrationHistory,
  snapshot: target.schema,
  connect: ({required bool readOnly}) async {
    $connection
  },
));
${engine == 'sqlite' ? '' : '''
Uri databaseUrl() {
  final value = Platform.environment['DATABASE_URL'];
  if (value == null || value.isEmpty) {
    throw const FormatException('DATABASE_URL is empty or missing.');
  }
  try {
    return Uri.parse(value);
  } on FormatException {
    throw const FormatException('DATABASE_URL is not a valid database URL.');
  }
}
'''}''';
}
