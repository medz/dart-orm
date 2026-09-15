import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/schema.orm.dart';
import 'support/migration_project.dart';

void main() {
  Future<Map<String, Object?>> inspect(String file) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/orm.dart',
      'db',
      'inspect',
      '--sqlite',
      file,
      '--table',
      'users',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return jsonDecode(result.stdout as String) as Map<String, Object?>;
  }

  test('Dart CLI generates, reviews, upgrades and verifies constraints without overwriting history', () async {
    final project = await MigrationProject.create();
    try {
      final initial = SchemaSnapshot(appSchema);
      await project.target(initial);
      await project.run(['create', '0001_initial']);
      expect((await project.run(['check']))['valid'], true);
      await project.run(['plan'], code: 1);
      expect(await File(project.databasePath).exists(), false);
      expect((await project.run(['apply']))['applied'], ['0001_initial']);
      final next = SchemaSnapshot([
        TableSchema(
          'users',
          columns: [
            ...usersSchema.columns,
            Column('status', Codecs.text, defaultSql: "'active'"),
            Column(
              'email_size',
              Codecs.integer,
              computed: const ComputedColumn('length(email)'),
            ),
          ],
          primaryKey: usersSchema.primaryKey,
          uniqueKeys: usersSchema.uniqueKeys,
          checks: const [
            CheckSchema('valid_status', "status IN ('active', 'disabled')"),
          ],
        ),
        postsSchema,
      ]);
      await project.target(next);
      await project.run(['create', '0002_status']);
      expect((await project.run(['plan']))['pending'], hasLength(1));
      expect((await project.run(['status']))['applied'], hasLength(1));
      await project.run(['apply']);
      final catalog = await inspect(project.databasePath);
      expect((catalog['checks'] as List).single, {
        'name': 'valid_status',
        'expression': "status IN ('active', 'disabled')",
      });
      expect(
        (catalog['columns'] as List).cast<Map<String, Object?>>().singleWhere(
          (c) => c['name'] == 'email_size',
        )['computed'],
        {'expression': 'length(email)', 'storage': 'stored'},
      );
      expect((await project.run(['verify']))['matches'], true);
      await project.target(initial);
      expect((await project.run(['verify'], code: 2))['matches'], false);
      await project.target(next);
      expect((await project.run(['create', '0003_same']))['created'], null);
      expect(
        await File('${project.migrationDirectory}/m0003_same.dart').exists(),
        false,
      );
      final file = File('${project.migrationDirectory}/m0001_initial.dart');
      final saved = await file.readAsString();
      await project.target(initial);
      await project.run([
        'create',
        '0001_initial',
        '--allow-destructive',
      ], code: 1);
      expect(await file.readAsString(), saved);
    } finally {
      await project.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Dart CLI baselines existing rows; read-only connections and invalid options reject writes', () async {
    final project = await MigrationProject.create();
    try {
      await project.target(SchemaSnapshot(appSchema));
      await project.run(['create', '0001_baseline']);
      final db = await sqlite(SqliteOptions.file(project.databasePath));
      try {
        for (final sql in createSchema(appSchema, SqlDialect.sqlite)) {
          await db.execute(sql);
        }
        await db.users.create(email: 'existing');
      } finally {
        await db.close();
      }
      expect((await project.run(['baseline']))['matches'], true);
      final read = await sqlite(SqliteOptions.readOnly(project.databasePath));
      try {
        expect((await read.users.single()).email, 'existing');
        expect(await Migrator(read).history(), hasLength(1));
        await expectLater(
          read.users.create(email: 'forbidden'),
          throwsA(isA<SqliteFailure>()),
        );
      } finally {
        await read.close();
      }
      await project.run(['verify', '--tls', 'disable'], code: 64);
      await project.run(['check', '--unknown', 'x'], code: 64);
      final removed = await Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/orm.dart',
        'migration',
        'create',
        '0001_legacy',
        '--schema',
        'unused.json',
      ]);
      expect(removed.exitCode, 64);
    } finally {
      await project.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) {
    test('Dart PostgreSQL configuration supports checked nontransactional recovery operations', () async {
      final schema = 'orm_cli_${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final project = await MigrationProject.create(postgresSchema: schema);
      final admin = postgres(
        PostgresOptions(
          url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
          tls: .disable,
        ),
      );
      var created = false;
      try {
        await admin.execute(SqlCommand('CREATE SCHEMA "$schema"'));
        created = true;
        await project.target(SchemaSnapshot(appSchema));
        final first = await project.run(['create', '0001_initial']);
        expect((await project.run(['check']))['valid'], true);
        expect((await project.run(['plan']))['pending'], hasLength(1));
        expect((await project.run(['status']))['applied'], isEmpty);
        expect((await project.run(['apply']))['applied'], ['0001_initial']);
        expect((await project.run(['verify']))['matches'], true);
        await project.append(
          Migration.steps('0002_index', {
            .postgres: [
              CheckedSql.createIndex(
                'users',
                const IndexSchema('nickname_lookup', ['nickname']),
              ),
            ],
          }, previous: first['checksum'] as String),
        );
        expect((await project.run(['plan']))['atomic'], false);
        expect((await project.run(['apply']))['applied'], ['0002_index']);
        final progress = (await project.run(['status']))['progress'] as List;
        expect((progress.single as Map)['state'], 'complete');
      } finally {
        if (created) {
          await admin.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
        }
        await admin.close();
        await project.dispose();
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
