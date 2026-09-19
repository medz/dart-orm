import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  late BuildFixture fixture;
  setUp(() async {
    fixture = await BuildFixture.create(ormPath: Directory.current.path);
  });
  tearDown(() => fixture.dispose());

  test('Dart emission preserves storage metadata and every operation without application imports', () async {
    final table = TableSchema(
      'quoted"table',
      columns: [
        Column('id', Codecs.integer, integerBits: 32),
        Column('amount', Codecs.decimal, decimalPrecision: 20, decimalScale: 4),
        Column('moment', Codecs.dateTime, temporalPrecision: 3),
        Column('local', Codecs.localDateTime, temporalPrecision: 2),
        Column('day', Codecs.date),
        Column('time', Codecs.time),
        Column('data', Codecs.bytes),
        Column('huge', Codecs.bigint),
        Column('document', Codecs.json),
        Column('active', Codecs.boolean, defaultSql: 'TRUE'),
        Column('ratio', Codecs.real),
        Column(
          'label',
          Codecs.text.nullable(),
          nullable: true,
          defaultSql: r"'cost $5'",
        ),
        Column(
          'derived',
          Codecs.integer,
          computed: const ComputedColumn('id + 1'),
        ),
      ],
      primaryKey: ['id'],
      uniqueKeys: const [
        ['label', 'id'],
      ],
      indexes: const [
        IndexSchema('label_index', ['label']),
      ],
      checks: const [
        CheckSchema.forDialects(
          'positive',
          sqlite: 'id > 0',
          postgres: 'id > 0',
        ),
      ],
      foreignKeys: const [
        ForeignKey(['id'], 'other', ['id'], onDelete: 'CASCADE'),
      ],
    );
    final other = TableSchema(
      'other',
      columns: [
        Column('id', Codecs.integer, integerBits: 32),
        Column('label', Codecs.text),
      ],
      primaryKey: ['id'],
    );
    final snapshot = SchemaSnapshot([other, table]);
    for (final dialect in [SqlDialect.sqlite, SqlDialect.postgres]) {
      final migration = Migration.steps(
        '0001_literals',
        dialect == SqlDialect.sqlite
            ? [
                ExecuteSql(
                  "SELECT 'quote\" and dollar\$ and \\ slash'\n-- retained",
                ),
                RebuildTable(table, table, copy: {'id': 'id'}),
                DropTable('gone'),
              ]
            : [
                ExecuteSql('SELECT 1'),
                DropConstraint('other', {
                  'kind': 'u',
                  'columns': ['id'],
                }),
                CheckedSql(
                  'CREATE INDEX CONCURRENTLY foo ON other(id)',
                  readyWhen: 'SELECT true',
                  doneWhen: 'SELECT false',
                ),
                Backfill(
                  other,
                  set: {'label': "'done'"},
                  doneWhen: 'SELECT true',
                ),
              ],
        snapshot: snapshot,
        dialect: dialect,
      );
      await fixture.write('lib/frozen.dart', schemaSource(snapshot));
      await fixture.write(
        'lib/m0001_literals.dart',
        migrationSource(migration),
      );
      await fixture.write('bin/check.dart', '''
import '../lib/frozen.dart' as s;
import '../lib/m0001_literals.dart' as m;
void main() {
  print(s.schema.checksum);
  print(m.migration.checksum);
  if (m.migration.checksum != m.migrationChecksum) throw StateError('fingerprint');
}
''');
      final source = await fixture
          .file('lib/m0001_literals.dart')
          .readAsString();
      expect(source, isNot(contains('fromJson')));
      expect(source, isNot(contains('schema.orm.dart')));
      final result = await fixture.run(['run', 'bin/check.dart']);
      expect(result.output, contains(snapshot.checksum));
      expect(result.output, contains(migration.checksum));
      await fixture.run([
        'analyze',
        'lib/frozen.dart',
        'lib/m0001_literals.dart',
        'bin/check.dart',
      ]);
    }
  });

  test('project CLI creates Dart history, upgrades a database and preserves recorded fingerprints', () async {
    final initial = TableSchema(
      'people',
      columns: [Column('id', Codecs.integer), Column('name', Codecs.text)],
      primaryKey: ['id'],
    );
    await fixture.write(
      'lib/target.dart',
      schemaSource(SchemaSnapshot([initial])),
    );
    await writeMigrationRegistry(
      '${fixture.directory.path}/lib/migrations',
      dialect: SqlDialect.sqlite,
    );
    await fixture.write('bin/migrate.dart', r'''
import 'package:orm/migrate_cli.dart';
import 'package:orm/sqlite.dart';
import '../lib/target.dart';
import '../lib/migrations/migrations.g.dart';
Future<void> main(List<String> args) => runMigrationCli(args,
  history: migrationHistory,
  directory: 'lib/migrations',
  schema: schema,
  connect: ({required readOnly}) async => (await sqlite(readOnly ? SqliteOptions.readOnly('database.sqlite') : SqliteOptions.file('database.sqlite'))).sql,
);
''');
    Future<Map<String, Object?>> command(
      List<String> args, {
      int code = 0,
    }) async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/migrate.dart',
        ...args,
      ], workingDirectory: fixture.directory.path);
      expect(
        result.exitCode,
        code,
        reason: '${result.stdout}\n${result.stderr}',
      );
      return code == 0
          ? jsonDecode(result.stdout as String) as Map<String, Object?>
          : {};
    }

    expect((await command(['check']))['valid'], true);
    expect(await fixture.file('database.sqlite').exists(), false);
    final created = await command(['create', '0001_people']);
    expect(created['created'], 'lib/migrations/m0001_people.dart');
    expect(
      await fixture.file('lib/migrations/0001_people.json').exists(),
      false,
    );
    await command(['plan'], code: 1);
    expect(await fixture.file('database.sqlite').exists(), false);
    expect((await command(['apply']))['applied'], ['0001_people']);
    final db = await sqlite(
      SqliteOptions.file(fixture.file('database.sqlite').path),
    );
    try {
      await db.execute(SqlCommand("INSERT INTO people VALUES(1, 'Ada')"));
    } finally {
      await db.close();
    }
    final after = TableSchema(
      'people',
      columns: [
        ...initial.columns,
        Column('nickname', Codecs.text.nullable(), nullable: true),
      ],
      primaryKey: ['id'],
    );
    await fixture.write(
      'lib/target.dart',
      schemaSource(SchemaSnapshot([after])),
    );
    await command(['create', '0002_nickname']);
    expect((await command(['plan']))['pending'], hasLength(1));
    expect((await command(['apply']))['applied'], ['0002_nickname']);
    expect((await command(['verify']))['matches'], true);
    expect((await command(['apply']))['applied'], isEmpty);
    final read = await sqlite(
      SqliteOptions.readOnly(fixture.file('database.sqlite').path),
    );
    try {
      expect(
        (await read.execute(SqlCommand('SELECT name, nickname FROM people')))
            .rows
            .single,
        ['Ada', null],
      );
    } finally {
      await read.close();
    }

    final latest = fixture.file('lib/migrations/m0002_nickname.dart');
    final source = await latest.readAsString();
    await latest.writeAsString(source.replaceAll('ADD COLUMN', 'ADD  COLUMN'));
    await command(['check'], code: 1);
    await writeMigrationRegistry(
      '${fixture.directory.path}/lib/migrations',
      dialect: SqlDialect.sqlite,
    );
    await command(['check'], code: 1);
    await command(['record', '0001_people'], code: 1);
    await command(['record', '0002_nickname']);
    expect((await command(['check']))['valid'], true);
    // Re-recording source cannot change an independently applied DB fingerprint.
    await command(['plan'], code: 1);
    await command(['apply', '--max-backfill-batches', '0'], code: 64);
  }, timeout: const Timeout(Duration(minutes: 3)));
  test(
    'AOT migration bundle works without Dart sources or migration assets',
    () async {
      final schema = SchemaSnapshot([
        TableSchema(
          'people',
          columns: [Column('id', Codecs.integer), Column('name', Codecs.text)],
          primaryKey: ['id'],
        ),
      ]);
      final initial = Migration(
        '0001_initial',
        [
          ...createSchema(schema.tables, SqlDialect.sqlite).map((s) => s.sql),
          "INSERT INTO people(id, name) VALUES (7, 'retained')",
        ],
        snapshot: schema,
        dialect: SqlDialect.sqlite,
      );
      await fixture.write('lib/target.dart', schemaSource(schema));
      await writeMigration(
        initial,
        directory: '${fixture.directory.path}/lib/migrations',
        history: MigrationHistory([], dialect: SqlDialect.sqlite),
      );
      await fixture.write('bin/migrate.dart', """
import 'package:orm/migrate_cli.dart';
import 'package:orm/sqlite.dart';
import '../lib/target.dart';
import '../lib/migrations/migrations.g.dart';
Future<void> main(List<String> args) => runMigrationCli(args,
  directory: 'lib/migrations', history: migrationHistory, schema: schema,
  connect: ({required readOnly}) async => (await sqlite(readOnly ? const SqliteOptions.readOnly('database.sqlite') : const SqliteOptions.file('database.sqlite'))).sql,
);
""");
      await fixture.run([
        'build',
        'cli',
        '--target',
        'bin/migrate.dart',
        '--output',
        'deployment',
      ]);
      await Directory('${fixture.directory.path}/lib').delete(recursive: true);
      await Directory('${fixture.directory.path}/bin').delete(recursive: true);
      await Directory('${fixture.directory.path}/.dart_tool')
          .delete(recursive: true);
      await fixture.file('pubspec.yaml').delete();
      final working = await Directory('${fixture.directory.path}/run').create();
      final executable =
          '${fixture.directory.path}/deployment/bundle/bin/migrate';
      Future<Map<String, Object?>> run(String command, {int code = 0}) async {
        final result = await Process.run(executable, [
          command,
        ], workingDirectory: working.path);
        expect(
          result.exitCode,
          code,
          reason: '$command: ${result.stdout}\n${result.stderr}',
        );
        return code == 0
            ? jsonDecode(result.stdout as String) as Map<String, Object?>
            : {};
      }

      expect((await run('check'))['valid'], true);
      await run('plan', code: 1);
      final path = '${working.path}/database.sqlite';
      expect(await File(path).exists(), false);
      expect((await run('apply'))['applied'], ['0001_initial']);
      expect((await run('apply'))['applied'], isEmpty);
      expect((await run('verify'))['matches'], true);
      final db = await sqlite(SqliteOptions.readOnly(path));
      try {
        expect(
          (await db.execute(SqlCommand('SELECT id, name FROM people'))).rows,
          [
            [7, 'retained'],
          ],
        );
        expect(
          (await Migrator(db.sql).history()).single.checksum,
          initial.checksum,
        );
      } finally {
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
