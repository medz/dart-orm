import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../example/schema.orm.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('orm-cli-');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<Map<String, Object?>> cli(List<String> args, {int code = 0}) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/orm.dart',
      ...args,
    ]);
    expect(
      result.exitCode,
      code,
      reason: '${args.take(2).join(' ')}: ${result.stderr}\n${result.stdout}',
    );
    if (code != 0 && code != 2) return {};
    return jsonDecode(result.stdout as String) as Map<String, Object?>;
  }

  Future<String> writeSnapshot(String name, SchemaSnapshot snapshot) async {
    final file = File(p.join(directory.path, '$name.json'));
    await file.writeAsString(jsonEncode(snapshot.toJson()));
    return file.path;
  }

  test('CLI generates checks reviews applies and verifies versioned migration files', () async {
    final migrations = p.join(directory.path, 'migrations');
    final file = p.join(directory.path, 'database.sqlite');
    final initial = await writeSnapshot('initial', SchemaSnapshot(appSchema));
    final created = await cli([
      'migration',
      'create',
      '0001_initial',
      '--schema',
      initial,
      '--dir',
      migrations,
    ]);
    expect(created['checksum'], isNotEmpty);
    final checked = await cli(['migration', 'check', '--dir', migrations]);
    expect(checked['valid'], true);
    // Opening a nonexistent database in planning mode must not create it.
    await cli([
      'migrate',
      'plan',
      '--sqlite',
      file,
      '--dir',
      migrations,
    ], code: 1);
    expect(await File(file).exists(), false);
    final applied = await cli([
      'migrate',
      'apply',
      '--sqlite',
      file,
      '--dir',
      migrations,
    ]);
    expect(applied['applied'], ['0001_initial']);
    final check = await cli([
      'db',
      'verify',
      '--sqlite',
      file,
      '--schema',
      initial,
    ]);
    expect(check['matches'], true);
    final info = await cli([
      'db',
      'inspect',
      '--sqlite',
      file,
      '--table',
      'users',
    ]);
    expect(info['primaryKey'], ['id']);
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
    final nextPath = await writeSnapshot('next', next);
    await cli([
      'migration',
      'create',
      '0002_status',
      '--schema',
      nextPath,
      '--dir',
      migrations,
    ]);
    final plan = await cli([
      'migrate',
      'plan',
      '--sqlite',
      file,
      '--dir',
      migrations,
    ]);
    expect((plan['pending'] as List).length, 1);
    expect(
      ((await cli(['migrate', 'status', '--sqlite', file]))['applied'] as List)
          .length,
      1,
    );
    await cli(['migrate', 'apply', '--sqlite', file, '--dir', migrations]);
    final constrained = await cli([
      'db',
      'inspect',
      '--sqlite',
      file,
      '--table',
      'users',
    ]);
    expect((constrained['checks'] as List).single, {
      'name': 'valid_status',
      'expression': "status IN ('active', 'disabled')",
    });
    expect(
      (constrained['columns'] as List).cast<Map<String, Object?>>().singleWhere(
        (c) => c['name'] == 'email_size',
      )['computed'],
      {'expression': 'length(email)', 'storage': 'stored'},
    );
    expect(
      (await cli([
        'db',
        'verify',
        '--sqlite',
        file,
        '--schema',
        nextPath,
      ]))['matches'],
      true,
    );
    final drift = await cli([
      'db',
      'verify',
      '--sqlite',
      file,
      '--schema',
      initial,
    ], code: 2);
    expect(drift['matches'], false);
    final unchanged = await cli([
      'migration',
      'create',
      '0003_same',
      '--schema',
      nextPath,
      '--dir',
      migrations,
    ]);
    expect(unchanged['created'], null);
    expect(await File(p.join(migrations, '0003_same.json')).exists(), false);
    // A rejected duplicate never overwrites the existing reviewed file.
    final saved = await File(p.join(migrations, '0001_initial.json'))
        .readAsString();
    await cli([
      'migration',
      'create',
      '0001_initial',
      '--schema',
      initial,
      '--dir',
      migrations,
      '--allow-destructive',
    ], code: 1);
    expect(
      await File(p.join(migrations, '0001_initial.json')).readAsString(),
      saved,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'CLI baselines existing SQLite rows and read-only options reject writes',
    () async {
      final migrations = p.join(directory.path, 'migrations');
      final file = p.join(directory.path, 'existing.sqlite');
      final snapshot = await writeSnapshot('schema', SchemaSnapshot(appSchema));
      await cli([
        'migration',
        'create',
        '0001_baseline',
        '--schema',
        snapshot,
        '--dir',
        migrations,
      ]);
      final db = await sqlite(SqliteOptions.file(file));
      try {
        for (final sql in createSchema(appSchema, SqlDialect.sqlite)) {
          await db.execute(sql);
        }
        await db.users.create(email: 'existing');
      } finally {
        await db.close();
      }
      final result = await cli([
        'db',
        'baseline',
        '--sqlite',
        file,
        '--dir',
        migrations,
      ]);
      expect(result['matches'], true);
      final read = await sqlite(SqliteOptions.readOnly(file));
      try {
        expect((await read.users.single()).email, 'existing');
        expect((await Migrator(read).history()).length, 1);
        await expectLater(
          read.users.create(email: 'forbidden'),
          throwsA(isA<SqliteFailure>()),
        );
      } finally {
        await read.close();
      }
      await cli([
        'db',
        'verify',
        '--sqlite',
        file,
        '--schema',
        snapshot,
        '--tls',
        'disable',
      ], code: 64);
      await cli([
        'migration',
        'check',
        '--dir',
        migrations,
        '--unknown',
        'x',
      ], code: 64);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    test('CLI uses PostgreSQL-specific connection configuration for apply and verification', () async {
      const schema = 'orm_cli_tests';
      final admin = postgres(
        PostgresOptions(url: Uri.parse(url), tls: .disable),
      );
      await admin.execute(SqlCommand('DROP SCHEMA IF EXISTS $schema CASCADE'));
      await admin.execute(SqlCommand('CREATE SCHEMA $schema'));
      final connection = [
        '--postgres-env',
        'ORM_TEST_POSTGRES',
        '--tls',
        'disable',
        '--database-schema',
        schema,
      ];
      try {
        final migrations = p.join(directory.path, 'migrations');
        final snapshot = await writeSnapshot(
          'schema',
          SchemaSnapshot(appSchema),
        );
        await cli([
          'migration',
          'create',
          '0001_initial',
          '--schema',
          snapshot,
          '--dir',
          migrations,
        ]);
        expect(
          (await cli([
            'migration',
            'check',
            '--dir',
            migrations,
            '--dialect',
            'postgres',
          ]))['valid'],
          true,
        );
        final pending = await cli([
          'migrate',
          'plan',
          '--dir',
          migrations,
          ...connection,
        ]);
        expect((pending['pending'] as List).length, 1);
        expect(
          (await cli(['migrate', 'status', ...connection]))['applied'],
          isEmpty,
        );
        expect(
          (await cli([
            'migrate',
            'apply',
            '--dir',
            migrations,
            ...connection,
          ]))['applied'],
          ['0001_initial'],
        );
        expect(
          (await cli([
            'db',
            'verify',
            '--schema',
            snapshot,
            ...connection,
          ]))['matches'],
          true,
        );
        final first = Migration.fromJson(
          jsonDecode(
            await File(p.join(migrations, '0001_initial.json')).readAsString(),
          ) as Map<String, Object?>,
        );
        final concurrent = Migration.steps('0002_index', {
          SqlDialect.postgres: [
            CheckedSql.createIndex(
              'users',
              const IndexSchema('nickname_lookup', ['nickname']),
            ),
          ],
        }, previous: first.checksum);
        await File(p.join(migrations, '0002_index.json'))
            .writeAsString(jsonEncode(concurrent.toJson()));
        expect(
          (await cli([
            'migrate',
            'plan',
            '--dir',
            migrations,
            ...connection,
          ]))['atomic'],
          false,
        );
        expect(
          (await cli([
            'migrate',
            'apply',
            '--dir',
            migrations,
            ...connection,
          ]))['applied'],
          ['0002_index'],
        );
        final status = await cli(['migrate', 'status', ...connection]);
        expect(
          ((status['progress'] as List).single as Map)['state'],
          'complete',
        );
      } finally {
        await admin.execute(SqlCommand('DROP SCHEMA $schema CASCADE'));
        await admin.close();
      }
    }, timeout: const Timeout(Duration(minutes: 1)));
  }
}
