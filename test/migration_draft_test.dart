import 'dart:io';

import 'package:orm/database.dart';
import 'package:orm/dev.dart';
import 'package:orm/migration.dart';
import 'package:orm/schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory('test').createTemp('.migration-draft-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  SchemaSnapshot schema(Engine engine, {bool addLabel = false}) =>
      SchemaSnapshot(
        engine: engine,
        tables: [
          TableDefinition('things', [
            const ColumnDefinition(
              name: 'id',
              field: 'id',
              type: ScalarType.integer,
              primaryKey: true,
              identity: true,
            ),
            const ColumnDefinition(
              name: 'name',
              field: 'name',
              type: ScalarType.text,
              defaultValue: "it's \$literal",
            ),
            if (addLabel)
              const ColumnDefinition(
                name: 'label',
                field: 'label',
                type: ScalarType.text,
                nullable: true,
              ),
          ]),
        ],
      );

  test(
    'drafted static history applies and preserves existing SQLite data',
    () async {
      final first = '${directory.path}/v001_initial.dart';
      final second = '${directory.path}/v002_label.dart';
      final before = schema(Engine.sqlite);
      final after = schema(Engine.sqlite, addLabel: true);
      await draftMigration(
        after: before,
        version: 1,
        name: 'initial',
        outputPath: first,
      );
      await draftMigration(
        before: await readSnapshot(first),
        after: after,
        version: 2,
        name: 'add_label',
        outputPath: second,
      );
      final restored = await readSnapshot(second);
      expect(restored.tables.single.columns.last.nullable, isTrue);
      expect(restored.tables.single.columns[1].defaultValue, "it's \$literal");
      final steps = planSchemaChange(before, after).steps;
      final fingerprint = migrationFingerprint(
        version: 2,
        name: 'add_label',
        engine: Engine.sqlite,
        steps: steps,
        snapshot: after,
      );
      final source = await File(second).readAsString();
      expect(
        source,
        contains(RegExp('reviewedFingerprint:\\s*"$fingerprint"')),
      );
      expect(source, isNot(contains('models')));
      expect(source, isNot(contains('migrationFingerprint(')));

      final runner = File('${directory.path}/run.dart');
      await runner.writeAsString(r'''
import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/sqlite.dart';
import 'v001_initial.dart' as v001;
import 'v002_label.dart' as v002;
Future<void> main() async {
  final database = openDatabase(SqliteDriver.memory());
  try {
    await MigrationRunner(database, MigrationHistory(engine: Engine.sqlite, migrations: [v001.migration])).apply();
    await database.session.run('INSERT INTO "things" DEFAULT VALUES');
    await MigrationRunner(database, MigrationHistory(engine: Engine.sqlite, migrations: [v001.migration, v002.migration])).apply();
    final result = await database.session.run('SELECT "name", "label" FROM "things"');
    if (result.rows.single[0] != r"it's $literal" || result.rows.single[1] != null) {
      throw StateError('Existing data was not preserved: ${result.rows}');
    }
    print('Migration history applied and preserved data.');
  } finally { await database.close(); }
}
''');
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        runner.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('Migration history applied and preserved data.'),
      );
    },
  );

  test(
    'PostgreSQL draft contains only its engine SQL and frozen metadata',
    () async {
      final path = '${directory.path}/postgres.dart';
      await draftMigration(
        after: schema(Engine.postgresql),
        version: 1,
        name: 'postgres_initial',
        outputPath: path,
      );
      final source = await File(path).readAsString();
      expect(source, contains('BIGINT GENERATED ALWAYS AS IDENTITY'));
      expect(source, isNot(contains('AUTOINCREMENT')));
      expect((await readSnapshot(path)).engine, Engine.postgresql);
    },
  );

  test('existing historical files cannot be overwritten', () async {
    final output = File('${directory.path}/history.dart');
    await output.writeAsString('preserve reviewed source');
    await expectLater(
      draftMigration(
        after: schema(Engine.sqlite),
        version: 1,
        name: 'initial',
        outputPath: output.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await output.readAsString(), 'preserve reviewed source');
  });

  test(
    'unsafe changes, no changes and mixed engines create no output',
    () async {
      final before = schema(Engine.sqlite);
      final output = '${directory.path}/unsafe.dart';
      for (final after in [
        before,
        const SchemaSnapshot(engine: Engine.sqlite, tables: []),
        schema(Engine.postgresql),
      ]) {
        await expectLater(
          draftMigration(
            before: before,
            after: after,
            version: 2,
            name: 'unsafe',
            outputPath: output,
          ),
          throwsA(anyOf(isA<StateError>(), isA<ArgumentError>())),
        );
        expect(await File(output).exists(), isFalse);
      }
    },
  );

  test(
    'snapshot reading accepts private const history without executing it',
    () async {
      final output = '${directory.path}/initial.dart';
      await draftMigration(
        after: schema(Engine.sqlite),
        version: 1,
        name: 'initial',
        outputPath: output,
      );
      final source = (await File(
        output,
      ).readAsString()).replaceAll('frozenSchema', '_saved');
      await File(output).writeAsString(
        "$source\nfinal sideEffect = throw StateError('must not execute');\n",
      );
      expect((await readSnapshot(output)).tables.single.name, 'things');
    },
  );

  test('ambiguous snapshots require the explicit frozenSchema name', () async {
    final output = '${directory.path}/initial.dart';
    await draftMigration(
      after: schema(Engine.sqlite),
      version: 1,
      name: 'initial',
      outputPath: output,
    );
    final source = (await File(
      output,
    ).readAsString()).replaceAll('frozenSchema', '_saved');
    await File(output).writeAsString('$source\nconst another = _saved;\n');
    await expectLater(readSnapshot(output), throwsFormatException);
  });

  test(
    'CLI drafts an initial migration with explicit ownership and version',
    () async {
      final output = '${directory.path}/cli.dart';
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/orm.dart',
        'migration',
        'draft',
        '--to',
        p.join('example', 'models.snapshot.dart'),
        '--out',
        output,
        '--version',
        '1',
        '--name',
        'initial',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('Review the SQL'));
      expect((await readSnapshot(output)).tables, isNotEmpty);
    },
  );
}
