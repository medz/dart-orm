import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

void main() {
  test(
    'SQLite and transaction controls reject recoverable autocommit steps',
    () async {
      final db = await sqlite(const SqliteOptions.memory());
      try {
        final migration = Migration.steps('0001_invalid', {
          SqlDialect.sqlite: [
            const CheckedSql(
              'VACUUM',
              readyWhen: 'SELECT true',
              doneWhen: 'SELECT true',
            ),
          ],
        });
        await expectLater(
          Migrator(db).apply([migration]),
          throwsA(isA<OrmException>()),
        );
        expect(await Migrator(db).history(), isEmpty);
        expect(
          () => validateMigrations([
            Migration.steps('0001_control', {
              SqlDialect.postgres: [
                const CheckedSql(
                  'COMMIT',
                  readyWhen: 'SELECT true',
                  doneWhen: 'SELECT true',
                ),
              ],
            }),
          ], dialect: SqlDialect.postgres),
          throwsA(isA<OrmException>()),
        );
      } finally {
        await db.close();
      }
    },
  );
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url == null) return;
  const schema = 'orm_recovery_tests';
  late Database<Postgres> admin, db;
  final initial = Migration('0001_initial', {
    SqlDialect.postgres: [
      'CREATE TABLE payload (id BIGINT PRIMARY KEY, value TEXT NOT NULL, touches BIGINT NOT NULL DEFAULT 0)',
      "INSERT INTO payload (id, value) VALUES (1, 'one'), (2, 'two')",
    ],
  });
  final index = CheckedSql.createIndex(
    'payload',
    const IndexSchema('value_lookup', ['value'], unique: true),
  );
  Migration build(List<MigrationStep> steps) => Migration.steps('0002_index', {
    SqlDialect.postgres: steps,
  }, previous: initial.checksum);
  setUpAll(() async {
    admin = postgres(PostgresOptions(url: Uri.parse(url), tls: .disable));
    await admin.execute(SqlCommand('CREATE SCHEMA IF NOT EXISTS $schema'));
  });
  tearDownAll(() async {
    await admin.execute(SqlCommand('DROP SCHEMA $schema CASCADE'));
    await admin.close();
  });
  setUp(() async {
    db = postgres(
      PostgresOptions(url: Uri.parse(url), tls: .disable, schema: schema),
    );
    for (final table in [
      'payload',
      'repair_target',
      '_orm_migration_steps',
      '_orm_migrations',
    ]) {
      await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
    }
    await Migrator(db).apply([initial]);
  });
  tearDown(() => db.close());

  test(
    'mixed migrations checkpoint SQL and verify concurrent indexes',
    () async {
      expect(
        (await db.execute(SqlCommand(index.doneWhen))).rows.single.single,
        false,
      );
      final migration = build([
        ExecuteSql("UPDATE payload SET value = 'updated' WHERE id = 1"),
        index,
        ExecuteSql('UPDATE payload SET touches = touches + 1'),
      ]);
      final restored = Migration.fromJson(
        jsonDecode(jsonEncode(migration.toJson())) as Map<String, Object?>,
      );
      expect(restored.checksum, migration.checksum);
      expect(await Migrator(db).apply([initial, restored]), [migration.id]);
      expect(
        (await db.execute(SqlCommand(index.doneWhen))).rows.single.single,
        true,
      );
      expect(
        (await Migrator(db).progress()).map((p) => p.state),
        everyElement(MigrationStepState.complete),
      );
      expect(await Migrator(db).apply([initial, restored]), isEmpty);
      expect(
        (await db.execute(SqlCommand('SELECT touches FROM payload'))).rows
            .map((r) => r.single),
        [1, 1],
      );
    },
  );

  test(
    'same-name wrong-definition indexes are never accepted as completion',
    () async {
      await db.execute(SqlCommand('CREATE INDEX value_lookup ON payload(id)'));
      final migration = build([index]);
      await expectLater(
        Migrator(db).apply([initial, migration]),
        throwsA(
          isA<OrmException>().having((e) => e.code, 'code', 'MIGRATION.STEP'),
        ),
      );
      final progress = (await Migrator(db).progress()).single;
      expect(progress.state, MigrationStepState.failed);
      expect(progress.phase, 'inspect');
      expect(progress.failure, 'MIGRATION.RECOVERY');
      expect((await Migrator(db).history()).length, 1);
    },
  );

  test(
    'failed unique builds leave INVALID indexes and require explicit repair',
    () async {
      await db.execute(SqlCommand("UPDATE payload SET value = 'duplicate'"));
      final migration = build([index]);
      await expectLater(
        Migrator(db).apply([initial, migration]),
        throwsA(isA<OrmException>()),
      );
      final invalid = await db.execute(
        SqlCommand(
          "SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = current_schema() AND c.relname = 'value_lookup'",
        ),
      );
      expect(invalid.rows.single.single, false);
      expect((await Migrator(db).progress()).single.phase, 'execute');
      await expectLater(
        Migrator(db).apply([initial, migration]),
        throwsA(isA<OrmException>()),
      );
      expect(
        (await Migrator(db).progress()).single.failure,
        'MIGRATION.RECOVERY',
      );
      await db.execute(SqlCommand('DROP INDEX CONCURRENTLY value_lookup'));
      await db.execute(
        SqlCommand("UPDATE payload SET value = 'repaired' WHERE id = 2"),
      );
      await Migrator(db).apply([initial, migration]);
      expect(
        (await db.execute(SqlCommand(index.doneWhen))).rows.single.single,
        true,
      );
    },
  );

  test(
    'failed attempts freeze migration checksums and block baseline',
    () async {
      final migration = build([
        const CheckedSql(
          'SELECT 1',
          readyWhen: 'SELECT false',
          doneWhen: 'SELECT false',
        ),
      ]);
      await expectLater(
        Migrator(db).apply([initial, migration]),
        throwsA(isA<OrmException>()),
      );
      await expectLater(
        Migrator(db).plan([
          initial,
          build([index]),
        ]),
        throwsA(
          isA<OrmException>().having(
            (e) => e.code,
            'code',
            'MIGRATION.CHECKSUM',
          ),
        ),
      );
      await expectLater(
        Migrator(db).plan([initial]),
        throwsA(
          isA<OrmException>().having(
            (e) => e.code,
            'code',
            'MIGRATION.CHECKSUM',
          ),
        ),
      );
      // Even an empty applied history cannot hide an attempted migration.
      await db.execute(SqlCommand('DELETE FROM "_orm_migrations"'));
      final snapshot = SchemaSnapshot([]);
      final baseline = Migration.create('0001_baseline', snapshot.tables);
      await expectLater(
        Migrator(db).baseline([baseline], expected: snapshot),
        throwsA(
          isA<OrmException>().having(
            (e) => e.code,
            'code',
            'MIGRATION.BASELINE',
          ),
        ),
      );
    },
  );

  test('failed postconditions report their actual failing stage', () async {
    final migration = build([
      const CheckedSql(
        'SELECT 1',
        readyWhen: 'SELECT true',
        doneWhen: 'SELECT false',
      ),
    ]);
    await expectLater(
      Migrator(db).apply([initial, migration]),
      throwsA(isA<OrmException>()),
    );
    expect(
      (await Migrator(db).progress()).single.failure,
      'MIGRATION.POSTCONDITION',
    );
    expect((await Migrator(db).progress()).single.phase, 'verify');
  });

  test('recovery probes must produce one boolean value', () async {
    final migration = build([
      const CheckedSql(
        'SELECT 1',
        readyWhen: 'SELECT true',
        doneWhen: 'SELECT 1',
      ),
    ]);
    await expectLater(
      Migrator(db).apply([initial, migration]),
      throwsA(isA<OrmException>()),
    );
    expect((await Migrator(db).progress()).single.failure, 'MIGRATION.PROBE');
    expect((await Migrator(db).progress()).single.phase, 'inspect');
  });

  test(
    'concurrent runners serialize normal and autocommit steps under one lock',
    () async {
      final migration = build([
        ExecuteSql('UPDATE payload SET touches = touches + 1'),
        index,
      ]);
      final results = await Future.wait([
        Migrator(db).apply([initial, migration]),
        Migrator(db).apply([initial, migration]),
      ]);
      expect(results.expand((r) => r), [migration.id]);
      expect(
        (await db.execute(SqlCommand('SELECT touches FROM payload'))).rows
            .map((r) => r.single),
        [1, 1],
      );
    },
  );

  test(
    'runner lock timeout leaves history untouched and the connection reusable',
    () async {
      final blocker = postgres(
        PostgresOptions(url: Uri.parse(url), tls: .disable, schema: schema),
      );
      try {
        await blocker.session((held) async {
          await held.execute(
            SqlCommand(
              'SELECT pg_advisory_lock(182983479, hashtext(current_schema()))',
            ),
          );
          try {
            final migrator = Migrator(
              db,
              lockTimeout: const Duration(milliseconds: 25),
            );
            await expectLater(
              migrator.apply([
                initial,
                build([index]),
              ]),
              throwsA(
                isA<OrmException>().having(
                  (e) => e.code,
                  'code',
                  'MIGRATION.LOCK_TIMEOUT',
                ),
              ),
            );
            expect((await migrator.history()).length, 1);
            expect(await migrator.progress(), isEmpty);
            expect(
              (await db.execute(SqlCommand('SELECT 1'))).rows.single.single,
              1,
            );
          } finally {
            await held.execute(
              SqlCommand(
                'SELECT pg_advisory_unlock(182983479, hashtext(current_schema()))',
              ),
            );
          }
        });
        await Migrator(db).apply([
          initial,
          build([index]),
        ]);
      } finally {
        await blocker.close();
      }
    },
  );

  test('ordinary SQL inside a mixed migration rolls back only its failed step and resumes', () async {
    final migration = build([
      ExecuteSql('UPDATE payload SET touches = touches + 1'),
      ExecuteSql('INSERT INTO repair_target VALUES (1)'),
      index,
    ]);
    await expectLater(
      Migrator(db).apply([initial, migration]),
      throwsA(isA<OrmException>()),
    );
    expect((await Migrator(db).progress()).map((p) => p.state), [
      MigrationStepState.complete,
      MigrationStepState.failed,
    ]);
    await db.execute(
      SqlCommand('CREATE TABLE repair_target (id BIGINT PRIMARY KEY)'),
    );
    await Migrator(db).apply([initial, migration]);
    expect(
      (await db.execute(SqlCommand('SELECT touches FROM payload'))).rows
          .map((r) => r.single),
      [1, 1],
    );
    expect(
      (await db.execute(SqlCommand('SELECT COUNT(*) FROM repair_target')))
          .rows
          .single
          .single,
      1,
    );
  });

  test(
    'completion checks reject partial and NULLS NOT DISTINCT definitions',
    () async {
      for (final suffix in ['WHERE id > 0', 'NULLS NOT DISTINCT']) {
        await db.execute(
          SqlCommand(
            'CREATE UNIQUE INDEX value_lookup ON payload(value) $suffix',
          ),
        );
        expect(
          (await db.execute(SqlCommand(index.doneWhen))).rows.single.single,
          false,
        );
        await db.execute(SqlCommand('DROP INDEX value_lookup'));
      }
    },
  );

  for (final crashAtCommit in [false, true]) {
    test(
      'real process exit after ${crashAtCommit ? 'transaction commit' : 'concurrent DDL'} resumes without replay',
      () async {
        const update = 'UPDATE payload SET touches = touches + 1';
        final migration = build(
          crashAtCommit
              ? [ExecuteSql(update), index]
              : [index, ExecuteSql(update)],
        );
        final directory = await Directory.systemTemp.createTemp(
          'orm-recovery-',
        );
        try {
          final file = File('${directory.path}/migrations.json');
          await file.writeAsString(
            jsonEncode([initial.toJson(), migration.toJson()]),
          );
          final process = await Process.run(Platform.resolvedExecutable, [
            'run',
            'test/support/migration_crash.dart',
            file.path,
            schema,
            crashAtCommit ? update : index.sql,
            crashAtCommit ? 'commit' : 'statement',
          ]);
          expect(
            process.exitCode,
            91,
            reason: '${process.stdout}\n${process.stderr}',
          );
          expect((await Migrator(db).history()).length, 1);
          final progress = await Migrator(db).progress();
          expect(
            progress.single.state,
            crashAtCommit
                ? MigrationStepState.complete
                : MigrationStepState.running,
          );
          if (!crashAtCommit) {
            expect(
              (await db.execute(SqlCommand(index.doneWhen))).rows.single.single,
              true,
            );
          }
          await Migrator(db).apply([initial, migration]);
          expect(
            (await db.execute(SqlCommand('SELECT touches FROM payload'))).rows
                .map((r) => r.single),
            [1, 1],
          );
          expect((await Migrator(db).history()).length, 2);
        } finally {
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
