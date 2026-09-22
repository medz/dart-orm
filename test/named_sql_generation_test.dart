import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:orm/generate.dart';
import 'package:orm/builder.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/cli.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory('.dart_tool').createTemp('named-generation-');
  });
  tearDown(() => directory.delete(recursive: true));
  File file(String name) => File('${directory.path}/$name');

  Future<void> declaration(String result, String options, String sql) async {
    await file('query.dart').writeAsString(
      "import 'package:orm/schema.dart';\nfinal sample = sqlQuery(result: $result, $options);\n",
    );
    await file('query.sql').writeAsString(sql);
  }

  test(
    'source contracts reject missing/extra parameters and row metadata',
    () async {
      for (final (result, options, sql) in [
        (
          '(n: integer(),)',
          "parameters: (missing: integer(),), sqlite: 'query.sql'",
          'SELECT :n AS n',
        ),
        ('(n: identity(),)', "sqlite: 'query.sql'", 'SELECT 1 AS n'),
        (
          "(n: integer().computed('1'),)",
          "sqlite: 'query.sql'",
          'SELECT 1 AS n',
        ),
        (
          "(n: text(clientDefault: String.fromEnvironment),)",
          "sqlite: 'query.sql'",
          'SELECT 1 AS n',
        ),
        (
          '(n: dateTime(precision: 2),)',
          "sqlite: 'query.sql'",
          'SELECT 1 AS n',
        ),
        (
          '(n: integer(), duplicate: text(name: "n"))',
          "sqlite: 'query.sql'",
          'SELECT 1 AS n',
        ),
        ('(integer(),)', "sqlite: 'query.sql'", 'SELECT 1 AS n'),
        ('(n: integer(),)', '', 'SELECT 1 AS n'),
        (
          '(n: integer(),)',
          "sqlite: 'query.sql'",
          'SELECT 1; DELETE FROM posts',
        ),
      ]) {
        await declaration(result, options, sql);
        await expectLater(
          generateQueries(file('query.dart').path),
          throwsA(anyOf(isA<GenerationException>(), isA<OrmException>())),
        );
      }
    },
  );

  test('generated query classes reject symbol collisions', () async {
    await file('query.sql').writeAsString('SELECT 1 AS n');
    for (final declarations in [
      "final query = sqlQuery(result: (n: integer(),), sqlite: 'query.sql');",
      "final stats = sqlQuery(result: (n: integer(),), sqlite: 'query.sql');"
          "final statsFields = sqlQuery(result: (n: integer(),), sqlite: 'query.sql');",
    ]) {
      await file('query.dart')
          .writeAsString("import 'package:orm/schema.dart';\n$declarations");
      await expectLater(
        generateQueries(file('query.dart').path),
        throwsA(
          isA<GenerationException>().having(
            (error) => error.toString(),
            'message',
            contains('ambiguous'),
          ),
        ),
      );
    }
  });

  test('SQL edits and modified generated code fail freshness checks', () async {
    await declaration(
      '(n: integer(),)',
      "sqlite: 'query.sql'",
      'SELECT 1 AS n',
    );
    final source = file('query.dart').path;
    await writeGeneratedQueries(source);
    await checkGeneratedQueries(source);
    expect(await file('query.queries.json').exists(), false);
    await file('query.sql').writeAsString('SELECT 2 AS n');
    await expectLater(
      checkGeneratedQueries(source),
      throwsA(isA<GenerationException>()),
    );
    await writeGeneratedQueries(source);
    await file('query.queries.dart')
        .writeAsString('// modified\n', mode: FileMode.append);
    await expectLater(
      checkGeneratedQueries(source),
      throwsA(isA<GenerationException>()),
    );
    await expectLater(
      writeGeneratedQueries(source, output: source),
      throwsA(isA<GenerationException>()),
    );
    expect(await file('query.dart').readAsString(), contains('sqlQuery'));
    final output = file('custom.dart').path;
    await writeGeneratedQueries(source, output: output);
    await checkGeneratedQueries(source, output: output);
    await file('query.dart').writeAsString(
      (await file(
        'query.dart',
      ).readAsString()).replaceAll('integer()', 'real()'),
    );
    await expectLater(
      checkGeneratedQueries(source, output: output),
      throwsA(isA<GenerationException>()),
    );
  });

  test(
    'asset builder and standalone generator emit identical SQL contracts',
    () async {
      final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
      await files.testing.loadIsolateSources();
      const root = 'test/support/named_sql/queries.dart';
      final inputs = <String, String>{};
      for (final name in [
        'queries.dart',
        'stats.sqlite.sql',
        'stats.postgres.sql',
        'echo.sql',
        'constant.sql',
      ]) {
        final path = 'test/support/named_sql/$name';
        inputs['orm|$path'] = await File(path).readAsString();
      }
      final result = await testBuilder(
        _QueryRoot(),
        inputs,
        rootPackage: 'orm',
        readerWriter: files,
        generateFor: {'orm|$root'},
        flattenOutput: true,
      );
      expect(result.succeeded, true, reason: result.errors.toString());
      final standalone = await generateQueries(root);
      expect(
        files.testing.readString(
          AssetId('orm', 'test/support/named_sql/queries.queries.dart'),
        ),
        standalone.dart,
      );
    },
  );

  test('generated APIs reject missing/wrong parameters and result types', () async {
    final invalid = [
      'db.authorStats();',
      'db.authorStats(minimum: "wrong");',
      'db.authorStats(minimum: 0, author: 1);',
      'db.authorStats(minimum: 0).select((s) => s.missing);',
      'db.authorStats(minimum: 0).where((s) => s.points.eq("wrong"));',
      'final Future<List<String>> wrong = db.authorStats(minimum: 0).get();',
    ];
    final negative = file('negative.dart').absolute;
    await negative.writeAsString(
      "import 'package:orm/orm.dart';\nimport '../../test/support/named_sql/queries.queries.dart';\nvoid wrong(Database<Sqlite> db) {\n${invalid.join('\n')}\n}\n",
    );
    final contexts = AnalysisContextCollection(includedPaths: [negative.path]);
    try {
      final result =
          await contexts
                  .contextFor(negative.path)
                  .currentSession
                  .getResolvedUnit(negative.path)
              as ResolvedUnitResult;
      final errors = result.diagnostics.where(
        (e) => e.severity.name.toLowerCase() == 'error',
      );
      expect(
        errors.any(
          (e) => e.diagnosticCode.lowerCaseName.contains('uri_does_not_exist'),
        ),
        false,
      );
      for (var i = 0; i < invalid.length; i++) {
        expect(
          errors.any(
            (e) => result.lineInfo.getLocation(e.offset).lineNumber == i + 4,
          ),
          true,
          reason: invalid[i],
        );
      }
    } finally {
      await contexts.dispose();
    }
  });

  test(
    'CLI checks a persistent SQLite database without creating missing files',
    () async {
      await declaration(
        '(n: integer(),)',
        "sqlite: 'query.sql'",
        'SELECT COUNT(*) AS n FROM entries',
      );
      final run = runCli;
      final generate = await run([
        'queries',
        'generate',
        file('query.dart').path,
      ]);
      expect(
        generate.exitCode,
        0,
        reason: '${generate.stdout}\n${generate.stderr}',
      );
      final database = await sqlite(
        SqliteOptions.file(file('database.db').path),
      );
      await database.execute(SqlCommand('CREATE TABLE entries (n INTEGER)'));
      await database.close();
      final args = [
        '--json',
        'queries',
        'check',
        '--source',
        file('query.dart').path,
        '--sqlite',
      ];
      final checked = await run([...args, file('database.db').path]);
      expect(
        checked.exitCode,
        0,
        reason: '${checked.stdout}\n${checked.stderr}',
      );
      expect(checked.stdout, contains('"structureChecked": true'));
      final missing = file('missing.db');
      final rejected = await run([...args, missing.path]);
      expect(rejected.exitCode, isNot(0));
      expect(await missing.exists(), false);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

// build_test loads root-package lib assets in addition to the requested input.
final class _QueryRoot implements Builder {
  final Builder delegate = ormQueryBuilder(BuilderOptions.empty);
  @override
  Map<String, List<String>> get buildExtensions => delegate.buildExtensions;
  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId.path == 'test/support/named_sql/queries.dart') {
      await delegate.build(step);
    }
  }
}
