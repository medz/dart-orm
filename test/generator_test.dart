import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:orm/database.dart';
import 'package:orm/dev.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory('test').createTemp('.generator-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<GeneratedSources> generate(
    String source, {
    Engine engine = Engine.sqlite,
  }) async {
    final input = File('${directory.path}/models.dart');
    await input.writeAsString("import 'package:orm/schema.dart';\n$source");
    return generateSchema(
      schemaPath: input.path,
      outputPath: '${directory.path}/models.db.dart',
      engine: engine,
    );
  }

  const row = '''
@Table('things')
final class Thing {
  const Thing({required this.id, required this.name, this.label});
  @PrimaryKey(autoIncrement: true)
  final int id;
  @Column(name: 'physical_name')
  final String name;
  @Column(defaultValue: 'fallback')
  final String? label;
}
''';

  test(
    'actually resolves models, emits typed client and independent frozen Dart',
    () async {
      final result = await generate('''$row
@SelectFrom(Thing)
typedef Card = ({int id, String name});
''');
      expect(result.database, contains('final class AppDatabase'));
      expect(result.database, contains('Database get database => _database'));
      expect(result.database, contains('ThingCreate get create'));
      expect(result.database, contains('required String name'));
      expect(result.database, contains('Object? label = _absent'));
      expect(result.database, contains('T == models.Card'));
      expect(result.database, contains('"name"'));
      expect(result.database, isNot(contains('part ')));
      expect(result.snapshot, contains('const frozenSchema = SchemaSnapshot'));
      expect(result.snapshot, contains('Engine.sqlite'));
      expect(result.snapshot, contains('physical_name'));
      expect(result.snapshot, isNot(contains('models.dart')));
      expect(result.snapshot, isNot(contains('Thing(')));
    },
  );

  test(
    'check detects missing and drifted outputs without modifying them',
    () async {
      final sources = await generate(row);
      final output = '${directory.path}/models.db.dart';
      expect(
        await writeGeneratedSources(
          sources: sources,
          outputPath: output,
          check: true,
        ),
        isFalse,
      );
      expect(await File(output).exists(), isFalse);
      expect(
        await writeGeneratedSources(sources: sources, outputPath: output),
        isTrue,
      );
      expect(
        await writeGeneratedSources(
          sources: sources,
          outputPath: output,
          check: true,
        ),
        isTrue,
      );
      final snapshot = File(snapshotPath(output));
      await snapshot.writeAsString('// changed\n');
      expect(
        await writeGeneratedSources(
          sources: sources,
          outputPath: output,
          check: true,
        ),
        isFalse,
      );
      expect(await snapshot.readAsString(), '// changed\n');
    },
  );

  test('each snapshot fixes one requested engine', () async {
    final result = await generate(row, engine: Engine.postgresql);
    expect(result.snapshot, contains('Engine.postgresql'));
    expect(result.snapshot, isNot(contains('Engine.sqlite')));
  });

  test('selection field names and exact nullability are validated', () async {
    for (final selection in [
      '({int id, String missing})',
      '({int id, int name})',
      '({int id, String label})',
      '(int, String)',
    ]) {
      await expectLater(
        generate('$row\n@SelectFrom(Thing)\ntypedef Broken = $selection;'),
        throwsFormatException,
      );
    }
  });

  test(
    'structurally equal records keep independent physical table identity',
    () async {
      final result = await generate('''$row
@Table('others')
final class Other {
  const Other({required this.id, required this.name});
  @PrimaryKey() final int id;
  @Column(name: 'different_name') final String name;
}
@SelectFrom(Thing) typedef ThingCard = ({int id, String name});
@SelectFrom(Other) typedef OtherCard = ({int id, String name});
''');
      expect(result.database, contains('T == models.ThingCard'));
      expect(result.database, contains('T == models.OtherCard'));
      expect(result.snapshot, contains('different_name'));
    },
  );

  test(
    'duplicate aliases for one structural selection share one decoder',
    () async {
      final result = await generate('''$row
@SelectFrom(Thing) typedef Card = ({int id, String name});
@SelectFrom(Thing) typedef Duplicate = ({String name, int id});
''');
      expect(
        RegExp(r'T == models\.(Card|Duplicate)').allMatches(result.database),
        hasLength(1),
      );
    },
  );

  test(
    'mutable fields, unsupported scalars and inconsistent constructors fail',
    () async {
      for (final source in [
        row
            .replaceFirst('final String name;', 'String name;')
            .replaceFirst('const Thing', 'Thing'),
        row.replaceFirst('final String name;', 'final Object name;'),
        row.replaceFirst('required this.name, ', ''),
        row
            .replaceFirst(
              '@PrimaryKey(autoIncrement: true)',
              '@PrimaryKey(autoIncrement: false)',
            )
            .replaceFirst('final int id;', 'final int? id;'),
        row.replaceFirst(
          "@Column(name: 'physical_name')",
          "@Column(name: 'id')",
        ),
        row.replaceFirst(
          "@Column(name: 'physical_name')",
          '@Column(defaultValue: 42)',
        ),
      ]) {
        await expectLater(generate(source), throwsFormatException);
      }
    },
  );

  test(
    'foreign keys require matching unique physical target columns',
    () async {
      await expectLater(
        generate(
          row.replaceFirst(
            "@Column(name: 'physical_name')",
            "@References('missing')",
          ),
        ),
        throwsFormatException,
      );
      await expectLater(
        generate(
          row.replaceFirst(
            "@Column(name: 'physical_name')",
            "@References('things')",
          ),
        ),
        throwsFormatException,
      );
      final result = await generate('''$row
@Table('links')
final class Link {
  const Link({required this.id, required this.thingId});
  @PrimaryKey() final int id;
  @Column(name: 'thing_id') @References('things') final int thingId;
}
''');
      expect(result.snapshot, contains('ForeignKey'));
      expect(result.snapshot, contains('thing_id'));
    },
  );

  test('SQL defaults preserve escaped Dart strings', () async {
    final result = await generate(
      row.replaceFirst("'fallback'", r"'price \$5 and \\path'"),
    );
    expect(result.snapshot, contains(r'\$5'));
    expect(result.snapshot, contains(r'\\path'));
  });

  test(
    'selection targets use class identity across imported libraries',
    () async {
      await File('${directory.path}/external.dart')
          .writeAsString('class Thing {}');
      await expectLater(
        generate('''
import 'external.dart' as external;
$row
@SelectFrom(external.Thing)
typedef Card = ({int id, String name});
'''),
        throwsFormatException,
      );
    },
  );

  test('reserved getters and identity defaults fail before output', () async {
    for (final source in [
      row.replaceFirst("'things'", "'class'"),
      row.replaceFirst("'things'", "'database'"),
      row.replaceFirst("'things'", "'hash_code'"),
      row.replaceFirst(
        '@PrimaryKey(autoIncrement: true)',
        '@PrimaryKey(autoIncrement: true) @Column(defaultValue: 1)',
      ),
    ]) {
      await expectLater(generate(source), throwsFormatException);
    }
  });

  test(
    'non-id primary keys do not collide with mutable field arguments',
    () async {
      final result = await generate('''
@Table('entries')
final class Entry {
  const Entry({required this.pk, required this.id, required this.key});
  @PrimaryKey(autoIncrement: true) final int pk;
  final int id;
  final int key;
}
''');
      final output = '${directory.path}/models.db.dart';
      await writeGeneratedSources(sources: result, outputPath: output);
      final collection = AnalysisContextCollection(
        includedPaths: [p.absolute(output)],
        sdkPath: p.dirname(p.dirname(Platform.resolvedExecutable)),
      );
      try {
        final resolved =
            await collection
                    .contextFor(p.absolute(output))
                    .currentSession
                    .getResolvedUnit(p.absolute(output))
                as ResolvedUnitResult;
        expect(resolved.diagnostics, isEmpty);
      } finally {
        await collection.dispose();
      }
    },
  );

  test('database name and output ownership are validated', () async {
    final input = File('${directory.path}/models.dart');
    await input.writeAsString("import 'package:orm/schema.dart';\n$row");
    await expectLater(
      generateSchema(
        schemaPath: input.path,
        outputPath: input.path,
        engine: Engine.sqlite,
      ),
      throwsFormatException,
    );
    await expectLater(
      generateSchema(
        schemaPath: input.path,
        outputPath: '${directory.path}/out.dart',
        databaseName: 'bad name',
        engine: Engine.sqlite,
      ),
      throwsFormatException,
    );
    for (final name in ['Database', 'ThingTable', 'TableQuery']) {
      await expectLater(
        generateSchema(
          schemaPath: input.path,
          outputPath: '${directory.path}/out.dart',
          databaseName: name,
          engine: Engine.sqlite,
        ),
        throwsFormatException,
      );
    }
  });
}
