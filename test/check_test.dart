import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/checks/schema.orm.dart';

void main() {
  for (final dialect in SqlDialect.values) {
    group(
      'CHECK ${dialect.name}',
      () {
        late Database<Backend> db;
        setUp(() async {
          if (dialect == SqlDialect.sqlite) {
            db = await sqlite(const SqliteOptions.memory());
          } else {
            db = postgres(
              PostgresOptions(
                url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                schema: 'orm_check_tests',
                tls: .disable,
              ),
            );
            await db.execute(
              SqlCommand('DROP SCHEMA IF EXISTS orm_check_tests CASCADE'),
            );
            await db.execute(SqlCommand('CREATE SCHEMA orm_check_tests'));
          }
        });
        tearDown(() => db.close());

        test('generated named and unnamed constraints enforce values and permit NULL', () async {
          await Migrator(db)
              .apply([Migration.create('0001_initial', appSchema)]);
          final row = await db.products.create(price: 10, state: 'draft');
          expect(row.stock, 0);
          expect(row.discount, isNull);
          for (final action in <Future<Object?> Function()>[
            () =>
                db.products.create(stock: .set(-1), price: 10, state: 'draft'),
            () => db.products.create(price: -1, state: 'draft'),
            () => db.products.create(price: 10, discount: 11, state: 'draft'),
            () => db.products.create(price: 10, state: 'unknown'),
            () => db.products.create(
              price: 10,
              state: 'draft',
              label: '; CHECK (0)',
            ),
          ]) {
            await expectLater(action(), throwsA(isA<SqlFailure>()));
          }
          expect(await db.products.count(), 1);
          await expectLater(
            db.products.byId(row.id).patch(discount: .set(-1)),
            throwsA(anything),
          );
          final info = await inspectTable(db, 'products');
          expect(info.checks.length, 6);
          expect(info.unmanaged, isEmpty);
          expect(
            (await verifySchema(db, SchemaSnapshot(appSchema))).differences,
            isEmpty,
          );
        });

        test(
          'import preserves names and SQL then generates a matching snapshot',
          () async {
            await Migrator(db)
                .apply([Migration.create('0001_initial', appSchema)]);
            await db.products.create(price: 10, state: 'draft');
            final directory = await Directory(
              '.dart_tool/orm-check-import-${dialect.name}',
            ).create(recursive: true);
            try {
              final imported = await importSchema(db);
              final source = File('${directory.path}/schema.dart');
              await source.writeAsString(imported.dart);
              final generated = await generateSchema(source.path);
              final result = await verifySchema(db, generated.snapshot);
              expect(result.differences, isEmpty);
              expect(result.unmanaged, isEmpty);
              expect(imported.dart, contains('.check('));
              expect(
                imported.issues.map((i) => i.code),
                contains('IMPORT.CHECK_SQL'),
              );
              await db.execute(SqlCommand('DROP TABLE _orm_migrations'));
              final snapshot = generated.snapshot;
              await Migrator(db).baseline([
                Migration.create('0001_imported', snapshot.tables),
              ], expected: snapshot);
              expect(await db.products.count(), 1);
            } finally {
              await directory.delete(recursive: true);
            }
          },
        );

        TableSchema scores(
          List<CheckSchema> checks, {
          String name = 'scores',
          String value = 'value',
        }) => TableSchema(
          name,
          columns: [Column('id', Codecs.integer), Column(value, Codecs.real)],
          primaryKey: ['id'],
          indexes: [
            IndexSchema('score_value', [value]),
          ],
          checks: checks,
        );

        test(
          'add, change and remove constraints validate old rows atomically',
          () async {
            final start = SchemaSnapshot([scores(const [])]);
            final initial = Migration.create('0001_initial', start.tables);
            await Migrator(db).apply([initial]);
            await db.execute(SqlCommand('INSERT INTO scores VALUES (1, -2)'));
            final positive = SchemaSnapshot([
              scores(const [CheckSchema('positive', 'value >= 0')]),
            ]);
            final add = Migration.diff(
              '0002_check',
              from: start,
              to: positive,
              previous: initial.checksum,
            );
            await expectLater(
              Migrator(db).apply([initial, add]),
              throwsA(anything),
            );
            expect(
              (await db.execute(SqlCommand('SELECT value FROM scores')))
                  .rows
                  .single
                  .single,
              -2,
            );
            expect(
              (await db.execute(
                SqlCommand('SELECT count(*) FROM _orm_migrations'),
              )).rows.single.single,
              1,
            );
            expect((await verifySchema(db, start)).differences, isEmpty);
            await db.execute(SqlCommand('UPDATE scores SET value = 2'));
            await Migrator(db).apply([initial, add]);
            expect((await verifySchema(db, positive)).differences, isEmpty);
            final stricter = SchemaSnapshot([
              scores(const [CheckSchema('positive', 'value >= 3')]),
            ]);
            final change = Migration.diff(
              '0003_check',
              from: positive,
              to: stricter,
              previous: add.checksum,
            );
            await expectLater(
              Migrator(db).apply([initial, add, change]),
              throwsA(anything),
            );
            expect((await verifySchema(db, positive)).differences, isEmpty);
            await db.execute(SqlCommand('UPDATE scores SET value = 3'));
            await Migrator(db).apply([initial, add, change]);
            final remove = Migration.diff(
              '0004_check',
              from: stricter,
              to: start,
              previous: change.checksum,
            );
            await Migrator(db).apply([initial, add, change, remove]);
            await db.execute(SqlCommand('UPDATE scores SET value = -4'));
            expect((await verifySchema(db, start)).differences, isEmpty);
          },
        );

        test(
          'duplicate unnamed checks consume and drop exactly one catalog entry',
          () async {
            final start = SchemaSnapshot([
              scores(const [
                CheckSchema(null, 'value >= 0'),
                CheckSchema(null, 'value >= 0'),
              ]),
            ]);
            final initial = Migration.create('0001_initial', start.tables);
            await Migrator(db).apply([initial]);
            expect((await verifySchema(db, start)).differences, isEmpty);
            final target = SchemaSnapshot([
              scores(const [CheckSchema(null, 'value >= 0')]),
            ]);
            final migration = Migration.diff(
              '0002_remove_copy',
              from: start,
              to: target,
              previous: initial.checksum,
            );
            await Migrator(db).apply([initial, migration]);
            expect((await inspectTable(db, 'scores')).checks, hasLength(1));
            await expectLater(
              db.execute(SqlCommand('INSERT INTO scores VALUES (1, -1)')),
              throwsA(anything),
            );
          },
        );

        test('explicit checked renames preserve rows, incoming references, indexes and views', () async {
          TableSchema notes(String target) => TableSchema(
            'notes',
            columns: [Column('score_id', Codecs.integer)],
            primaryKey: ['score_id'],
            foreignKeys: [
              ForeignKey(['score_id'], target, ['id']),
            ],
          );
          final start = SchemaSnapshot([
            scores(const [CheckSchema('nonnegative', 'value >= 0')]),
            notes('scores'),
          ]);
          final initial = Migration.create('0001_initial', start.tables);
          await Migrator(db).apply([initial]);
          await db.execute(SqlCommand('INSERT INTO scores VALUES (1, 3)'));
          await db.execute(SqlCommand('INSERT INTO notes VALUES (1)'));
          await db.execute(
            SqlCommand(
              'CREATE VIEW score_cards AS SELECT id, value AS original_value FROM scores',
            ),
          );
          if (dialect == SqlDialect.sqlite) {
            await db.execute(SqlCommand('CREATE TABLE audit (value REAL)'));
            await db.execute(
              SqlCommand(
                'CREATE TRIGGER score_audit AFTER UPDATE ON scores BEGIN INSERT INTO audit VALUES (NEW.value); END',
              ),
            );
          }
          final target = SchemaSnapshot([
            scores(
              const [CheckSchema('nonnegative', 'points >= 0')],
              name: 'rankings',
              value: 'points',
            ),
            notes('rankings'),
          ]);
          final migration = Migration.diff(
            '0002_rename',
            from: start,
            to: target,
            previous: initial.checksum,
            renames: const SchemaRenames(
              tables: {'scores': 'rankings'},
              columns: {
                'rankings': {'value': 'points'},
              },
            ),
          );
          if (dialect == SqlDialect.sqlite) {
            expect(
              migration.steps[dialect]!.whereType<RebuildTable>(),
              hasLength(2),
            );
          }
          await Migrator(db).apply([initial, migration]);
          expect((await verifySchema(db, target)).differences, isEmpty);
          expect(
            (await db.execute(
              SqlCommand('SELECT original_value FROM score_cards'),
            )).rows.single.single,
            3,
          );
          expect(
            (await db.execute(SqlCommand('SELECT score_id FROM notes')))
                .rows
                .single
                .single,
            1,
          );
          await db.execute(SqlCommand('UPDATE rankings SET points = 4'));
          if (dialect == SqlDialect.sqlite) {
            expect(
              (await db.execute(SqlCommand('SELECT value FROM audit')))
                  .rows
                  .single
                  .single,
              4,
            );
          }
          await expectLater(
            db.execute(SqlCommand('UPDATE rankings SET points = -1')),
            throwsA(anything),
          );
          await expectLater(
            db.execute(SqlCommand('DELETE FROM rankings')),
            throwsA(anything),
          );
        });

        test('verification preserves casts, precedence, literals and trailing comments', () async {
          final start = SchemaSnapshot([
            scores(const [
              CheckSchema('valid', 'value / 2 > 0 -- trailing comment'),
            ]),
          ]);
          await Migrator(db)
              .apply([Migration.create('0001_initial', start.tables)]);
          expect((await verifySchema(db, start)).differences, isEmpty);
          for (final sql in [
            'value / (2 + 1) > 0',
            'CAST(value AS INTEGER) / 2 > 0',
          ]) {
            final result = await verifySchema(
              db,
              SchemaSnapshot([
                scores([CheckSchema('valid', sql)]),
              ]),
            );
            expect(result.differences, contains('scores checks differs'));
          }
          for (final name in ['value', 'renamed']) {
            final wrongContext = TableSchema(
              'scores',
              columns: [
                Column('id', Codecs.integer),
                Column(name, Codecs.text),
              ],
              primaryKey: ['id'],
              checks: [CheckSchema('valid', 'length($name) > 0')],
            );
            expect(
              (await verifySchema(
                db,
                SchemaSnapshot([wrongContext]),
              )).differences,
              contains(
                name == 'value'
                    ? 'scores.value type differs'
                    : 'scores.renamed is missing',
              ),
            );
          }
          expect(
            (await verifySchema(
              db,
              SchemaSnapshot([scores(const [])]),
            )).unmanaged.single.kind,
            'check',
          );
        });

        if (dialect == SqlDialect.sqlite) {
          test(
            'quoted Unicode identifiers retain SQLite case distinctions',
            () async {
              TableSchema table(String expression) => TableSchema(
                'unicode_checks',
                columns: [Column('Ä', Codecs.real), Column('ä', Codecs.real)],
                checks: [CheckSchema('valid', expression)],
              );
              await Migrator(db).apply([
                Migration.create('0001_initial', [table('"Ä" > 0')]),
              ]);
              expect(
                (await verifySchema(
                  db,
                  SchemaSnapshot([table('"Ä" > 0')]),
                )).matches,
                true,
              );
              expect(
                (await verifySchema(
                  db,
                  SchemaSnapshot([table('"ä" > 0')]),
                )).matches,
                false,
              );
            },
          );
          test(
            'undeclared CHECK is refused before a rebuild and remains enforced',
            () async {
              await db.execute(
                SqlCommand(
                  'CREATE TABLE scores (id INTEGER NOT NULL PRIMARY KEY, value REAL NOT NULL CHECK (value >= 0))',
                ),
              );
              final before = scores(const []);
              final after = TableSchema(
                'scores',
                columns: [
                  ...before.columns,
                  Column('label', Codecs.text.nullable(), nullable: true),
                ],
                primaryKey: ['id'],
              );
              final step = RebuildTable(
                before,
                after,
                copy: {'id': 'id', 'value': 'value', 'label': 'NULL'},
              );
              await expectLater(
                Migrator(db).apply([
                  Migration.steps('0001_rebuild', {
                    SqlDialect.sqlite: [step],
                  }),
                ]),
                throwsA(
                  isA<OrmException>().having(
                    (e) => e.code,
                    'code',
                    'MIGRATION.UNMANAGED',
                  ),
                ),
              );
              expect((await inspectTable(db, 'scores')).columns, hasLength(2));
              await expectLater(
                db.execute(SqlCommand('INSERT INTO scores VALUES (1, -1)')),
                throwsA(anything),
              );
            },
          );
        } else {
          test(
            'catalog excludes unvalidated and NO INHERIT constraints',
            () async {
              await Migrator(db).apply([
                Migration.create('0001_initial', [scores(const [])]),
              ]);
              await db.execute(
                SqlCommand(
                  'ALTER TABLE scores ADD CONSTRAINT unvalidated CHECK (value > 0) NOT VALID, ADD CONSTRAINT local_only CHECK (value < 10) NO INHERIT',
                ),
              );
              final info = await inspectTable(db, 'scores');
              expect(info.checks, isEmpty);
              expect(
                info.unmanaged.map((o) => o.name),
                containsAll(['unvalidated', 'local_only']),
              );
              final version = int.parse(
                (await db.execute(SqlCommand('SHOW server_version_num')))
                        .rows
                        .single
                        .single
                    as String,
              );
              if (version >= 180000) {
                await db.execute(
                  SqlCommand(
                    'ALTER TABLE scores ADD CONSTRAINT unenforced CHECK (value <> 0) NOT ENFORCED',
                  ),
                );
                final next = await inspectTable(db, 'scores');
                expect(next.checks, isEmpty);
                expect(
                  next.unmanaged.map((o) => o.name),
                  contains('unenforced'),
                );
              }
            },
          );
          test(
            'verification plans but does not execute volatile row expressions',
            () async {
              await db.execute(SqlCommand('CREATE SEQUENCE check_counter'));
              final start = SchemaSnapshot([
                scores(const [
                  CheckSchema('counter', "nextval('check_counter') > 0"),
                ]),
              ]);
              await Migrator(db)
                  .apply([Migration.create('0001_initial', start.tables)]);
              await db.execute(SqlCommand('INSERT INTO scores VALUES (1, 3)'));
              expect((await verifySchema(db, start)).differences, isEmpty);
              expect(
                (await db.execute(
                  SqlCommand('SELECT last_value FROM check_counter'),
                )).rows.single.single,
                1,
              );
            },
          );
        }
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
    );
  }
  test('dialect overrides only alter the affected backend and preserve old snapshot JSON', () {
    TableSchema table(CheckSchema check) => TableSchema(
      'items',
      columns: [Column('value', Codecs.text)],
      checks: [check],
    );
    final before = SchemaSnapshot([
      table(const CheckSchema('valid', 'length(value) > 0')),
    ]);
    final after = SchemaSnapshot([
      table(
        const CheckSchema.forDialects(
          'valid',
          sqlite: 'length(value) > 0',
          postgres: 'char_length(value) > 1',
        ),
      ),
    ]);
    final diff = Migration.diff('0002_change', from: before, to: after);
    expect(diff.steps[SqlDialect.sqlite], isEmpty);
    expect(diff.steps[SqlDialect.postgres], isNotEmpty);
    final legacy = SchemaSnapshot([
      TableSchema('legacy', columns: [Column('id', Codecs.integer)]),
    ]).toJson();
    expect((legacy['tables'] as List).single, isNot(contains('checks')));
  });
}
