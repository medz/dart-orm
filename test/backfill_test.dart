import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/backfill.dart';
import 'support/backfill_history/migrations.g.dart' as historical;
import 'support/migration_project.dart';

Matcher code(String value) =>
    isA<OrmException>().having((e) => e.code, 'code', value);
void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('backfill $backend', () {
      late Directory directory;
      late Database<Backend> db;
      late Migrator runner;
      late String path;
      final commands = <SqlCommand>[];
      Future<Database<Backend>> open() async {
        if (backend == 'sqlite') return sqlite(SqliteOptions.file(path));
        final result = postgres(
          PostgresOptions(
            url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
            tls: .disable,
            schema: 'orm_backfill_tests',
            maxConnections: 1,
          ),
        );
        await result.execute(
          SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_backfill_tests'),
        );
        return result;
      }

      setUp(() async {
        directory = await Directory.systemTemp.createTemp('orm-backfill-');
        path = '${directory.path}/db.sqlite';
        final base = await open();
        db = Database(_Driver(base.driver, commands));
        runner = Migrator(db);
        for (final table in [
          'children',
          'payload',
          'keys',
          'audit',
          'flags',
          '_orm_migration_steps',
          '_orm_migrations',
        ]) {
          await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
        }
        commands.clear();
      });
      tearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });
      Future<List<List<Object?>>> data() async => (await db.execute(
        SqlCommand('SELECT id, value, touches FROM payload ORDER BY id'),
      )).rows;
      Future<BackfillProgress> progress() async =>
          (await runner.progress()).single.backfill!;

      test(
        'chunks pause and resume from a checksummed historical declaration',
        () async {
          await seed(db);
          final migration = historical.migrationHistory.checked.last;
          expect(migration.checksum, fill().checksum);
          expect(
            await runner.apply([initial, migration], maxBackfillBatches: 2),
            isEmpty,
          );
          final saved = await progress();
          expect(
            [saved.rows, saved.batches, saved.lastKey, saved.upperKey],
            [
              6,
              2,
              ['6'],
              ['8'],
            ],
          );
          expect((await data()).where((r) => r[2] == 1).length, 6);
          await expectLater(
            runner.requireVersion([initial, migration], maximum: initial.id),
            throwsA(code('MIGRATION.INCOMPLETE')),
          );
          await expectLater(
            runner.apply([initial, fill(batchSize: 2)]),
            throwsA(code('MIGRATION.CHECKSUM')),
          );
          expect(await runner.apply([initial, migration]), [migration.id]);
          expect(
            (await data()).every((r) => r[1] == 'V${r[0]}' && r[2] == 1),
            true,
          );
          expect((await progress()).rows, 8);
          expect(
            (await runner.requireVersion([initial, migration])).id,
            migration.id,
          );
          expect(await runner.apply([initial, migration]), isEmpty);
          expect(commands.any((c) => c.sql.contains('OFFSET')), false);
        },
      );

      test('failed chunk rolls back both writes and cursor, then resumes after repair', () async {
        await seed(db);
        await db.execute(
          SqlCommand('UPDATE payload SET source = NULL WHERE id = 7'),
        );
        final migration = fill(
          set: {
            'value': 'upper(source)',
            'touches':
                'CASE WHEN source IS NULL THEN NULL ELSE touches + 1 END',
          },
        );
        await expectLater(
          runner.apply([initial, migration]),
          throwsA(code('MIGRATION.STEP')),
        );
        expect((await progress()).lastKey, ['6']);
        expect((await data()).where((r) => r[2] == 1).length, 6);
        expect((await runner.progress()).single.phase, 'update');
        await db.execute(
          SqlCommand("UPDATE payload SET source = 'v7' WHERE id = 7"),
        );
        await runner.apply([initial, migration]);
        expect((await data()).every((r) => r[2] == 1), true);
      });

      test(
        'failed completion proof preserves finished chunks without replay',
        () async {
          await seed(db);
          await db.execute(
            SqlCommand('CREATE TABLE flags (ready INTEGER NOT NULL)'),
          );
          await db.execute(SqlCommand('INSERT INTO flags VALUES (0)'));
          final migration = fill(doneWhen: 'SELECT ready = 1 FROM flags');
          await expectLater(
            runner.apply([initial, migration]),
            throwsA(code('MIGRATION.STEP')),
          );
          expect((await progress()).rows, 8);
          expect((await runner.progress()).single.phase, 'verify');
          await db.execute(SqlCommand('UPDATE flags SET ready = 1'));
          commands.clear();
          await runner.apply([initial, migration]);
          expect(
            commands.where((c) => c.sql.startsWith('UPDATE "payload"')),
            isEmpty,
          );
          expect((await data()).every((r) => r[2] == 1), true);
        },
      );

      test('frozen upper bound and completion proof detect incompatible new writes', () async {
        await seed(db);
        final migration = fill();
        await runner.apply([initial, migration], maxBackfillBatches: 1);
        await db.execute(
          SqlCommand(
            "INSERT INTO payload(id, source, value, touches) VALUES (99, 'new', 'NEW', 1), (0, 'late', NULL, 0)",
          ),
        );
        await expectLater(
          runner.apply([initial, migration]),
          throwsA(code('MIGRATION.STEP')),
        );
        expect((await progress()).upperKey, ['8']);
        expect((await progress()).rows, 8);
        await db.execute(
          SqlCommand(
            "UPDATE payload SET value = 'LATE', touches = 1 WHERE id = 0",
          ),
        );
        await runner.apply([initial, migration]);
        expect((await data()).every((r) => r[2] == 1), true);
      });

      test(
        'competing runners share committed chunks without duplicate updates',
        () async {
          await seed(db, count: 35);
          final other = await open();
          final migration = fill(batchSize: 2);
          try {
            final results = await Future.wait([
              runner.apply([initial, migration]),
              Migrator(other).apply([initial, migration]),
            ]);
            expect(results.expand((r) => r).toList(), [migration.id]);
            expect((await progress()).rows, 35);
            expect((await data()).every((r) => r[2] == 1), true);
          } finally {
            await other.close();
          }
        },
      );

      test(
        'lost chunk commit acknowledgement preserves the committed frontier',
        () async {
          await seed(db);
          var wrote = false, failed = false;
          final driver = db.driver as _Driver;
          driver.after = (command) {
            if (command.sql.startsWith('UPDATE "payload" SET')) wrote = true;
            if (wrote && command.sql == 'COMMIT' && !failed) {
              failed = true;
              throw StateError('Lost acknowledgement');
            }
          };
          await expectLater(
            runner.apply([initial, fill()]),
            throwsA(code('MIGRATION.STEP')),
          );
          expect((await progress()).rows, 3);
          await runner.apply([initial, fill()]);
          expect((await data()).every((r) => r[2] == 1), true);
        },
      );

      test('old checkpoint tables upgrade on apply; completed reads remain nonmutating', () async {
        await seed(db);
        await db.execute(
          SqlCommand(
            'CREATE TABLE _orm_migration_steps (migration_id TEXT NOT NULL, checksum TEXT NOT NULL, step INTEGER NOT NULL, state TEXT NOT NULL, phase TEXT NOT NULL, failure TEXT, PRIMARY KEY(migration_id, step))',
          ),
        );
        expect(await runner.progress(), isEmpty);
        expect((await runner.requireVersion([initial])).id, initial.id);
        expect(
          (await inspectColumns(
            db,
            '_orm_migration_steps',
          )).any((c) => c.name == 'backfill'),
          false,
        );
        await runner.apply([initial, fill()]);
        expect((await progress()).rows, 8);
      });

      test(
        'completion conditions reject numeric results instead of truthiness',
        () async {
          await seed(db, count: 0);
          await expectLater(
            runner.apply([initial, fill(doneWhen: 'SELECT 1.0')]),
            throwsA(
              isA<OrmException>().having(
                (e) => e.cause,
                'cause',
                code('MIGRATION.PROBE'),
              ),
            ),
          );
          expect((await runner.history()).length, 1);
        },
      );

      test('empty input still requires the completion condition', () async {
        await seed(db, count: 0);
        await runner.apply([initial, fill()]);
        expect((await progress()).toJson(), {
          'format': 1,
          'upper': null,
          'last': null,
          'rows': 0,
          'batches': 0,
        });
      });

      test('later ordinary migrations retain group atomicity after a completed backfill', () async {
        await seed(db);
        final migration = fill();
        final add = Migration('0003_add', {
          for (final d in SqlDialect.values)
            d: ['CREATE TABLE audit (value INTEGER)'],
        }, previous: migration.checksum);
        final fail = Migration('0004_fail', {
          for (final d in SqlDialect.values)
            d: ['INSERT INTO flags(ready) VALUES(1)'],
        }, previous: add.checksum);
        await expectLater(
          runner.apply([initial, migration, add, fail]),
          throwsA(isA<SqlFailure>()),
        );
        expect((await runner.history()).map((m) => m.id), [
          initial.id,
          migration.id,
        ]);
        expect(await inspectColumns(db, 'audit'), isEmpty);
        expect((await data()).every((r) => r[2] == 1), true);
        await db.execute(SqlCommand('CREATE TABLE flags (ready INTEGER)'));
        expect(await runner.apply([initial, migration, add, fail]), [
          add.id,
          fail.id,
        ]);
      });

      test('AFTER triggers cannot silently move keys past a committed cursor', () async {
        await seed(db);
        if (backend == 'sqlite') {
          await db.execute(
            SqlCommand(
              'CREATE TRIGGER move_keys AFTER UPDATE OF value ON payload BEGIN UPDATE payload SET id = id + 100 WHERE id = NEW.id; END',
            ),
          );
        } else {
          await db.execute(
            SqlCommand(
              r'CREATE OR REPLACE FUNCTION move_key() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN UPDATE payload SET id = id + 100 WHERE id = NEW.id; RETURN NEW; END $$',
            ),
          );
          await db.execute(
            SqlCommand(
              'CREATE TRIGGER move_keys AFTER UPDATE OF value ON payload FOR EACH ROW EXECUTE FUNCTION move_key()',
            ),
          );
        }
        await expectLater(
          runner.apply([initial, fill()]),
          throwsA(code('MIGRATION.STEP')),
        );
        expect(
          (await data()).map((r) => r.first),
          List.generate(8, (i) => i + 1),
        );
        expect((await data()).every((r) => r[2] == 0), true);
        await db.execute(
          SqlCommand(
            'DROP TRIGGER move_keys${backend == 'postgres' ? ' ON payload' : ''}',
          ),
        );
        await runner.apply([initial, fill()]);
        expect((await data()).every((r) => r[2] == 1), true);
      });

      test('corrupt checkpoint dimensions and invalid run limits are rejected', () async {
        await expectLater(
          runner.apply([initial, fill()], maxBackfillBatches: 0),
          throwsArgumentError,
        );
        expect(commands, isEmpty);
        await seed(db);
        await runner.apply([initial, fill()], maxBackfillBatches: 1);
        final bad = jsonEncode({
          'format': 1,
          'upper': ['8'],
          'last': ['3', 'unexpected'],
          'rows': 3,
          'batches': 1,
        });
        await db.execute(
          SqlCommand(
            'UPDATE _orm_migration_steps SET backfill = ${backend == 'sqlite' ? '?1' : r'$1'}',
            [bad],
          ),
        );
        await expectLater(
          runner.apply([initial, fill()]),
          throwsA(code('MIGRATION.HISTORY')),
        );
        expect((await data()).where((r) => r[2] == 1).length, 3);
      });

      if (backend == 'sqlite') {
        test('rebuild, chunked backfill and required-column rebuild preserve FK enforcement', () async {
          await seed(db);
          final expanded = TableSchema(
            'payload',
            columns: [
              ...payload.columns,
              Column('extra', Codecs.integer, defaultSql: '1'),
            ],
            primaryKey: ['id'],
          );
          final required = TableSchema(
            'payload',
            columns: [
              for (final c in expanded.columns)
                c.name == 'value' ? Column('value', Codecs.text) : c,
            ],
            primaryKey: ['id'],
          );
          final migration = Migration.steps(
            '0002_rebuild',
            {
              SqlDialect.sqlite: [
                RebuildTable(
                  payload,
                  expanded,
                  copy: {
                    for (final c in payload.columns) c.name: '"${c.name}"',
                  },
                ),
                Backfill(
                  expanded,
                  set: {'value': 'upper(source)', 'touches': 'touches + 1'},
                  where: 'value IS NULL',
                  doneWhen: 'SELECT NOT EXISTS(SELECT 1 FROM payload WHERE value IS NULL)',
                  batchSize: 3,
                ),
                RebuildTable(
                  expanded,
                  required,
                  copy: {
                    for (final c in expanded.columns) c.name: '"${c.name}"',
                  },
                ),
              ],
            },
            previous: initial.checksum,
            snapshot: SchemaSnapshot([required]),
          );
          await runner.apply([initial, migration], maxBackfillBatches: 1);
          expect(
            (await db.execute(SqlCommand('PRAGMA foreign_keys')))
                .rows
                .single
                .single,
            1,
          );
          expect((await data()).where((r) => r[2] == 1).length, 3);
          await runner.apply([initial, migration]);
          expect((await verifySchema(db, migration.snapshot!)).matches, true);
          expect((await data()).every((r) => r[2] == 1), true);
          expect(
            (await db.execute(SqlCommand('PRAGMA foreign_keys')))
                .rows
                .single
                .single,
            1,
          );
        });
      }

      test(
        'CLI previews non-atomic work and reports a bounded run as incomplete',
        () async {
          await seed(db);
          final project = await MigrationProject.create(
            postgresSchema: backend == 'postgres' ? 'orm_backfill_tests' : null,
            sqlitePath: path,
          );
          addTearDown(project.dispose);
          await project.target(fill().snapshot ?? SchemaSnapshot([payload]));
          for (final m in [initial, fill()]) {
            await project.append(m);
          }
          final plan = await project.run(['plan']);
          expect(plan['atomic'], false);
          final paused = await project.run([
            'apply',
            '--max-backfill-batches',
            '1',
          ]);
          expect(paused, {'applied': <String>[], 'complete': false});
          final status = await project.run(['status']);
          expect(
            (((status['progress'] as List).single as Map)['backfill']
                as Map)['rows'],
            3,
          );
          expect(await project.run(['apply', '--max-backfill-batches', '10']), {
            'applied': ['0002_fill'],
            'complete': true,
          });
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test('temporary tables cannot redirect the historical backfill target', () async {
        await seed(db);
        await db.session((session) async {
          await session.execute(
            SqlCommand(
              'CREATE TEMP TABLE payload(id ${backend == 'postgres' ? 'BIGINT' : 'INTEGER'} PRIMARY KEY NOT NULL, source TEXT, value TEXT, touches ${backend == 'postgres' ? 'BIGINT' : 'INTEGER'} NOT NULL DEFAULT 0)',
            ),
          );
          try {
            await expectLater(
              Migrator(session).apply([initial, fill()]),
              throwsA(code('MIGRATION.STEP')),
            );
          } finally {
            await session.execute(
              SqlCommand(
                'DROP TABLE ${backend == 'postgres' ? 'pg_temp' : 'temp'}.payload',
              ),
            );
          }
        });
        expect((await data()).every((r) => r[2] == 0), true);
        await runner.apply([initial, fill()]);
        expect((await data()).every((r) => r[2] == 1), true);
      });

      test('temporary objects cannot impersonate durable migration metadata', () async {
        await seed(db);
        await db.session((session) async {
          for (final table in ['_orm_migrations', '_orm_migration_steps']) {
            final columns = table == '_orm_migrations'
                ? 'id TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TEXT NOT NULL'
                : 'migration_id TEXT NOT NULL, checksum TEXT NOT NULL, step INTEGER NOT NULL, state TEXT NOT NULL, phase TEXT NOT NULL, failure TEXT, backfill TEXT, PRIMARY KEY(migration_id, step)';
            await session.execute(
              SqlCommand('CREATE TEMP TABLE "$table" ($columns)'),
            );
            try {
              if (table == '_orm_migrations') {
                await session.execute(
                  SqlCommand(
                    'INSERT INTO "$table" SELECT * FROM ${backend == 'postgres' ? 'orm_backfill_tests' : 'main'}."$table"',
                  ),
                );
              }
              await expectLater(
                Migrator(session).apply([initial, fill()]),
                throwsA(code('MIGRATION.SESSION')),
              );
            } finally {
              await session.execute(
                SqlCommand(
                  'DROP TABLE ${backend == 'postgres' ? 'pg_temp' : 'temp'}."$table"',
                ),
              );
            }
          }
        });
        expect((await data()).every((r) => r[2] == 0), true);
        await runner.apply([initial, fill()]);
        expect((await data()).every((r) => r[2] == 1), true);
      });

      if (backend == 'postgres') {
        test('row security cannot hide unfinished rows from the completion proof', () async {
          await seed(db);
          final role = 'orm_backfill_${DateTime.now().microsecondsSinceEpoch}';
          await db.execute(SqlCommand('CREATE ROLE "$role"'));
          try {
            await db.execute(
              SqlCommand(
                'GRANT USAGE, CREATE ON SCHEMA orm_backfill_tests TO "$role"',
              ),
            );
            await db.execute(
              SqlCommand(
                'GRANT ALL ON ALL TABLES IN SCHEMA orm_backfill_tests TO "$role"',
              ),
            );
            await db.execute(
              SqlCommand('ALTER TABLE payload ENABLE ROW LEVEL SECURITY'),
            );
            await db.execute(
              SqlCommand(
                'CREATE POLICY hide ON payload USING (false) WITH CHECK (false)',
              ),
            );
            await db.session((session) async {
              await session.execute(SqlCommand('SET ROLE "$role"'));
              try {
                await expectLater(
                  Migrator(session).apply([initial, fill()]),
                  throwsA(
                    isA<OrmException>().having(
                      (e) => e.cause,
                      'cause',
                      code('MIGRATION.BACKFILL_SCOPE'),
                    ),
                  ),
                );
              } finally {
                await session.execute(SqlCommand('RESET ROLE'));
              }
            });
            expect((await data()).every((r) => r[2] == 0), true);
          } finally {
            await db.execute(SqlCommand('DROP OWNED BY "$role"'));
            await db.execute(SqlCommand('DROP ROLE "$role"'));
          }
        });

        test(
          'inherited duplicate primary keys cannot advance a cursor',
          () async {
            await seed(db);
            await db.execute(
              SqlCommand('CREATE TABLE payload_child () INHERITS (payload)'),
            );
            try {
              await db.execute(
                SqlCommand(
                  "INSERT INTO payload_child(id, source) VALUES (1, 'child')",
                ),
              );
              await expectLater(
                runner.apply([initial, fill()]),
                throwsA(
                  isA<OrmException>().having(
                    (e) => e.cause,
                    'cause',
                    code('MIGRATION.BACKFILL_KEY'),
                  ),
                ),
              );
              expect((await data()).every((r) => r[2] == 0), true);
            } finally {
              await db.execute(SqlCommand('DROP TABLE payload_child'));
            }
          },
        );
      }

      test(
        'committed chunks invalidate relevant typed query subscriptions',
        () async {
          await seed(db);
          final table = Table<int, _PayloadFields>(
            payload,
            _PayloadFields.new,
            (p) => p.touches,
          );
          final watch = StreamIterator(db.table(table).watch());
          try {
            expect(await watch.moveNext(), true);
            expect(watch.current, everyElement(0));
            final changed = watch.moveNext();
            await runner.apply([initial, fill()], maxBackfillBatches: 1);
            expect(await changed.timeout(const Duration(seconds: 2)), true);
            expect(watch.current.where((v) => v == 1).length, 3);
          } finally {
            await watch.cancel();
          }
        },
      );

      for (final boundary in ['write', 'commit']) {
        test(
          'real process exit after second chunk $boundary resumes correctly',
          () async {
            await seed(db);
            final migrations = [initial, fill()];
            final project = await MigrationProject.create();
            addTearDown(project.dispose);
            for (final m in migrations) {
              await project.append(m);
            }
            await project.fixture.write('bin/crash.dart', '''
import '${File('test/support/backfill_crash.dart').absolute.uri}';
import '../lib/migrations/migrations.g.dart';
Future<void> main(List<String> args) => crashBackfill(migrationHistory.checked, args);
''');
            final child = await Process.run(Platform.resolvedExecutable, [
              'run',
              'bin/crash.dart',
              backend,
              backend == 'sqlite' ? path : 'orm_backfill_tests',
              boundary,
            ], workingDirectory: project.path);
            expect(
              child.exitCode,
              91,
              reason: '${child.stdout}\n${child.stderr}',
            );
            expect((await progress()).rows, boundary == 'write' ? 3 : 6);
            expect(
              (await data()).where((r) => r[2] == 1).length,
              boundary == 'write' ? 3 : 6,
            );
            await runner.apply(migrations);
            expect((await data()).every((r) => r[2] == 1), true);
          },
        );
      }
    });
  }
}

final class _PayloadFields extends Fields {
  _PayloadFields(super.table);
  late final Field<int> touches = column(Column('touches', Codecs.integer));
}

final class _Driver(
  final Driver<Backend> source,
  final List<SqlCommand> commands,
) implements Driver<Backend> {
  void Function(SqlCommand)? after;
  @override
  Capabilities get capabilities => source.capabilities;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      source.run((c) => action(_Connection(c, this)));
  @override
  Future<void> close() => source.close();
}

final class _Connection(final SqlConnection source, final _Driver driver)
    implements SqlConnection {
  @override
  bool? get transactionActive => source.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    driver.commands.add(command);
    final result = await source.execute(command, options: options);
    driver.after?.call(command);
    return result;
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => source.openCursor(command, options: options);
  @override
  Future<void> invalidate() => source.invalidate();
}
