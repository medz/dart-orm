@Tags(['database'])
library;

import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart' hide allOf, anyOf;

import 'support/decimals/schema.orm.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('decimal division $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_decimal_division_tests',
            ),
          );
          await db.execute(
            SqlCommand(
              'DROP SCHEMA IF EXISTS orm_decimal_division_tests CASCADE',
            ),
          );
          await db.execute(
            SqlCommand('CREATE SCHEMA orm_decimal_division_tests'),
          );
        }
        await Migrator(db.sql).apply([
          Migration.create('0001_decimal', appSchema, dialect: db.dialect),
        ]);
      });
      tearDown(() => db.close());

      Future<Decimal?> ratio(
        Decimal a,
        Decimal b,
        int scale,
        DecimalRounding mode,
      ) async {
        return db.entry
            .select(
              (e) => value(
                a,
                Codecs.decimal,
              ).divide(b, scale: scale, rounding: mode),
            )
            .single();
      }

      test('signed modes and scales match exact integer arithmetic', () async {
        for (final a in [
          '0',
          '1',
          '-1',
          '5',
          '-5',
          '25',
          '-25',
          '1250',
          '-1250',
          '2.345',
          '-2.345',
          '2.355',
          '-2.355',
          '.4999999999999999999999999999',
        ]) {
          for (final b in ['2', '-2', '.03', '-.03']) {
            await db.entry.create(amount: d(a), fee: d(b), bucket: 'a');
          }
        }
        final input = await db.entry.orderBy((e) => [e.id.asc()]).get();
        for (final mode in DecimalRounding.values.where((m) => m != .exact)) {
          for (final scale in [-3, -1, 0, 1, 2, 8, 100]) {
            final output = await db.entry
                .orderBy((e) => [e.id.asc()])
                .select(
                  (e) => (
                    e.amount.divideExpression(
                      e.fee,
                      scale: scale,
                      rounding: mode,
                    ),
                    e.amount.rounded(scale, rounding: mode),
                  ).row,
                )
                .get();
            expect(
              output,
              input.map(
                (r) => (
                  r.amount.divide(r.fee!, scale: scale, rounding: mode),
                  r.amount.rounded(scale, rounding: mode),
                ),
              ),
              reason: '$mode scale=$scale',
            );
          }
        }
      });

      test(
        'exact defaults reject lost digits and zero divisors, NULL propagates',
        () async {
          await db.entry.create(amount: d('1'), bucket: 'a');
          expect(await ratio(d('1'), d('8'), 3, .exact), d('.125'));
          expect(await ratio(d('1200'), d('2'), -2, .exact), d('600'));
          expect(
            await db.entry.select((e) => e.amount.rounded(0)).single(),
            d('1'),
          );
          await expectLater(
            ratio(d('1'), d('3'), 100, .exact),
            throwsA(isA<Exception>()),
          );
          await expectLater(
            ratio(d('1'), d('0'), 2, .halfEven),
            throwsA(isA<Exception>()),
          );
          await expectLater(
            db.entry.select((e) => e.amount.rounded(-1)).single(),
            throwsA(isA<Exception>()),
          );
          expect(
            await db.entry
                .select((e) => e.fee.divide(d('0'), scale: 2))
                .single(),
            null,
          );
          expect(
            await db.entry
                .select((e) => e.amount.divideExpression(e.fee, scale: 2))
                .single(),
            null,
          );
          expect(
            await db.entry.select((e) => e.fee.rounded(-2)).single(),
            null,
          );
        },
      );

      test(
        'precision exceeds native division scale without double rounding',
        () async {
          await db.entry.create(amount: d('1'), bucket: 'a');
          for (final scale in [50, 1000, Decimal.maxFractionDigits]) {
            final actual = await ratio(d('1'), d('3'), scale, .halfEven);
            expect(
              actual ==
                  d('1').divide(d('3'), scale: scale, rounding: .halfEven),
              isTrue,
              reason: 'scale=$scale',
            );
          }
          expect(
            await ratio(
              d('.4999999999999999999999999999'),
              d('1'),
              0,
              .halfAwayFromZero,
            ),
            d('0'),
          );
          expect(
            await ratio(
              d('2.5000000000000000000000000001'),
              d('1'),
              0,
              .halfEven,
            ),
            d('3'),
          );
          final smallest = d('1e-16383');
          expect(await ratio(smallest, d('1'), 16383, .exact), smallest);
          expect(await ratio(smallest, d('2'), 16383, .halfEven), d('0'));
          expect(
            await ratio(smallest, d('2'), 16383, .halfAwayFromZero),
            smallest,
          );
        },
      );

      test(
        'huge remainders avoid overflowing intermediate scaled products',
        () async {
          await db.entry.create(amount: d('1'), bucket: 'a');
          final huge = d('9e131071');
          final pairs = [
            (d('8e131071'), huge),
            (huge, huge + d('1')),
            (huge, huge + d('1e-16383')),
          ];
          for (final (a, b) in pairs) {
            for (final scale in [1, 50, 16383]) {
              for (final mode in [
                DecimalRounding.towardZero,
                DecimalRounding.halfEven,
                DecimalRounding.ceiling,
              ]) {
                final expected = a.divide(b, scale: scale, rounding: mode);
                final actual = await ratio(a, b, scale, mode);
                expect(
                  actual == expected,
                  isTrue,
                  reason: 'large operands scale=$scale mode=$mode',
                );
              }
            }
          }
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'outermost integer scale and result overflow are explicit',
        () async {
          await db.entry.create(amount: d('1'), bucket: 'a');
          expect(
            await ratio(d('5e131071'), d('1'), -131072, .halfEven),
            d('0'),
          );
          expect(
            await ratio(d('-5e131071'), d('1'), -131072, .ceiling),
            d('0'),
          );
          expect(
            await ratio(d('9e131071'), d('1'), -131072, .towardZero),
            d('0'),
          );
          await expectLater(
            ratio(d('5e131071'), d('1'), -131072, .halfAwayFromZero),
            throwsA(isA<Exception>()),
          );
          await expectLater(
            ratio(d('9e131071'), d('.1'), 0, .towardZero),
            throwsA(isA<Exception>()),
          );
          expect(await ratio(d('0'), d('1'), -131072, .exact), d('0'));
        },
      );

      test('aggregates windows CTEs predicates and unions compose', () async {
        await db.entry.create(amount: d('2.345'), bucket: 'a');
        await db.entry.create(amount: d('4.345'), bucket: 'a');
        expect(
          await db.entry
              .select(
                (e) => e.amount.sum().divide(
                  d('2'),
                  scale: 2,
                  rounding: .halfEven,
                ),
              )
              .single(),
          d('3.34'),
        );
        expect(
          await db.entry
              .groupBy((e) => [e.bucket])
              .select(
                (e) => (
                  e.bucket,
                  e.amount.sum().rounded(1, rounding: .halfEven),
                ).row,
              )
              .single(),
          ('a', d('6.7')),
        );
        expect(
          await db.entry
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => e.amount
                    .sum()
                    .over(orderBy: [e.id.asc()], frame: .rowsToCurrent)
                    .divide(d('2'), scale: 2, rounding: .halfEven),
              )
              .get(),
          [d('1.17'), d('3.34')],
        );
        final cte = db.entry
            .select(
              (e) => e.amount.divide(d('2'), scale: 2, rounding: .halfEven),
            )
            .asCte('halves');
        expect(
          await cte.query
              .where(
                (e) => e
                    .ref(
                      (o) => o.amount.divide(
                        d('2'),
                        scale: 2,
                        rounding: .halfEven,
                      ),
                    )
                    .gt(d('2')),
              )
              .get(),
          [d('2.17')],
        );
        expect(
          await db.entry
              .where((e) => e.amount.rounded(0, rounding: .halfEven).eq(d('2')))
              .count(),
          1,
        );
        final set = db.entry
            .select((e) => e.amount.rounded(0, rounding: .halfEven))
            .union(
              db.entry.select(
                (e) => e.amount.divide(d('1'), scale: 0, rounding: .halfEven),
              ),
            );
        expect(await set.get(), unorderedEquals([d('2'), d('4')]));
      });

      test(
        'expression assignments and transaction rollback preserve values',
        () async {
          final row = await db.entry.create(
            amount: d('10'),
            fee: d('3'),
            bucket: 'a',
          );
          await db.entry
              .byId(row.id)
              .update(
                (e) => [
                  e.amount.setExpression(e.amount.divide(d('4'), scale: 2)),
                ],
              )
              .execute();
          expect((await db.entry.byId(row.id).single()).amount, d('2.5'));
          await expectLater(
            db.transaction((tx) async {
              await tx.entry
                  .byId(row.id)
                  .patch(bucket: const Change.set('changed'));
              await tx.entry
                  .byId(row.id)
                  .update(
                    (e) => [
                      e.amount.setExpression(e.amount.divide(d('3'), scale: 2)),
                    ],
                  )
                  .execute();
            }),
            throwsA(isA<Exception>()),
          );
          expect((await db.entry.byId(row.id).single()).bucket, 'a');
          expect((await db.entry.byId(row.id).single()).amount, d('2.5'));
        },
      );

      test('window filtering ordering DISTINCT and pagination keep their SQL order', () async {
        for (final n in ['1', '3', '5']) {
          await db.entry.create(amount: d(n), bucket: 'a');
        }
        await db.entry.create(amount: d('100'), bucket: 'excluded');
        Expr<Decimal?> running(EntryFields e) => e.amount
            .sum()
            .over(orderBy: [e.id.asc()], frame: .rowsToCurrent)
            .divide(d('2'), scale: 1);
        final query = db.entry
            .where((e) => e.bucket.eq('a'))
            .orderBy((e) => [running(e).desc()]);
        expect(await query.select(running).get(), [d('4.5'), d('2'), d('.5')]);
        expect(await query.select(running).skip(1).take(1).get(), [d('2')]);
        expect(await query.select((e) => e.id).get(), [3, 2, 1]);
        Expr<Decimal?> total(EntryFields e) =>
            e.amount.sum().over(frame: .rowsAll).divide(d('3'), scale: 0);
        final distinct = db.entry
            .where((e) => e.bucket.eq('a'))
            .orderBy((e) => [total(e).desc()])
            .select(total)
            .distinct();
        expect(await distinct.get(), [d('3')]);
        expect(await distinct.skip(1).get(), isEmpty);
      });

      test('windows over grouped aggregates run after HAVING', () async {
        await db.entry.create(amount: d('1'), bucket: 'a');
        await db.entry.create(amount: d('3'), bucket: 'a');
        await db.entry.create(amount: d('6'), bucket: 'b');
        await db.entry.create(amount: d('100'), bucket: 'excluded');
        final result = await db.entry
            .groupBy((e) => [e.bucket])
            .having((e) => e.amount.sum().lt(d('50')))
            .orderBy((e) => [e.bucket.asc()])
            .select(
              (e) => (
                e.bucket,
                e.amount
                    .sum()
                    .sum()
                    .over(orderBy: [e.bucket.asc()], frame: .rowsToCurrent)
                    .divide(d('2'), scale: 0),
              ).row,
            )
            .get();
        expect(result, [('a', d('2')), ('b', d('5'))]);
      });

      test(
        'window results compose through CTEs sets and correlated subqueries',
        () async {
          await db.entry.create(amount: d('1'), bucket: 'a');
          await db.entry.create(amount: d('3'), bucket: 'a');
          Expr<Decimal?> running(EntryFields e) => e.amount
              .sum()
              .over(orderBy: [e.id.asc()], frame: .rowsToCurrent)
              .divide(d('2'), scale: 1);
          final projected = db.entry
              .orderBy((e) => [e.id.asc()])
              .select(running);
          final cte = projected.asCte('running_halves');
          expect(await projected.stream().toList(), [d('.5'), d('2')]);
          expect(
            () => cte.query.where(
              (e) => e
                  .ref(
                    (o) => o.amount
                        .sum()
                        .over(orderBy: [o.id.asc()], frame: .rowsAll)
                        .divide(d('2'), scale: 1),
                  )
                  .gt(d('1')),
            ),
            throwsA(isA<OrmException>()),
          );
          expect(
            await cte.query.where((e) => e.ref(running).gt(d('1'))).get(),
            [d('2')],
          );
          expect(
            await projected.union(projected).get(),
            unorderedEquals([d('.5'), d('2')]),
          );
          final outer = db.entry;
          final inner = db.entry;
          final result = await outer
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => inner
                    .where(
                      (i) => sql(
                        ['(', ' <= ', ')'],
                        [i.id, e.id],
                        Codecs.boolean.nullable(),
                      ),
                    )
                    .orderBy((i) => [i.id.desc()])
                    .select(running)
                    .take(1)
                    .scalar(),
              )
              .get();
          expect(result, [d('.5'), d('2')]);
          final alias = entryTable.alias();
          final joined = await db.entry
              .leftJoin(
                alias,
                on: (e, a) => allOf([e.id.equals(a.id), a.id.eq(1)]),
              )
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => (
                  e.id,
                  running(e).rounded(0, rounding: .halfEven),
                  alias.optional(alias.fields.amount),
                ).map((id, n, matched) => (id, n, matched)),
              )
              .get();
          expect(joined, [(1, d('0'), d('1')), (2, d('2'), null)]);
        },
      );

      test('batched relations retain per-parent window pagination', () async {
        for (final n in ['2', '4']) {
          await db.rate.create(id: d(n), label: n);
          for (var i = 0; i < 2; i++) {
            await db.allocation.create(rateId: d(n));
          }
        }
        final result = await db.rate
            .orderBy((r) => [r.id.asc()])
            .select(
              (r) => (
                r.label,
                r.allocations
                    .orderBy((a) => [a.id.desc()])
                    .take(1)
                    .select(
                      (a) => a.rateId
                          .sum()
                          .over(
                            partitionBy: [a.rateId],
                            orderBy: [a.id.asc()],
                            frame: .rowsToCurrent,
                          )
                          .divide(d('2'), scale: 0),
                    )
                    .many(),
              ).map((label, totals) => (label, totals.single)),
            )
            .get();
        expect(result, [('2', d('2')), ('4', d('4'))]);
      });

      if (backend == 'postgres') {
        test('volatile operands are evaluated exactly once each', () async {
          await db.entry.create(amount: d('1'), bucket: 'a');
          await db.execute(SqlCommand('CREATE SEQUENCE division_calls'));
          final next = sql<Decimal>(
            ["nextval('division_calls')::numeric"],
            [],
            Codecs.decimal,
          );
          expect(
            await db.entry
                .select((e) => next.divideExpression(next, scale: 2))
                .single(),
            d('.5'),
          );
          expect(
            (await db.execute(
              SqlCommand('SELECT last_value FROM division_calls'),
            )).rows.single.single,
            2,
          );
          expect(
            await db.entry.select((e) => next.rounded(0)).single(),
            d('3'),
          );
          expect(
            (await db.execute(
              SqlCommand('SELECT last_value FROM division_calls'),
            )).rows.single.single,
            3,
          );
          await db.entry.create(amount: d('1'), bucket: 'a');
          final windowed = await db.entry
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => e.amount
                    .sum()
                    .over(orderBy: [e.id.asc()], frame: .rowsToCurrent)
                    .divideExpression(next, scale: 2, rounding: .halfEven),
              )
              .get();
          expect(windowed, [d('.25'), d('.4')]);
          expect(
            (await db.execute(
              SqlCommand('SELECT last_value FROM division_calls'),
            )).rows.single.single,
            5,
          );
        });
      }
    }, tags: backend);
  }
}
