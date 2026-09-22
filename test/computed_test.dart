import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/computed/schema.orm.dart';

TableSchema scores({
  String name = 'scores',
  String value = 'value',
  ComputedColumn? computed = const ComputedColumn('value * 2'),
  bool includeTotal = true,
  bool real = false,
  bool checked = false,
}) => TableSchema(
  name,
  columns: [
    Column('id', Codecs.integer),
    Column(value, Codecs.integer),
    if (includeTotal)
      Column<Object?>(
        'total',
        real ? Codecs.real : Codecs.integer,
        computed: computed,
      ),
  ],
  primaryKey: ['id'],
  indexes: [
    if (includeTotal && computed?.storage != ComputedStorage.virtual)
      const IndexSchema('score_total', ['total']),
  ],
  checks: [if (checked) CheckSchema('nonnegative', '$value >= 0')],
);

void main() {
  for (final dialect in [SqlDialect.sqlite, SqlDialect.postgres]) {
    group(
      'computed ${dialect.name}',
      () {
        late Database<Backend> db;
        setUp(() async {
          if (dialect == SqlDialect.sqlite) {
            db = await sqlite(const SqliteOptions.memory());
          } else {
            db = postgres(
              PostgresOptions(
                url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                schema: 'orm_computed_tests',
                tls: .disable,
              ),
            );
            await db.execute(
              SqlCommand('DROP SCHEMA IF EXISTS orm_computed_tests CASCADE'),
            );
            await db.execute(SqlCommand('CREATE SCHEMA orm_computed_tests'));
          }
        });
        tearDown(() => db.close());

        test('native expressions preserve quoted identifiers, comments and SQL-like string values', () async {
          const expression =
              '''coalesce("odd,value", ') AS (') || ',' /* ( STORED */''';
          final table = TableSchema(
            'quoted',
            columns: [
              Column('id', Codecs.integer),
              Column('odd,value', Codecs.text.nullable(), nullable: true),
              Column(
                'result)AS',
                Codecs.text,
                computed: const ComputedColumn(expression),
              ),
            ],
            primaryKey: ['id'],
          );
          final snapshot = SchemaSnapshot([table]);
          await Migrator(db.sql).apply([
            Migration.create(
              '0001_initial',
              snapshot.tables,
              dialect: db.dialect,
            ),
          ]);
          await db.execute(SqlCommand('INSERT INTO quoted (id) VALUES (1)'));
          expect(
            (await db.execute(SqlCommand('SELECT "result)AS" FROM quoted')))
                .rows,
            [
              [') AS (,'],
            ],
          );
          final info = await inspectTable(db.sql, 'quoted');
          expect(info.unmanaged, isEmpty);
          expect(info.columns.last.computed!.storage, ComputedStorage.stored);
          expect((await verifySchema(db.sql, snapshot)).differences, isEmpty);
        });

        test('generated CRUD, projections, batch and conflict writes compute stored and virtual values', () async {
          await Migrator(db.sql).apply([
            Migration.create('0001_initial', appSchema, dialect: db.dialect),
          ]);
          final row = await db.line.create(price: 4, quantity: 3, label: 'cat');
          expect((row.total, row.labelSize, row.normalizedNote), (12, 3, null));
          await db.line
              .byId(row.id)
              .patch(quantity: .set(5), note: .set('Hello'));
          expect(
            await db.line
                .select((r) => (r.total, r.labelSize, r.normalizedNote).row)
                .single(),
            (20, 3, 'HELLO'),
          );
          final inserted = await db.line
              .insertMany(
                [2, 3],
                (r, int q) => [
                  r.price.set(10),
                  r.quantity.set(q),
                  r.label.set('batch'),
                ],
              )
              .returning((r) => r.total)
              .get();
          expect(inserted, [20, 30]);
          final updated = await db.line
              .insert(
                (r) => [
                  r.id.set(row.id),
                  r.price.set(7),
                  r.quantity.set(2),
                  r.label.set('conflict'),
                ],
              )
              .onConflictUpdate(
                target: (r) => [r.id],
                set: (old, incoming) => [
                  old.price.setExpression(incoming.price),
                ],
              )
              .returning((r) => r.total)
              .get();
          expect(updated, [35]);
          expect(await db.line.where((r) => r.total.gt(.value(25))).count(), 2);
          await db.band.create(id: 35, name: 'large');
          expect(
            await db.line
                .byId(row.id)
                .select((r) => r.band.select((b) => b.name).one())
                .single(),
            'large',
          );
          expect(
            await db.band
                .byId(35)
                .select((b) => b.lines.select((r) => r.total).many())
                .single(),
            [35],
          );
          expect(
            () => db.line.update((r) => [r.column(r.total.definition).set(1)]),
            throwsA(
              isA<OrmException>().having(
                (e) => e.code,
                'code',
                'COLUMN.READ_ONLY',
              ),
            ),
          );
          await expectLater(
            db.execute(SqlCommand('UPDATE lines SET total = 1')),
            throwsA(isA<SqlFailure>()),
          );
          expect(
            (await verifySchema(db.sql, SchemaSnapshot(appSchema))).differences,
            isEmpty,
          );
        });

        test(
          'catalog/import roundtrip preserves SQL and modes and detects drift',
          () async {
            await Migrator(db.sql).apply([
              Migration.create('0001_initial', appSchema, dialect: db.dialect),
            ]);
            final info = await inspectTable(db.sql, 'lines');
            expect(info.unmanaged, isEmpty);
            expect(info.columns.where((c) => c.computed != null), hasLength(3));
            expect(
              info.columns
                  .singleWhere((c) => c.name == 'label_size')
                  .computed!
                  .storage,
              ComputedStorage.virtual,
            );
            expect(
              info.columns
                  .where((c) => c.computed != null)
                  .every((c) => c.defaultSql == null),
              true,
            );
            expect(await verifyColumns(db.sql, appSchema), isEmpty);
            final dir = await Directory(
              '.dart_tool/orm-computed-import-${dialect.name}',
            ).create(recursive: true);
            try {
              final imported = await importSchema(db.sql);
              expect(
                imported.hasBlockingIssues,
                false,
                reason: '${imported.issues.map((i) => i.toJson())}',
              );
              expect(imported.dart, contains('.computed('));
              final source = File('${dir.path}/schema.dart');
              await source.writeAsString(imported.dart);
              final generated = await generateSchema(source.path);
              expect(
                (await verifySchema(db.sql, generated.snapshot)).differences,
                isEmpty,
              );
            } finally {
              await dir.delete(recursive: true);
            }
            final wrong = SchemaSnapshot([scores()]);
            await db.execute(
              SqlCommand(createSchema(wrong.tables, dialect).first.sql),
            );
            final changed = SchemaSnapshot([
              scores(computed: const ComputedColumn('value * 3')),
            ]);
            expect(
              (await verifySchema(db.sql, changed)).differences,
              contains('scores.total computed expression or storage differs'),
            );
            expect(
              await verifyColumns(db.sql, changed.tables),
              contains('scores.total computed expression or storage differs'),
            );
          },
        );

        for (final storage in ComputedStorage.values) {
          test(
            '$storage add, expression/type change and drop preserve existing rows',
            () async {
              final start = SchemaSnapshot([scores(includeTotal: false)]);
              final initial = Migration.create(
                '0001_initial',
                start.tables,
                dialect: db.dialect,
              );
              await Migrator(db.sql).apply([initial]);
              await db.execute(SqlCommand('INSERT INTO scores VALUES (1, 3)'));
              final withTotal = SchemaSnapshot([
                scores(computed: ComputedColumn('value * 2', storage: storage)),
              ]);
              final add = Migration.diff(
                '0002_add',
                from: start,
                to: withTotal,
                previous: initial.checksum,
                dialect: db.dialect,
              );
              if (dialect == SqlDialect.sqlite) {
                expect(
                  add.steps.whereType<RebuildTable>().length,
                  storage == ComputedStorage.stored ? 1 : 0,
                );
              }
              await Migrator(db.sql).apply([initial, add]);
              expect(
                (await db.execute(SqlCommand('SELECT total FROM scores'))).rows,
                [
                  [6],
                ],
              );
              expect(
                (await verifySchema(db.sql, withTotal)).differences,
                isEmpty,
              );
              final changed = SchemaSnapshot([
                scores(
                  computed: ComputedColumn('value * 3', storage: storage),
                  real: true,
                ),
              ]);
              final change = Migration.diff(
                '0003_change',
                from: withTotal,
                to: changed,
                previous: add.checksum,
                dialect: db.dialect,
              );
              await Migrator(db.sql).apply([initial, add, change]);
              expect(
                (await db.execute(SqlCommand('SELECT total FROM scores'))).rows,
                [
                  [9.0],
                ],
              );
              expect(
                (await verifySchema(db.sql, changed)).differences,
                isEmpty,
              );
              final remove = Migration.diff(
                '0004_drop',
                from: changed,
                to: start,
                previous: change.checksum,
                allowDestructive: true,
                dialect: db.dialect,
              );
              await Migrator(db.sql).apply([initial, add, change, remove]);
              expect(
                (await db.execute(SqlCommand('SELECT * FROM scores'))).rows,
                [
                  [1, 3],
                ],
              );
              expect((await verifySchema(db.sql, start)).differences, isEmpty);
            },
          );
        }

        test('stored to ordinary materialization retains values and permits later writes', () async {
          final start = SchemaSnapshot([scores()]);
          final initial = Migration.create(
            '0001_initial',
            start.tables,
            dialect: db.dialect,
          );
          await Migrator(db.sql).apply([initial]);
          await db.execute(
            SqlCommand('INSERT INTO scores (id, value) VALUES (1, 3)'),
          );
          final target = SchemaSnapshot([scores(computed: null)]);
          final materialize = Migration.diff(
            '0002_materialize',
            from: start,
            to: target,
            previous: initial.checksum,
            dialect: db.dialect,
          );
          await Migrator(db.sql).apply([initial, materialize]);
          expect(
            (await db.execute(SqlCommand('SELECT total FROM scores'))).rows,
            [
              [6],
            ],
          );
          await db.execute(
            SqlCommand('UPDATE scores SET value = 4, total = 20'),
          );
          expect(
            (await db.execute(SqlCommand('SELECT total FROM scores'))).rows,
            [
              [20],
            ],
          );
          expect((await verifySchema(db.sql, target)).differences, isEmpty);
        });

        test('explicit renamed expressions preserve indexes, checks, references and views', () async {
          TableSchema notes(String target) => TableSchema(
            'notes',
            columns: [Column('id', Codecs.integer)],
            primaryKey: ['id'],
            foreignKeys: [
              ForeignKey(['id'], target, ['id']),
            ],
          );
          final start = SchemaSnapshot([
            scores(checked: true),
            notes('scores'),
          ]);
          final initial = Migration.create(
            '0001_initial',
            start.tables,
            dialect: db.dialect,
          );
          await Migrator(db.sql).apply([initial]);
          await db.execute(
            SqlCommand('INSERT INTO scores (id, value) VALUES (1, 3)'),
          );
          await db.execute(SqlCommand('INSERT INTO notes VALUES (1)'));
          await db.execute(
            SqlCommand('CREATE VIEW totals AS SELECT total FROM scores'),
          );
          final target = SchemaSnapshot([
            scores(
              name: 'marks',
              value: 'amount',
              checked: true,
              computed: const ComputedColumn('amount * 3'),
            ),
            notes('marks'),
          ]);
          final rename = Migration.diff(
            '0002_rename',
            from: start,
            to: target,
            previous: initial.checksum,
            renames: const SchemaRenames(
              tables: {'scores': 'marks'},
              columns: {
                'marks': {'value': 'amount'},
              },
            ),
            dialect: db.dialect,
          );
          if (dialect == SqlDialect.sqlite) {
            expect(rename.steps.whereType<RebuildTable>(), hasLength(2));
          }
          await Migrator(db.sql).apply([initial, rename]);
          expect((await db.execute(SqlCommand('SELECT * FROM totals'))).rows, [
            [9],
          ]);
          expect((await verifySchema(db.sql, target)).differences, isEmpty);
          await expectLater(
            db.execute(SqlCommand('DELETE FROM marks')),
            throwsA(anything),
          );
          await expectLater(
            db.execute(SqlCommand('UPDATE marks SET amount = -1')),
            throwsA(anything),
          );
        });

        test(
          'invalid recomputation rolls back the table and migration history',
          () async {
            final start = SchemaSnapshot([scores()]);
            final initial = Migration.create(
              '0001_initial',
              start.tables,
              dialect: db.dialect,
            );
            await Migrator(db.sql).apply([initial]);
            await db.execute(
              SqlCommand('INSERT INTO scores (id, value) VALUES (1, 3)'),
            );
            final target = SchemaSnapshot([
              scores(computed: const ComputedColumn('NULL')),
            ]);
            final change = Migration.diff(
              '0002_null',
              from: start,
              to: target,
              previous: initial.checksum,
              dialect: db.dialect,
            );
            await expectLater(
              Migrator(db.sql).apply([initial, change]),
              throwsA(anything),
            );
            expect(
              (await db.execute(SqlCommand('SELECT total FROM scores'))).rows,
              [
                [6],
              ],
            );
            expect(
              (await db.execute(
                SqlCommand('SELECT count(*) FROM _orm_migrations'),
              )).rows.single.single,
              1,
            );
            expect((await verifySchema(db.sql, start)).differences, isEmpty);
          },
        );

        test('decimal computed SQL keeps precision coercion and imports exactly once', () async {
          final table = TableSchema(
            'amounts',
            columns: [
              Column('id', Codecs.integer),
              Column(
                'amount',
                Codecs.decimal,
                decimalPrecision: 5,
                decimalScale: 2,
                computed: const ComputedColumn("'12.345'"),
              ),
            ],
            primaryKey: ['id'],
          );
          final snapshot = SchemaSnapshot([table]);
          await Migrator(db.sql).apply([
            Migration.create(
              '0001_initial',
              snapshot.tables,
              dialect: db.dialect,
            ),
          ]);
          await db.execute(SqlCommand('INSERT INTO amounts (id) VALUES (1)'));
          expect(
            (await db.execute(SqlCommand('SELECT amount FROM amounts')))
                .rows
                .single
                .single
                .toString(),
            '12.35',
          );
          expect((await verifySchema(db.sql, snapshot)).differences, isEmpty);
          final dir = await Directory(
            '.dart_tool/orm-computed-decimal-${dialect.name}',
          ).create(recursive: true);
          try {
            final imported = await importSchema(db.sql);
            expect(imported.hasBlockingIssues, false);
            final file = File('${dir.path}/schema.dart');
            await file.writeAsString(imported.dart);
            final result = await generateSchema(file.path);
            expect(
              (await verifySchema(db.sql, result.snapshot)).differences,
              isEmpty,
            );
          } finally {
            await dir.delete(recursive: true);
          }
        });
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
      tags: dialect.name,
    );
  }

  test('mode conversions need explicit plans and historical copy/backfill cannot write computed columns', () {
    final stored = SchemaSnapshot([scores()]);
    final virtual = SchemaSnapshot([
      scores(
        computed: const ComputedColumn(
          'value * 2',
          storage: ComputedStorage.virtual,
        ),
      ),
    ]);
    final plain = SchemaSnapshot([scores(computed: null)]);
    for (final (from, to) in [
      (stored, virtual),
      (virtual, stored),
      (plain, stored),
      (virtual, plain),
    ]) {
      expect(
        () => Migration.diff(
          '0002_mode',
          from: from,
          to: to,
          dialect: SqlDialect.postgres,
        ),
        throwsA(
          isA<OrmException>().having(
            (e) => e.code,
            'code',
            'MIGRATION.COMPUTED',
          ),
        ),
      );
    }
    expect(
      () => RebuildTable(
        stored.tables.single,
        stored.tables.single,
        copy: {'total': 'value * 2'},
      ),
      throwsA(isA<OrmException>()),
    );
    expect(
      () => Backfill(
        stored.tables.single,
        set: {'total': 'value * 2'},
        doneWhen: 'SELECT TRUE',
      ),
      throwsArgumentError,
    );
  });
}
