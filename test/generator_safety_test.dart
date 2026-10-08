import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:orm/database.dart';
import 'package:orm/dev.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
  }) async {
    await File('${directory.path}/models.dart')
        .writeAsString("import 'package:orm/schema.dart';\n$model");
    return generateSchema(
      schemaPath: '${directory.path}/models.dart',
      outputPath: '${directory.path}/models.db.dart',
      databaseName: name,
      engine: Engine.sqlite,
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

  const row = '''
@Table('things')
final class const Thing({
  @PrimaryKey(autoIncrement: true) required final int id,
  @Unique() required final String name,
  final String? label,
});
''';

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
      for (final name in [
        'Future',
        'List',
        'Map',
        'Object',
        'String',
        'DateTime',
        'Stream',
        'ArgumentError',
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
