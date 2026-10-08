import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:orm/database.dart';
import 'package:orm/dev.dart';
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _hasPostgres =>
    Platform.environment.containsKey('ORM_TEST_POSTGRES_SOCKET') ||
    Platform.environment.containsKey('ORM_TEST_POSTGRES_HOST');

const _runtimeDrivers = r'''
bool get hasPostgres => Platform.environment.containsKey('ORM_TEST_POSTGRES_SOCKET') || Platform.environment.containsKey('ORM_TEST_POSTGRES_HOST');

Driver nativeDriver(Engine engine) {
  if (engine == Engine.sqlite) { return SqliteDriver.memory(); }
  final env = Platform.environment;
  final socket = env['ORM_TEST_POSTGRES_SOCKET'];
  return PostgresDriver(Endpoint(
    host: socket ?? env['ORM_TEST_POSTGRES_HOST']!,
    port: int.parse(env['ORM_TEST_POSTGRES_PORT'] ?? '5432'),
    database: env['ORM_TEST_POSTGRES_DATABASE'] ?? 'postgres',
    username: env['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
    password: env['ORM_TEST_POSTGRES_PASSWORD'],
    isUnixSocket: socket != null,
  ), settings: const PoolSettings(sslMode: SslMode.disable));
}

final class TrackedDriver implements Driver {
  TrackedDriver(this.delegate, {String? schema}) : schema = schema ?? delegate.schema;
  final Driver delegate;
  int acquisitions = 0;
  int closes = 0;
  @override
  final String schema;
  @override
  Engine get engine => delegate.engine;
  @override
  Capabilities get capabilities => delegate.capabilities;
  @override
  Future<T> withConnection<T>(Future<T> Function(Connection) action) {
    acquisitions++;
    return delegate.withConnection(action);
  }
  @override
  Future<void> close() { closes++; return delegate.close(); }
}
''';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory('test').createTemp('.generator-safety-'),
  );
  tearDown(() => directory.delete(recursive: true));

  Future<GeneratedSources> generate(
    String model, {
    String name = 'AppDatabase',
    Engine engine = Engine.sqlite,
  }) async {
    await File('${directory.path}/models.dart')
        .writeAsString("import 'package:orm/schema.dart';\n$model");
    return generateSchema(
      schemaPath: '${directory.path}/models.dart',
      outputPath: '${directory.path}/models.db.dart',
      databaseName: name,
      engine: engine,
    );
  }

  Future<void> analyze(GeneratedSources sources) async {
    final path = p.absolute('${directory.path}/models.db.dart');
    await writeGeneratedSources(sources: sources, outputPath: path);
    final collection = AnalysisContextCollection(
      includedPaths: [path],
      sdkPath: p.dirname(p.dirname(Platform.resolvedExecutable)),
    );
    try {
      final resolved =
          await collection.contextFor(path).currentSession.getResolvedUnit(path)
              as ResolvedUnitResult;
      expect(
        resolved.diagnostics.where(
          (diagnostic) => diagnostic.severity.name == 'error',
        ),
        isEmpty,
      );
    } finally {
      await collection.dispose();
    }
  }

  Future<void> runClient(String body) async {
    final run = File('${directory.path}/run.dart');
    await run.writeAsString('''
import 'dart:io';
import 'models.db.dart';
import 'models.snapshot.dart';
import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/postgres.dart';
import 'package:orm/query.dart';
import 'package:orm/schema.dart';
import 'package:orm/sqlite.dart';
$_runtimeDrivers
$body
''');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      run.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  const row = '''
@Table('things')
final class const Thing({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Unique() required final String name,
  final String? label,
});
''';

  test(
    'NUL defaults fail freeze, draft and generation without changing outputs',
    () async {
      const invalidTable = TableDefinition('things', [
        ColumnDefinition(
          name: 'id',
          field: 'id',
          type: ScalarType.integer,
          primaryKey: true,
        ),
        ColumnDefinition(
          name: 'name',
          field: 'name',
          type: ScalarType.text,
          defaultValue: 'before\u0000after',
        ),
      ]);
      for (final engine in Engine.values) {
        final snapshot = SchemaSnapshot(
          engine: engine,
          tables: const [invalidTable],
        );
        expect(() => freezeSnapshot(snapshot), throwsArgumentError);
        final draft = '${directory.path}/nul_${engine.name}.dart';
        await expectLater(
          draftMigration(
            after: snapshot,
            version: 1,
            name: 'nul_default',
            outputPath: draft,
          ),
          throwsArgumentError,
        );
        expect(await File(draft).exists(), isFalse);
        final original = await generate(row, engine: engine);
        final output = '${directory.path}/models.db.dart';
        await writeGeneratedSources(sources: original, outputPath: output);
        await expectLater(
          generate(
            row.replaceFirst(
              '@Unique()',
              r"@Column(defaultValue: '\u0000') @Unique()",
            ),
            engine: engine,
          ),
          throwsArgumentError,
        );
        expect(await File(output).readAsString(), original.database);
        expect(
          await File(snapshotPath(output)).readAsString(),
          original.snapshot,
        );
      }
    },
  );

  test(
    'stable primary constructors preserve field annotations and exact schema',
    () async {
      final sources = await generate(row);
      expect(sources.snapshot, contains('identity: true'));
      expect(sources.snapshot, contains('unique: true'));
      expect(
        sources.database,
        contains('ThingCreateIfAbsent get createIfAbsent'),
      );
      expect(
        sources.database,
        contains('static const name = ThingUnique._("name")'),
      );
      await analyze(sources);
    },
  );

  test(
    'traditional constructors accept only direct field assignments',
    () async {
      await analyze(
        await generate('''
@Table('things')
final class Thing {
  const Thing({required this.id, required String name, String? label})
      : name = name, label = (label);
  @PrimaryKey(autoIncrement: true) final int id;
  final String name;
  final String? label;
}
'''),
      );
      for (final constructor in [
        "Thing({required this.id, required String name}) : name = 'fixed';",
        'Thing({required this.id, required String name}) : name = name.toUpperCase();',
        'Thing({required this.id, required this.name}) { throw StateError("rejected"); }',
        'Thing({required this.id, required this.name}) : assert(name.isNotEmpty);',
      ]) {
        await expectLater(
          generate('''
@Table('things')
final class Thing {
  $constructor
  @PrimaryKey(autoIncrement: true) final int id;
  final String name;
}
'''),
          throwsFormatException,
        );
      }
      await expectLater(
        generate('''
@Table('things')
final class Thing {
  Thing({required this.id, required String name});
  @PrimaryKey(autoIncrement: true) final int id;
  late final String name;
}
'''),
        throwsFormatException,
      );
    },
  );

  test(
    'primary constructor body and computed initializers are rejected',
    () async {
      for (final source in [
        '''@Table('things')
final class Thing({@PrimaryKey() required final int id, required final String name}) {
  this { throw StateError('rejected'); }
}''',
        '''@Table('things')
final class const Thing({@PrimaryKey() required final int id, required final String name}) {
  this : assert(name != 'bad');
}''',
      ]) {
        await expectLater(generate(source), throwsFormatException);
      }
    },
  );

  test(
    'core names and every actual generated symbol are checked before output',
    () async {
      await expectLater(
        generate(row.replaceFirst("@Table('things')", "@Table('schema')")),
        throwsFormatException,
      );
      for (final name in [
        'Future',
        'List',
        'Map',
        'Object',
        'String',
        'DateTime',
        'Stream',
        'ArgumentError',
        'SchemaSnapshot',
        'ThingUnique',
        'ThingCreateIfAbsent',
      ]) {
        await expectLater(generate(row, name: name), throwsFormatException);
      }
      await expectLater(
        generate('''
@Table('decode_user')
final class const User({@PrimaryKey() required final int id});
@Table('elsewhere')
final class const UserDefinition({@PrimaryKey() required final int id});
'''),
        throwsFormatException,
      );
      final sources = await generate('''
@Table('things')
final class const Thing({@PrimaryKey() required final int id});
@Table('others')
final class const thing({@PrimaryKey() required final int id});
''');
      await analyze(sources);
    },
  );

  test('quoted and multiline physical names remain valid generated Dart and SQLite', () async {
    final sources = await generate(r'''
@Table('things\'s\nnext')
final class const Thing({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Column(name: 'value"\nnext') required final String name,
});
''');
    await analyze(sources);
    final run = File('${directory.path}/run.dart');
    await run.writeAsString('''
import 'models.db.dart';
import 'models.snapshot.dart';
import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';
import 'package:orm/sqlite.dart';
Future<void> main() async {
  final db = AppDatabase(SqliteDriver.memory());
  try {
    final plan = planSchemaChange(const SchemaSnapshot(engine: Engine.sqlite, tables: []), frozenSchema);
    await db.database.transaction((tx) async { for (final sql in plan.steps) { await tx.run(sql); } });
    final row = await db.thingsSNext.create(name: 'literal');
    if (row.name != 'literal' || (await db.thingsSNext.get(row.id))?.name != 'literal') { throw StateError('Wrong value'); }
  } finally { await db.close(); }
}
''');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      run.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('unique targets are closed typed constants and allow values/index/name fields', () async {
    final sources = await generate('''
@Table('things')
final class const Thing({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Unique() required final String values,
  @Unique() required final String index,
  @Unique() required final String name,
  @Unique() required final String target,
  @Unique() required final int hashCode,
  @Unique() required final int hashCodeColumn,
});
''');
    expect(
      sources.database,
      contains('static const values = ThingUnique._("values")'),
    );
    expect(
      sources.database,
      contains('static const index = ThingUnique._("index")'),
    );
    expect(
      sources.database,
      contains('static const name = ThingUnique._("name")'),
    );
    expect(sources.database, contains('ThingUnique targetValue'));
    expect(
      sources.database,
      contains('static const hashCodeColumn = ThingUnique._("hashCode")'),
    );
    expect(
      sources.database,
      contains(
        'static const hashCodeColumnColumn = ThingUnique._("hashCodeColumn")',
      ),
    );
    await analyze(sources);
    final run = File('${directory.path}/run.dart');
    await run.writeAsString('''
import 'models.db.dart';
import 'package:orm/sqlite.dart';
Future<void> main() async {
  final db = AppDatabase(SqliteDriver.memory());
  try {
    await db.session.run('CREATE TABLE things(id INTEGER PRIMARY KEY AUTOINCREMENT, "values" TEXT NOT NULL UNIQUE, "index" TEXT NOT NULL UNIQUE, name TEXT NOT NULL UNIQUE, target TEXT NOT NULL UNIQUE, hashCode INTEGER NOT NULL UNIQUE, hashCodeColumn INTEGER NOT NULL UNIQUE)');
    final row = await db.things.createIfAbsent(.values, values: 'one', index: 'first', name: 'a', target: 'claim', hashCode: 1, hashCodeColumn: 2);
    final duplicate = await db.things.createIfAbsent(.values, values: 'one', index: 'second', name: 'b', target: 'another', hashCode: 3, hashCodeColumn: 4);
    if (row == null || duplicate != null || (await db.things.all()).length != 1) { throw StateError('Wrong conflict result'); }
    final reservedTarget = await db.things.createIfAbsent(.hashCodeColumn, values: 'reserved', index: 'third', name: 'c', target: 'third', hashCode: 1, hashCodeColumn: 5);
    if (reservedTarget != null) { throw StateError('Reserved conflict target was mapped incorrectly'); }
  } finally { await db.close(); }
}
''');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      run.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('legal field and table names cannot shadow generated helpers or model imports', () async {
    final sources = await generate('''
@Table('models')
final class const Thing({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Unique() required final String identical,
  required final int num,
  required final String models,
  required final String models2,
  @Column(defaultValue: 'models.users') required final String models3,
  final String? models4,
});
@Table('models2')
final class const OtherThing({@PrimaryKey() required final int id});
@SelectFrom(Thing) typedef Card = ({int num, String identical, String models3});
''');
    expect(sources.database, contains('as models5'));
    expect(sources.database, contains('defaultValue: "models.users"'));
    await analyze(sources);
    final run = File('${directory.path}/run.dart');
    await run.writeAsString('''
import 'models.db.dart';
import 'models.dart';
import 'package:orm/sqlite.dart';
Future<void> main() async {
  final db = AppDatabase(SqliteDriver.memory());
  try {
    await db.session.run("CREATE TABLE models(id INTEGER PRIMARY KEY AUTOINCREMENT, identical TEXT NOT NULL UNIQUE, num INTEGER NOT NULL, models TEXT NOT NULL, models2 TEXT NOT NULL, models3 TEXT NOT NULL DEFAULT 'models.users', models4 TEXT)");
    final row = await db.models.create(identical: 'one', num: 1, models: 'first', models2: 'second');
    await db.models.update(row.id, identical: 'updated', models4: 'fourth');
    final changed = await db.models.increment(row.id, num: 2);
    final duplicate = await db.models.createIfAbsent(.identical, identical: 'updated', num: 8, models: 'other', models2: 'other');
    final card = (await db.models.select<Card>()).single;
    if (changed?.num != 3 || changed?.models4 != 'fourth' || duplicate != null || card.num != 3 || card.identical != 'updated' || card.models3 != 'models.users') { throw StateError('Shadowed generated value'); }
  } finally { await db.close(); }
}
''');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      run.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test(
    'identity-only clients omit unused sentinel and numeric helpers',
    () async {
      final sources = await generate('''
@Table('tokens') final class const Token({@PrimaryKey(autoIncrement: true) required final int id});
''');
      expect(sources.database, isNot(contains('_absent')));
      expect(sources.database, isNot(contains('_provided')));
      expect(sources.database, isNot(contains('_number')));
      final path = p.absolute('${directory.path}/models.db.dart');
      await writeGeneratedSources(sources: sources, outputPath: path);
      final result = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test(
    'generation validates engine-specific physical identifier identity',
    () async {
      const models = [
        '''
@Table('_ORM_MIGRATIONS')
final class const Metadata({@PrimaryKey() required final int id});
''',
        '''
@Table('users')
final class const User({@PrimaryKey() required final int id});
@Table('Users')
final class const OtherUser({@PrimaryKey() required final int id});
''',
        '''
@Table('users')
final class const User({
  @PrimaryKey() required final int id,
  @Column(name: 'ID') required final int uppercaseId,
});
''',
      ];
      for (final source in models) {
        await expectLater(generate(source), throwsArgumentError);
        expect(
          await File('${directory.path}/models.db.dart').exists(),
          isFalse,
        );
        expect(
          await File('${directory.path}/models.snapshot.dart').exists(),
          isFalse,
        );
      }
      for (final source in models) {
        await analyze(await generate(source, engine: Engine.postgresql));
      }
    },
  );

  test(
    'one generated client validates and runs portable models on both engines',
    () async {
      await analyze(await generate(row));
      await runClient(r'''
Future<void> main() async {
  final engines = [Engine.sqlite, if (hasPostgres) Engine.postgresql];
  for (final engine in engines) {
    final native = nativeDriver(engine);
    final schema = engine == Engine.sqlite ? 'main' : 'orm_generated_${pid}_${DateTime.now().microsecondsSinceEpoch}';
    if (engine == Engine.postgresql) {
      await native.withConnection((connection) => connection.run('CREATE SCHEMA ${quoteIdentifier(schema)}', []));
    }
    final driver = TrackedDriver(native, schema: schema);
    final events = <DatabaseEvent>[];
    final db = AppDatabase(driver, onEvent: events.add);
    if (driver.acquisitions != 0 || driver.closes != 0 || events.isNotEmpty) {
      throw StateError('Model validation must not acquire a connection');
    }
    try {
      final target = SchemaSnapshot(engine: engine, tables: frozenSchema.tables);
      final plan = planSchemaChange(SchemaSnapshot(engine: engine, tables: const []), target);
      await db.database.transaction((tx) async {
        if (engine == Engine.postgresql) {
          await tx.run('SET LOCAL search_path TO ${quoteIdentifier(schema)}, pg_temp');
        }
        for (final sql in plan.steps) { await tx.run(sql); }
      });
      events.clear();
      final created = await db.things.create(name: 'portable');
      final duplicate = await db.things.createIfAbsent(.name, name: 'portable');
      final updated = await db.things.update(created.id, label: 'updated');
      final fetched = await db.things.get(created.id);
      final rows = await db.things.all();
      if (created.name != 'portable' || duplicate != null || updated?.label != 'updated' || fetched?.label != 'updated' || rows.length != 1) {
        throw StateError('Portable typed CRUD failed on $engine');
      }
      if (events.length != 5 || events.any((event) => event.kind != 'statement')) {
        throw StateError('Runtime model validation added SQL');
      }
    } finally {
      try {
        if (engine == Engine.postgresql) { await db.session.run('DROP SCHEMA ${quoteIdentifier(schema)} CASCADE'); }
      } finally { await db.close(); }
    }
    if (driver.closes != 1) { throw StateError('Generated client must own the valid driver'); }
  }
}
''');
    },
  );

  for (final (name, source, generatedEngine, runtimeEngine, diagnostic) in [
    (
      'SQLite table identity collision',
      '''
@Table('users') final class const User({@PrimaryKey() required final int id});
@Table('Users') final class const OtherUser({@PrimaryKey() required final int id});
''',
      Engine.postgresql,
      Engine.sqlite,
      'Duplicate or reserved table Users',
    ),
    (
      'SQLite column identity collision',
      '''
@Table('users') final class const User({
  @PrimaryKey() required final int id,
  @Column(name: 'ID') required final int uppercaseId,
});
''',
      Engine.postgresql,
      Engine.sqlite,
      'Duplicate column or field',
    ),
    (
      'PostgreSQL overlong table name',
      '''
@Table('${List.filled(64, 't').join()}') final class const Thing({@PrimaryKey() required final int id});
''',
      Engine.sqlite,
      Engine.postgresql,
      '63 UTF-8 bytes',
    ),
    (
      'PostgreSQL overlong column name',
      '''
@Table('things') final class const Thing({
  @PrimaryKey() required final int id,
  @Column(name: '${List.filled(61, 'c').join()}éx') required final String name,
});
''',
      Engine.sqlite,
      Engine.postgresql,
      '63 UTF-8 bytes',
    ),
  ]) {
    test(
      'runtime schema rejects $name before taking driver ownership',
      () async {
        await analyze(await generate(source, engine: generatedEngine));
        await runClient('''
Future<void> main() async {
  final driver = TrackedDriver(nativeDriver(Engine.${runtimeEngine.name}));
  final events = <DatabaseEvent>[];
  try {
    try {
      AppDatabase(driver, onEvent: events.add);
      throw StateError('Invalid model accepted');
    } on ArgumentError catch (error) {
      if (!error.toString().contains('$diagnostic')) { rethrow; }
    }
    if (driver.acquisitions != 0 || driver.closes != 0 || events.isNotEmpty) {
      throw StateError('Failed construction acquired or closed the caller driver');
    }
    final result = await driver.withConnection((connection) => connection.run('SELECT 1', []));
    if (result.rows.single.single != 1) { throw StateError('Caller driver is unusable'); }
  } finally { await driver.close(); }
  if (driver.closes != 1) { throw StateError('Caller must close the rejected driver'); }
}
''');
      },
      skip: runtimeEngine == Engine.postgresql && !_hasPostgres
          ? 'Set ORM_TEST_POSTGRES_SOCKET or ORM_TEST_POSTGRES_HOST for PostgreSQL'
          : false,
    );
  }

  test('SQLite reference aliases generate, draft and apply without changing reviewed names', () async {
    const model = '''
@Table('Children')
final class const Child({
  @PrimaryKey() required final int id,
  @References('parents', column: 'id') required final int parentId,
});
@Table('Parents')
final class const Parent({
  @PrimaryKey() @Column(name: 'ID') required final int id,
});
''';
    for (final invalid in [
      model,
      model.replaceFirst("@References('parents'", "@References('Parents'"),
    ]) {
      await expectLater(
        generate(invalid, engine: Engine.postgresql),
        throwsFormatException,
      );
    }
    expect(await File('${directory.path}/models.db.dart').exists(), isFalse);
    final sources = await generate(model);
    expect(sources.snapshot, contains('ForeignKey("parents", "id"'));
    await analyze(sources);
    final draft = '${directory.path}/v001_initial.dart';
    await draftMigration(
      after: await readSnapshot('${directory.path}/models.snapshot.dart'),
      version: 1,
      name: 'case_alias',
      outputPath: draft,
    );
    final run = File('${directory.path}/run.dart');
    await run.writeAsString('''
import 'models.db.dart';
import 'v001_initial.dart' as v001;
import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/sqlite.dart';
Future<void> main() async {
  final db = AppDatabase(SqliteDriver.memory());
  try {
    final history = MigrationHistory(engine: Engine.sqlite, migrations: [v001.migration]);
    final runner = MigrationRunner(db.database, history);
    await runner.apply();
    final parent = await db.Parents.create(id: 1);
    final child = await db.Children.create(id: 2, parentId: parent.id);
    if (child.parentId != 1 || (await db.Children.get(2))?.parentId != 1 || (await runner.apply()).isNotEmpty) { throw StateError('Wrong case-aliased foreign key'); }
  } finally { await db.close(); }
}
''');
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      run.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test(
    'reserved SQLite and overlong PostgreSQL names fail without output',
    () async {
      for (final (engine, table) in [
        (Engine.sqlite, 'SQLite_widgets'),
        (Engine.postgresql, '${List.filled(63, 't').join()}x'),
      ]) {
        await expectLater(
          generate('''
@Table('$table')
final class const Thing({@PrimaryKey() required final int id});
''', engine: engine),
          throwsArgumentError,
        );
        expect(
          await File('${directory.path}/models.db.dart').exists(),
          isFalse,
        );
        expect(
          await File('${directory.path}/models.snapshot.dart').exists(),
          isFalse,
        );
      }
    },
  );

  test(
    'filesystem model names become URI paths before Dart import emission',
    () async {
      final output = '${directory.path}/models.db.dart';
      for (final name in [
        'models#draft.dart',
        'models%20draft.dart',
        'models?draft.dart',
        'models draft.dart',
        '模型.dart',
      ]) {
        final input = File('${directory.path}/$name');
        await input.writeAsString("import 'package:orm/schema.dart';\n$row");
        final sources = await generateSchema(
          schemaPath: input.path,
          outputPath: output,
          engine: Engine.sqlite,
        );
        await analyze(sources);
      }
    },
    skip: Platform.isWindows
        ? 'Unix filenames containing question marks'
        : false,
  );

  test('generation and writing reject source/output symlink aliases', () async {
    final sources = await generate(row);
    final input = File('${directory.path}/models.dart');
    final before = await input.readAsString();
    final output = '${directory.path}/models.db.dart';
    await Link(output).create(input.absolute.path);
    await expectLater(generate(row), throwsFormatException);
    await expectLater(
      writeGeneratedSources(sources: sources, outputPath: output),
      throwsFormatException,
    );
    expect(await input.readAsString(), before);
    await Link(output).delete();
    await Link(snapshotPath(output)).create(input.absolute.path);
    await expectLater(generate(row), throwsFormatException);
    expect(await input.readAsString(), before);
  }, skip: Platform.isWindows ? 'Unix link behavior' : false);

  test('hard links to schema or sibling outputs are rejected; atomic replacement preserves other links', () async {
    final sources = await generate(row);
    final input = '${directory.path}/models.dart';
    final before = await File(input).readAsString();
    final output = '${directory.path}/models.db.dart';
    Future<void> link(String existing, String alias) async {
      final result = await Process.run('ln', [existing, alias]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    }

    await link(input, output);
    await expectLater(
      writeGeneratedSources(sources: sources, outputPath: output),
      throwsFormatException,
    );
    expect(await File(input).readAsString(), before);
    await File(output).delete();
    await File(output).writeAsString('old generated output');
    await link(output, snapshotPath(output));
    await expectLater(generate(row), throwsFormatException);
    await File(snapshotPath(output)).delete();
    final preserved = '${directory.path}/preserved.dart';
    await link(output, preserved);
    await writeGeneratedSources(sources: sources, outputPath: output);
    expect(await File(preserved).readAsString(), 'old generated output');
    expect(await File(output).readAsString(), sources.database);
    expect(await File(input).readAsString(), before);
    expect(directory.listSync().whereType<Directory>(), isEmpty);
  }, skip: Platform.isWindows ? 'Unix hard links' : false);

  test('relocation is rejected and aliases through parent directories cannot overwrite input', () async {
    final sources = await generate(row);
    await expectLater(
      writeGeneratedSources(
        sources: sources,
        outputPath: '${directory.path}/elsewhere.dart',
      ),
      throwsFormatException,
    );
    expect(await File('${directory.path}/elsewhere.dart').exists(), isFalse);
    final alias = '${directory.path}/alias';
    await Link(alias).create(directory.absolute.path);
    await expectLater(
      generateSchema(
        schemaPath: '${directory.path}/models.dart',
        outputPath: '$alias/models.dart',
        engine: Engine.sqlite,
      ),
      throwsFormatException,
    );
  }, skip: Platform.isWindows ? 'Unix directory symlinks' : false);
}
