import 'dart:io';
import 'dart:typed_data';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('backfill keys $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_backfill_key_tests',
            ),
          );
          await db.execute(
            SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_backfill_key_tests'),
          );
        }
        for (final table in [
          'keys',
          '_orm_migrations',
          '_orm_migration_steps',
        ]) {
          await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
        }
      });
      tearDown(() => db.close());
      for (final sample in <String, (Codec<Object?>, List<Object?>)>{
        'integer': (Codecs.integer, [-9007199254740993, 0, 9007199254740993]),
        'bigint': (
          Codecs.bigint,
          [
            '-900719925474099399999',
            '22222222222222222222222',
            '100000000000000000000000',
          ],
        ),
        'text': (Codecs.text, ['', r"a' $1 ?2", '数据 😀']),
        'real': (Codecs.real, [-1.125, 0.0, 1.23456789012345]),
        'boolean': (Codecs.boolean, [false, true]),
        'timestamp': (
          Codecs.dateTime,
          [
            DateTime.utc(2026, 1, 1, 0, 0, 0, 0, 1),
            DateTime.utc(2026, 1, 1, 0, 0, 0, 0, 2),
          ],
        ),
        'blob': (
          Codecs.bytes,
          [
            Uint8List.fromList([0]),
            Uint8List.fromList([0, 255]),
            Uint8List.fromList([255, 0]),
          ],
        ),
      }.entries) {
        test('${sample.key} cursors preserve native values across resume', () async {
          final table = TableSchema(
            'keys',
            columns: [
              Column('key', sample.value.$1),
              Column('touches', Codecs.integer, defaultSql: '0'),
            ],
            primaryKey: ['key'],
          );
          final initial = Migration.create('0001_keys', [table]);
          final runner = Migrator(db);
          await runner.apply([initial]);
          for (final key in sample.value.$2) {
            final stored = switch ((backend, key)) {
              ('sqlite', DateTime date) => date.toUtc().toIso8601String(),
              ('sqlite', bool value) => value ? 1 : 0,
              _ => key,
            };
            await db.execute(
              SqlCommand(
                'INSERT INTO "keys" ("key") VALUES (${backend == 'sqlite' ? '?1' : r'$1'})',
                [stored],
              ),
            );
          }
          final migration = Migration.steps('0002_backfill', {
            db.dialect: [
              Backfill(
                table,
                set: {'touches': 'touches + 1'},
                doneWhen: 'SELECT NOT EXISTS(SELECT 1 FROM "keys" WHERE touches <> 1)',
                batchSize: 1,
              ),
            ],
          }, previous: initial.checksum);
          await runner.apply([initial, migration], maxBackfillBatches: 1);
          final cursor = (await runner.progress()).single.backfill!;
          expect(cursor.lastKey, hasLength(1));
          expect(cursor.rows, 1);
          await runner.apply([initial, migration]);
          final rows = await db.execute(
            SqlCommand('SELECT touches FROM "keys"'),
          );
          expect(rows.rows.map((r) => r.single), everyElement(1));
          expect(
            (await runner.progress()).single.backfill!.rows,
            sample.value.$2.length,
          );
        });
      }
      test('composite key batches account for every bound parameter', () async {
        final commands = <SqlCommand>[];
        final limited = Database(_Limited(db.driver, commands));
        final table = TableSchema(
          'keys',
          columns: [
            Column('tenant', Codecs.text),
            Column('id', Codecs.integer),
            Column('touches', Codecs.integer, defaultSql: '0'),
          ],
          primaryKey: ['tenant', 'id'],
        );
        final initial = Migration.create('0001_keys', [table]);
        final runner = Migrator(limited);
        await runner.apply([initial]);
        for (var i = 0; i < 20; i++) {
          await limited.execute(
            SqlCommand(
              'INSERT INTO "keys" (tenant, id) VALUES (${backend == 'sqlite' ? '?1, ?2' : r'$1, $2'})',
              ['tenant${i ~/ 10}', i],
            ),
          );
        }
        final migration = Migration.steps('0002_backfill', {
          db.dialect: [
            Backfill(
              table,
              set: {'touches': 'touches + 1'},
              doneWhen:
                  'SELECT NOT EXISTS(SELECT 1 FROM "keys" WHERE touches <> 1)',
              batchSize: 1000,
            ),
          ],
        }, previous: initial.checksum);
        await runner.apply([initial, migration], maxBackfillBatches: 2);
        expect((await runner.progress()).single.backfill!.rows, 12);
        expect((await runner.progress()).single.backfill!.lastKey, [
          'tenant1',
          '11',
        ]);
        await runner.apply([initial, migration]);
        expect((await runner.progress()).single.backfill!.batches, 4);
        expect(commands.every((c) => c.parameters.length <= 12), true);
        final data = await limited.execute(
          SqlCommand('SELECT touches FROM "keys"'),
        );
        expect(data.rows.map((r) => r.single), everyElement(1));
      });
    });
  }
  test('invalid key, assignments and completion declarations fail before execution', () {
    TableSchema schema(
      Codec<Object?> codec, {
      bool nullable = false,
      bool primary = true,
    }) => TableSchema(
      'keys',
      columns: [
        Column('key', codec, nullable: nullable),
        Column('value', Codecs.text),
      ],
      primaryKey: primary ? ['key'] : [],
    );
    for (final table in [
      schema(Codecs.integer, primary: false),
      schema(Codecs.text.nullable(), nullable: true),
      schema(Codecs.json),
    ]) {
      expect(
        () =>
            Backfill(table, set: {'value': "'done'"}, doneWhen: 'SELECT TRUE'),
        throwsA(isA<OrmException>()),
      );
    }
    final table = schema(Codecs.integer);
    for (final set in [
      <String, String>{},
      {'key': 'key + 1'},
      {'unknown': 'value'},
      {'value': ''},
    ]) {
      expect(
        () => Backfill(table, set: set, doneWhen: 'SELECT TRUE'),
        throwsArgumentError,
      );
    }
    expect(
      () => Backfill(
        table,
        set: {'value': "'done'"},
        doneWhen: 'DELETE FROM keys',
      ),
      throwsA(isA<OrmException>()),
    );
    expect(
      () => Backfill(
        table,
        set: {'value': "'done'"},
        doneWhen: 'SELECT TRUE',
        batchSize: 0,
      ),
      throwsArgumentError,
    );
  });
}

final class _Limited(
  final Driver<Backend> source,
  final List<SqlCommand> commands,
) implements Driver<Backend> {
  @override
  Capabilities get capabilities => Capabilities(
    dialect: source.capabilities.dialect,
    maxParameters: 12,
    cancellation: source.capabilities.cancellation,
  );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      source.run((c) => action(_Counting(c, commands)));
  @override
  Future<void> close() => source.close();
}

final class _Counting(
  final SqlConnection source,
  final List<SqlCommand> commands,
) implements SqlConnection {
  @override
  bool? get transactionActive => source.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    commands.add(command);
    return source.execute(command, options: options);
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => source.openCursor(command, options: options);
  @override
  Future<void> invalidate() => source.invalidate();
}
