import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/decimals/schema.orm.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('exact decimal $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_decimal_tests',
            ),
          );
          await db.execute(
            SqlCommand('DROP SCHEMA IF EXISTS orm_decimal_tests CASCADE'),
          );
          await db.execute(SqlCommand('CREATE SCHEMA orm_decimal_tests'));
        }
      });
      tearDown(() => db.close());
      Future<void> create() =>
          Migrator(db).apply([Migration.create('0001_decimal', appSchema)]);
      Future<void> amounts(List<String> values) async {
        for (final v in values) {
          await db.entries.create(amount: d(v), bucket: 'a');
        }
      }

      test('generated writes, defaults, patches and projections preserve all digits', () async {
        await create();
        final n = d('9007199254740993.12345678901234567890123456789');
        final first = await db.entries.create(amount: n, bucket: 'a');
        expect(first.amount, n);
        expect(first.tax, d('.1'));
        expect(first.fee, null);
        await db.entries
            .byId(first.id)
            .patch(fee: Change.set(d('.00000000000000000000000000001')));
        final row = await db.entries.byId(first.id).single();
        expect(row.fee, d('.00000000000000000000000000001'));
        final result = await db.entries
            .select(
              (e) => (
                e.amount.plus(d('.00000000000000000000000000001')),
                e.amount.minus(d('.12345678901234567890123456789')),
                e.tax.times(d('3')),
                e.amount.plusExpression(e.fee),
              ).row,
            )
            .single();
        expect(result, (
          d('9007199254740993.1234567890123456789012345679'),
          d('9007199254740993'),
          d('.3'),
          d('9007199254740993.1234567890123456789012345679'),
        ));
        await db.entries.byId(first.id).patch(fee: const Change.set(null));
        expect(
          await db.entries
              .select((e) => e.amount.plusExpression(e.fee))
              .single(),
          null,
        );
        expect(
          await db.entries.select((e) => value(n, Codecs.decimal)).single(),
          n,
        );
      });

      test(
        'numeric ordering, predicates, IN, distinct and stable cursors',
        () async {
          await create();
          await amounts(['10', '2', '-2', '-10', '.00000000000000000001', '2']);
          expect(
            await db.entries
                .orderBy((e) => [e.amount.asc()])
                .select((e) => e.amount)
                .get(),
            ['-10', '-2', '.00000000000000000001', '2', '2', '10'].map(d),
          );
          expect(await db.entries.where((e) => e.amount.gt(d('2'))).count(), 1);
          expect(
            await db.entries
                .where((e) => e.amount.isIn([d('2.00'), d('-10')]))
                .count(),
            3,
          );
          expect(
            await db.entries
                .select((e) => e.amount.count(distinct: true))
                .single(),
            5,
          );
          final ordered = db.entries.orderBy(
            (e) => [e.amount.asc(), e.id.asc()],
          );
          final first = (await ordered.take(2).get()).last;
          final token = db.entries.cursorToken(
            (e) => [e.amount.cursor(first.amount), e.id.cursor(first.id)],
          );
          final rest = await db.entries
              .seekToken(token, orderBy: (e) => [e.amount.asc(), e.id.asc()])
              .get();
          expect(
            rest.map((r) => r.amount),
            ['.00000000000000000001', '2', '2', '10'].map(d),
          );
        },
      );

      test(
        'sums, min/max, grouped aggregates and sliding windows stay exact',
        () async {
          await create();
          expect(await db.entries.select((e) => e.amount.sum()).single(), null);
          await amounts(['.1', '.2', '.3', '.3']);
          expect(
            await db.entries
                .select(
                  (e) => (
                    e.amount.sum(),
                    e.amount.sum(distinct: true),
                    e.amount.min(),
                    e.amount.max(),
                  ).row,
                )
                .single(),
            (d('.9'), d('.6'), d('.1'), d('.3')),
          );
          expect(
            await db.entries
                .groupBy((e) => [e.bucket])
                .select((e) => (e.bucket, e.amount.sum()).row)
                .single(),
            ('a', d('.9')),
          );
          final windows = await db.entries
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => e.amount.sum().over(
                  orderBy: [e.id.asc()],
                  frame: .rowsToCurrent,
                ),
              )
              .get();
          expect(windows, ['.1', '.3', '.6', '.9'].map(d));
          await db.execute(SqlCommand('UPDATE entries SET fee = amount'));
          expect(await db.entries.select((e) => e.fee.sum()).single(), d('.9'));
          if (backend == 'sqlite') {
            final rows = await db.execute(
              SqlCommand(
                'SELECT orm_decimal_sum_v1(amount) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) FROM entries ORDER BY id',
              ),
            );
            expect(
              rows.rows.map((r) => Codecs.decimal.decode(r.single)),
              ['.1', '.3', '.5', '.6'].map(d),
            );
          }
        },
      );

      test('computed CTEs, union results, subqueries and streaming keep decimal semantics', () async {
        await create();
        await amounts(['2', '10', '-2']);
        final source = db.entries.select((e) => e.amount.times(d('2')));
        final cte = source.asCte('doubled');
        expect(
          await cte.query
              .where((e) => e.ref((o) => o.amount.times(d('2'))).gt(d('5')))
              .get(),
          [d('20')],
        );
        final set = db.entries
            .select((e) => e.amount)
            .union(db.entries.select((e) => e.amount.plus(d('0'))));
        expect(await set.get(), unorderedEquals(['2', '10', '-2'].map(d)));
        expect(
          await set.stream().toList(),
          unorderedEquals(['2', '10', '-2'].map(d)),
        );
        expect(
          await db.entries
              .where(
                (e) => e.amount.isInQuery(
                  db.entries
                      .where((e) => e.amount.gt(d('2')))
                      .select((e) => e.amount),
                ),
              )
              .count(),
          1,
        );
      });

      test(
        'numeric primary keys, foreign keys, joined and batched relations',
        () async {
          await create();
          await db.rates.create(id: d('2'), label: 'two');
          await db.execute(
            SqlCommand(
              "INSERT INTO allocations (\"rate_id\") VALUES ('2.000')",
            ),
          );
          expect(
            await db.allocations
                .select((a) => a.rate.select((r) => r.label).required())
                .single(),
            'two',
          );
          final children = await db.rates
              .select((r) => r.allocations.select((a) => a.rateId).many())
              .single();
          expect(children, [d('2')]);
          await expectLater(
            db.execute(
              SqlCommand(
                "INSERT INTO rates (id, label) VALUES ('2.00', 'duplicate')",
              ),
            ),
            throwsA(isA<SqlFailure>()),
          );
          await expectLater(
            db.allocations.create(rateId: d('3')),
            throwsA(isA<SqlFailure>()),
          );
          expect((await db.rates.byId(d('2.000')).single()).label, 'two');
          if (backend == 'sqlite') {
            final command = db.rates.byId(d('2')).compile();
            final plan = await db.execute(
              SqlCommand(
                'EXPLAIN QUERY PLAN ${command.sql}',
                command.parameters,
              ),
            );
            expect(
              plan.rows.map((r) => r.last).join(' '),
              contains('USING INDEX'),
            );
          }
        },
      );

      test('snapshots, catalog verification and imported declarations retain decimal storage', () async {
        await create();
        await amounts(['12345678901234567890.00000000001']);
        final snapshot = SchemaSnapshot(appSchema);
        expect(
          SchemaSnapshot.fromJson(
            jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>,
          ).checksum,
          snapshot.checksum,
        );
        final verification = await verifySchema(db, snapshot);
        expect(verification.differences, isEmpty);
        expect(verification.unmanaged, isEmpty);
        expect(await verifyColumns(db, appSchema), isEmpty);
        final imported = await importSchema(db);
        expect(imported.issues, isEmpty);
        expect(imported.dart, contains('Decimal'));
        final directory = await Directory(
          '.dart_tool/orm-decimal-import-$backend',
        ).create(recursive: true);
        try {
          final source = File('${directory.path}/schema.dart');
          await source.writeAsString(imported.dart);
          final generated = await generateSchema(source.path);
          expect(
            (await verifySchema(
              db,
              SchemaSnapshot.fromJson(generated.snapshot),
            )).differences,
            isEmpty,
          );
        } finally {
          await directory.delete(recursive: true);
        }
        expect(
          (await db.entries.single()).amount,
          d('12345678901234567890.00000000001'),
        );
      });

      test('aggregate intermediate overflow may cancel before a valid final result', () async {
        await create();
        final huge = d('9e131071');
        await db.entries.create(amount: huge, bucket: 'a');
        await db.entries.create(amount: huge, bucket: 'a');
        await db.entries.create(amount: -huge, bucket: 'a');
        expect(await db.entries.select((e) => e.amount.sum()).single(), huge);
        await db.entries
            .where((e) => e.amount.lt(Decimal.zero))
            .delete()
            .execute();
        await expectLater(
          db.entries.select((e) => e.amount.sum()).single(),
          throwsA(isA<SqlFailure>()),
        );
        expect(await db.entries.count(), 2);
      });

      test('historical decimal keys resume backfills without lexical ordering or precision loss', () async {
        await create();
        for (final n in ['10', '2', '-10', '.00000000000000000001']) {
          await db.rates.create(id: d(n), label: 'pending');
        }
        final first = Migration.create('0001_decimal', appSchema);
        final second = Migration.steps('0002_backfill', {
          for (final dialect in SqlDialect.values)
            dialect: [
              Backfill(
                ratesSchema,
                set: {'label': "'done'"},
                where: "label = 'pending'",
                doneWhen: "SELECT NOT EXISTS (SELECT 1 FROM rates WHERE label = 'pending')",
                batchSize: 1,
              ),
            ],
        }, previous: first.checksum);
        await Migrator(db).apply([first, second], maxBackfillBatches: 1);
        expect(await db.rates.where((r) => r.label.eq('done')).count(), 1);
        await Migrator(db).apply([first, second]);
        expect(await db.rates.where((r) => r.label.eq('done')).count(), 4);
      });

      test('reviewed text-to-decimal migration rejects duplicate numeric keys and rolls back', () async {
        TableSchema schema(Codec<Object?> codec) => TableSchema(
          'converted',
          columns: [Column('id', Codecs.integer), Column('amount', codec)],
          primaryKey: ['id'],
          uniqueKeys: [
            ['amount'],
          ],
        );
        final first = Migration.create('0001_text', [schema(Codecs.text)]);
        await Migrator(db).apply([first]);
        await db.execute(
          SqlCommand(
            "INSERT INTO converted VALUES (1, '2'), (2, '2.00'), (3, '12345678901234567890.00000000001')",
          ),
        );
        final next = Migration.diff(
          '0002_decimal',
          from: first.snapshot!,
          to: SchemaSnapshot([schema(Codecs.decimal)]),
          previous: first.checksum,
          using: {
            SqlDialect.sqlite: {
              'converted': {'amount': 'amount'},
            },
            SqlDialect.postgres: {
              'converted': {'amount': 'CAST(amount AS NUMERIC)'},
            },
          },
        );
        await expectLater(
          Migrator(db).apply([first, next]),
          throwsA(isA<SqlFailure>()),
        );
        expect((await Migrator(db).history()).length, 1);
        expect(
          (await db.execute(
            SqlCommand('SELECT amount FROM converted WHERE id = 2'),
          )).rows.single.single,
          '2.00',
        );
        await db.execute(SqlCommand('DELETE FROM converted WHERE id = 2'));
        await Migrator(db).apply([first, next]);
        expect((await verifySchema(db, next.snapshot!)).differences, isEmpty);
        expect((await verifySchema(db, next.snapshot!)).unmanaged, isEmpty);
        final row = await db.execute(
          SqlCommand('SELECT amount FROM converted WHERE id = 3'),
        );
        expect(
          Codecs.decimal.decode(row.rows.single.single),
          d('12345678901234567890.00000000001'),
        );
      });

      test('invalid external values fail decoding; later valid queries still work', () async {
        await create();
        await db.execute(
          SqlCommand(
            "INSERT INTO entries (amount, bucket) VALUES ('${backend == 'sqlite' ? 'invalid' : 'NaN'}', 'bad')",
          ),
        );
        await expectLater(db.entries.get(), throwsFormatException);
        if (backend == 'sqlite') {
          await amounts(['2', '-10', '10']);
          final raw = await db.execute(
            SqlCommand('SELECT amount FROM entries ORDER BY amount'),
          );
          expect(raw.rows.map((r) => r.single), ['-10', '2', '10', 'invalid']);
          await expectLater(
            db.entries.select((e) => e.amount.sum()).single(),
            throwsA(isA<SqlFailure>()),
          );
        }
        await db.entries.where((e) => e.bucket.eq('bad')).delete().execute();
        expect(await db.entries.where((e) => e.bucket.eq('bad')).count(), 0);
      });
    });
  }

  test(
    'decimal SQL rejects drivers without exact operations before execution',
    () async {
      final db = Database(_NoDecimalDriver());
      expect(
        () => db.entries.select((e) => e.amount).compile(),
        throwsA(
          isA<OrmException>().having(
            (e) => e.code,
            'code',
            'CAPABILITY.DECIMAL',
          ),
        ),
      );
      await db.close();
    },
  );

  test('SQLite recognizes only column decimal collations, and detects drift', () async {
    final db = await sqlite(const SqliteOptions.memory());
    try {
      final table = TableSchema(
        'quoted',
        columns: [
          Column('id', Codecs.integer),
          Column('a"b', Codecs.decimal),
          Column(
            'literal',
            Codecs.text,
            defaultSql: "'COLLATE orm_decimal_v1'",
          ),
        ],
        primaryKey: ['id'],
        uniqueKeys: [
          ['a"b'],
        ],
      );
      await Migrator(db).apply([
        Migration.create('0001_quoted', [table]),
      ]);
      expect(
        (await verifySchema(db, SchemaSnapshot([table]))).differences,
        isEmpty,
      );
      expect((await inspectTable(db, 'quoted')).unmanaged, isEmpty);
      await db.execute(
        SqlCommand(
          'CREATE TABLE missing (id INTEGER NOT NULL, amount TEXT NOT NULL DEFAULT (\'COLLATE orm_decimal_v1\'), PRIMARY KEY (id))',
        ),
      );
      final expected = TableSchema(
        'missing',
        columns: [
          Column('id', Codecs.integer),
          Column('amount', Codecs.decimal),
        ],
        primaryKey: ['id'],
      );
      expect(await verifyColumns(db, [expected]), [
        'missing.amount collation differs',
      ]);
      await db.execute(
        SqlCommand('CREATE TABLE custom (amount TEXT COLLATE NOCASE)'),
      );
      expect((await inspectTable(db, 'custom')).unmanaged, isNotEmpty);
      final imported = await importSchema(db, tables: ['missing']);
      expect(imported.dart, contains('String amount'));
      await db.execute(
        SqlCommand(
          'CREATE TABLE unicode_names (Ä TEXT COLLATE orm_decimal_v1, ä TEXT)',
        ),
      );
      final unicode = await inspectColumns(db, 'unicode_names');
      expect(unicode.map((c) => (c.name, c.collation?.toLowerCase())), [
        ('Ä', 'orm_decimal_v1'),
        ('ä', 'binary'),
      ]);
    } finally {
      await db.close();
    }
  });
}

final class _NoDecimalDriver implements Driver<Sqlite> {
  @override
  final capabilities = const Capabilities(
    dialect: SqlDialect.sqlite,
    maxParameters: 999,
  );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      throw StateError('Compilation must reject first');
  @override
  Future<void> close() async {}
}
