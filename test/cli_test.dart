import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/src/cli/migration.dart';
import 'package:test/test.dart';

import '../example/schema.orm.dart';
import 'support/cli.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('orm-cli-');
  });
  tearDown(() => directory.delete(recursive: true));

  String databasePath() => '${directory.path}/database.sqlite';
  Future<SqlDatabase<Backend>> connect({required bool readOnly}) async =>
      (await sqlite(
        readOnly
            ? SqliteOptions.readOnly(databasePath())
            : SqliteOptions.file(databasePath()),
      )).sql;

  Future<Map<String, Object?>> migrate(
    List<String> args, {
    required List<Migration> history,
    required SchemaSnapshot schema,
    SqlDialect dialect = SqlDialect.sqlite,
    MigrationConnection? connection,
    int code = 0,
  }) async {
    final result = await captureCli(
      () => runMigrationCommand(
        args,
        history: MigrationHistory([
          for (final m in history) (m, m.checksum),
        ], dialect: dialect),
        directory: directory.path,
        schema: schema,
        connect: connection ?? connect,
      ),
    );
    expect(result.exitCode, code, reason: '${result.stdout}\n${result.stderr}');
    return code == 0 || code == 2 ? cliReport(result) : {};
  }

  test('migration commands upgrade and verify constraints without overwriting history', () async {
    final initial = SchemaSnapshot(appSchema);
    final first = Migration.create(
      '0001_initial',
      initial.tables,
      dialect: .sqlite,
    );
    final created = await migrate(
      ['create', first.id],
      history: [],
      schema: initial,
    );
    expect(created['checksum'], first.checksum);
    final file = File(created['created'] as String);
    final saved = await file.readAsString();
    expect(
      (await migrate(['check'], history: [first], schema: initial))['valid'],
      true,
    );
    await migrate(['plan'], history: [first], schema: initial, code: 1);
    expect(await File(databasePath()).exists(), false);
    expect(
      (await migrate(['apply'], history: [first], schema: initial))['applied'],
      [first.id],
    );

    final next = SchemaSnapshot([
      TableSchema(
        'users',
        columns: [
          ...userSchema.columns,
          Column('status', Codecs.text, defaultSql: "'active'"),
          Column(
            'email_size',
            Codecs.integer,
            computed: const ComputedColumn('length(email)'),
          ),
        ],
        primaryKey: userSchema.primaryKey,
        uniqueKeys: userSchema.uniqueKeys,
        checks: const [
          CheckSchema('valid_status', "status IN ('active', 'disabled')"),
        ],
      ),
      postSchema,
    ]);
    final second = Migration.diff(
      '0002_status',
      dialect: .sqlite,
      from: initial,
      to: next,
      previous: first.checksum,
    );
    expect(
      (await migrate(
        ['create', second.id],
        history: [first],
        schema: next,
      ))['checksum'],
      second.checksum,
    );
    final history = [first, second];
    expect(
      (await migrate(['plan'], history: history, schema: next))['pending'],
      hasLength(1),
    );
    expect(
      (await migrate(['status'], history: history, schema: next))['applied'],
      hasLength(1),
    );
    await migrate(['apply'], history: history, schema: next);
    final inspected = await runCli([
      '--json',
      'db',
      'inspect',
      '--sqlite',
      databasePath(),
      '--table',
      'users',
    ]);
    expect(inspected.exitCode, 0, reason: inspected.stderr);
    final catalog = cliReport(inspected);
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
    expect(
      (await migrate(['verify'], history: history, schema: next))['matches'],
      true,
    );
    expect(
      (await migrate(
        ['verify'],
        history: history,
        schema: initial,
        code: 2,
      ))['matches'],
      false,
    );
    expect(
      (await migrate(
        ['create', '0003_same'],
        history: history,
        schema: next,
      ))['created'],
      null,
    );
    expect(await File('${directory.path}/m0003_same.dart').exists(), false);
    await migrate(
      ['create', first.id, '--allow-destructive'],
      history: history,
      schema: initial,
      code: 1,
    );
    expect(await file.readAsString(), saved);
  });

  test(
    'baseline retains existing rows and read-only connections reject writes',
    () async {
      final schema = SchemaSnapshot(appSchema);
      final initial = Migration.create(
        '0001_baseline',
        schema.tables,
        dialect: .sqlite,
      );
      final db = await sqlite(SqliteOptions.file(databasePath()));
      try {
        for (final sql in createSchema(appSchema, .sqlite)) {
          await db.execute(sql);
        }
        await db.user.create(email: 'existing');
      } finally {
        await db.close();
      }
      expect(
        (await migrate(
          ['baseline'],
          history: [initial],
          schema: schema,
        ))['matches'],
        true,
      );
      final read = await sqlite(SqliteOptions.readOnly(databasePath()));
      try {
        expect((await read.user.single()).email, 'existing');
        expect(await Migrator(read.sql).history(), hasLength(1));
        await expectLater(
          read.user.create(email: 'forbidden'),
          throwsA(isA<SqliteFailure>()),
        );
      } finally {
        await read.close();
      }
    },
  );

  for (final dialect in SqlDialect.values) {
    test(
      '${dialect.name} offline migration commands never open a connection',
      () async {
        final schema = SchemaSnapshot(appSchema);
        final migration = Migration.create(
          '0001_initial',
          schema.tables,
          dialect: dialect,
        );
        Future<SqlDatabase<Backend>> offline({required bool readOnly}) =>
            throw StateError('Offline command opened a connection');
        final created = await migrate(
          ['create', migration.id],
          history: [],
          schema: schema,
          dialect: dialect,
          connection: offline,
        );
        expect(created['checksum'], matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(
          await File(created['created'] as String).readAsString(),
          contains('dialect: SqlDialect.${dialect.name}'),
        );
        final checked = await migrate(
          ['check'],
          history: [migration],
          schema: schema,
          dialect: dialect,
          connection: offline,
        );
        expect(checked['dialect'], dialect.name);
        expect(checked['migrations'], [migration.id]);
        for (final args in [
          ['verify', '--tls', 'disable'],
          ['check', '--unknown', 'x'],
          ['apply', '--max-backfill-batches', '0'],
        ]) {
          await migrate(
            args,
            history: [migration],
            schema: schema,
            dialect: dialect,
            connection: offline,
            code: 64,
          );
        }
      },
    );
  }

  if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) {
    test('PostgreSQL commands support checked nontransactional recovery operations', () async {
      final name = 'orm_cli_${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final options = PostgresOptions(
        url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
        tls: .disable,
        schema: name,
        maxConnections: 1,
      );
      final admin = postgres(options);
      var created = false;
      try {
        await admin.execute(SqlCommand('CREATE SCHEMA "$name"'));
        created = true;
        final schema = SchemaSnapshot(appSchema);
        final first = Migration.create(
          '0001_initial',
          schema.tables,
          dialect: .postgres,
        );
        Future<Map<String, Object?>> command(
          List<String> args,
          List<Migration> history,
        ) => migrate(
          args,
          history: history,
          schema: schema,
          dialect: .postgres,
          connection: ({required readOnly}) => postgres(options).sql,
        );
        expect((await command(['plan'], [first]))['pending'], hasLength(1));
        expect((await command(['status'], [first]))['applied'], isEmpty);
        expect((await command(['apply'], [first]))['applied'], [first.id]);
        expect((await command(['verify'], [first]))['matches'], true);
        final second = Migration.steps(
          '0002_index',
          [
            CheckedSql.createIndex(
              'users',
              const IndexSchema('nickname_lookup', ['nickname']),
            ),
          ],
          previous: first.checksum,
          dialect: .postgres,
        );
        expect((await command(['plan'], [first, second]))['atomic'], false);
        expect((await command(['apply'], [first, second]))['applied'], [
          second.id,
        ]);
        final progress =
            (await command(['status'], [first, second]))['progress'] as List;
        expect((progress.single as Map)['state'], 'complete');
      } finally {
        if (created) {
          await admin.execute(SqlCommand('DROP SCHEMA "$name" CASCADE'));
        }
        await admin.close();
      }
    });
  }
}
