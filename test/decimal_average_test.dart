import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/decimals/schema.orm.dart';

Decimal d(String text) => Decimal.parse(text);

void main() {
  test('integer fractions round once and only bound their final result', () {
    final huge = BigInt.from(10).pow(131072);
    expect(
      Decimal.fromFraction(huge, BigInt.from(10), scale: 0),
      d('1e131071'),
    );
    expect(
      Decimal.fromFraction(
        BigInt.from(469),
        BigInt.from(200),
        scale: 2,
        rounding: .halfEven,
      ),
      d('2.34'),
    );
    expect(
      Decimal.fromFraction(
        BigInt.from(-469),
        BigInt.from(200),
        scale: 2,
        rounding: .floor,
      ),
      d('-2.35'),
    );
    expect(
      () => Decimal.fromFraction(BigInt.one, BigInt.zero, scale: 0),
      throwsUnsupportedError,
    );
    expect(
      () => Decimal.fromFraction(BigInt.one, BigInt.from(3), scale: 2),
      throwsFormatException,
    );
  });
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('decimal average $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_decimal_average_tests',
            ),
          );
          await db.execute(
            SqlCommand(
              'DROP SCHEMA IF EXISTS orm_decimal_average_tests CASCADE',
            ),
          );
          await db.execute(
            SqlCommand('CREATE SCHEMA orm_decimal_average_tests'),
          );
        }
        await Migrator(db).apply([
          Migration.create('0001_average', appSchema, dialect: db.dialect),
        ]);
      });
      tearDown(() => db.close());
      Future<void> rows(List<String> values, {String bucket = 'a'}) async {
        for (final v in values) {
          await db.entries.create(amount: d(v), bucket: bucket);
        }
      }

      test(
        'empty null and constant inputs retain aggregate semantics',
        () async {
          expect(
            await db.entries.select((e) => e.amount.average(scale: 2)).single(),
            null,
          );
          expect(
            await db.entries
                .select((e) => value(d('2'), Codecs.decimal).average(scale: 2))
                .single(),
            null,
          );
          await rows(['1', '2', '3']);
          expect(
            await db.entries.select((e) => e.amount.average(scale: 2)).single(),
            d('2'),
          );
          expect(
            await db.entries.select((e) => e.fee.average(scale: 2)).single(),
            null,
          );
          expect(
            await db.entries
                .select((e) => value(d('2'), Codecs.decimal).average(scale: 2))
                .single(),
            d('2'),
          );
          await db.entries.byId(2).patch(fee: Change.set(d('4')));
          expect(
            await db.entries.select((e) => e.fee.average(scale: 2)).single(),
            d('4'),
          );
        },
      );

      test(
        'all rounding modes match exact signed sums across scales',
        () async {
          for (final values in [
            ['2.34', '2.35'],
            ['-2.34', '-2.35'],
            ['1e20', '-1'],
            ['-1e20', '1'],
            ['1', '0', '0'],
            ['1250', '1450'],
            ['-1250', '-1450'],
          ]) {
            await db.entries.delete().execute();
            await rows(values);
            final sum = values.map(d).reduce((a, b) => a + b);
            for (final mode in DecimalRounding.values) {
              for (final scale in [-2, 0, 2, 30]) {
                Decimal? expected;
                try {
                  expected = sum.divide(
                    d('${values.length}'),
                    scale: scale,
                    rounding: mode,
                  );
                } on FormatException {
                  /* Exact mode intentionally rejects rounding. */
                }
                final result = db.entries
                    .select(
                      (e) => e.amount.average(scale: scale, rounding: mode),
                    )
                    .single();
                if (expected == null) {
                  await expectLater(result, throwsA(isA<SqlFailure>()));
                } else {
                  expect(
                    await result,
                    expected,
                    reason: '$values $scale $mode',
                  );
                }
              }
            }
          }
        },
      );

      test(
        'valid means survive sums exceeding the finite numeric range',
        () async {
          await rows(['9e131071', '9e131071']);
          await expectLater(
            db.entries.select((e) => e.amount.sum()).single(),
            throwsA(isA<Exception>()),
          );
          expect(
            await db.entries.select((e) => e.amount.average(scale: 0)).single(),
            d('9e131071'),
          );
          await db.entries.delete().execute();
          await rows(['9e131071', '-9e131071', '1']);
          final actual = await db.entries
              .select(
                (e) => e.amount.average(scale: 16383, rounding: .halfEven),
              )
              .single();
          expect(
            actual == d('1').divide(d('3'), scale: 16383, rounding: .halfEven),
            isTrue,
          );
          await db.entries.delete().execute();
          await rows(['-9e131071', '-9e131071']);
          expect(
            await db.entries.select((e) => e.amount.average(scale: 0)).single(),
            d('-9e131071'),
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'minimum fractions and outermost rounding scales stay exact',
        () async {
          await rows(['1e-16383', '0']);
          expect(
            await db.entries
                .select(
                  (e) => e.amount.average(scale: 16383, rounding: .halfEven),
                )
                .single(),
            d('0'),
          );
          expect(
            await db.entries
                .select(
                  (e) => e.amount.average(
                    scale: 16383,
                    rounding: .halfAwayFromZero,
                  ),
                )
                .single(),
            d('1e-16383'),
          );
          await db.entries.delete().execute();
          await rows(['5e131071', '5e131071']);
          expect(
            await db.entries
                .select(
                  (e) => e.amount.average(scale: -131072, rounding: .halfEven),
                )
                .single(),
            d('0'),
          );
          await expectLater(
            db.entries
                .select(
                  (e) => e.amount.average(
                    scale: -131072,
                    rounding: .halfAwayFromZero,
                  ),
                )
                .single(),
            throwsA(isA<SqlFailure>()),
          );
        },
      );

      test(
        'grouping HAVING ordering and CTE references preserve the mean',
        () async {
          await rows(['1', '2'], bucket: 'a');
          await rows(['2', '3'], bucket: 'b');
          final grouped = db.entries
              .groupBy((e) => [e.bucket])
              .having((e) => e.amount.average(scale: 1).gt(d('2')))
              .orderBy((e) => [e.amount.average(scale: 1).desc()])
              .select((e) => (e.bucket, e.amount.average(scale: 1)).row);
          expect(await grouped.get(), [('b', d('2.5'))]);
          final cte = grouped.asCte('means');
          expect(
            await cte.query
                .where(
                  (e) => e.ref((o) => o.amount.average(scale: 1)).lt(d('3')),
                )
                .get(),
            [('b', d('2.5'))],
          );
          expect(await grouped.union(grouped).get(), [('b', d('2.5'))]);
          final unique = db.entries
              .select((e) => e.amount)
              .distinct()
              .asCte('unique_amounts');
          expect(
            await unique.query
                .select((e) => e.ref((o) => o.amount).average(scale: 1))
                .single(),
            d('2'),
          );
        },
      );

      test(
        'illegal window nesting and aggregate assignments fail before SQL',
        () {
          expect(
            () => db.entries.select(
              (e) => e.amount.sum().over().average(scale: 2),
            ),
            throwsA(
              isA<OrmException>().having((e) => e.code, 'code', 'QUERY.WINDOW'),
            ),
          );
          expect(
            () => db.entries.select(
              (e) => e.amount
                  .average(scale: 2)
                  .over(orderBy: [e.amount.sum().over().asc()]),
            ),
            throwsA(
              isA<OrmException>().having((e) => e.code, 'code', 'QUERY.WINDOW'),
            ),
          );
          expect(
            () => db.entries
                .update(
                  (e) => [e.fee.setExpression(e.amount.average(scale: 2))],
                )
                .compile(),
            throwsA(
              isA<OrmException>().having(
                (e) => e.code,
                'code',
                'QUERY.AGGREGATE',
              ),
            ),
          );
        },
      );

      test(
        'windows and rounded window means respect partitions and pagination',
        () async {
          await rows(['1', '2', '3']);
          await rows(['10', '20'], bucket: 'b');
          Expr<Decimal?> mean(EntriesFields e) => e.amount
              .average(scale: 2)
              .over(
                partitionBy: [e.bucket],
                orderBy: [e.id.asc()],
                frame: .rowsToCurrent,
              );
          expect(
            await db.entries.orderBy((e) => [e.id.asc()]).select(mean).get(),
            ['1', '1.5', '2', '10', '15'].map(d),
          );
          expect(
            await db.entries
                .orderBy((e) => [mean(e).desc()])
                .select(mean)
                .skip(1)
                .take(2)
                .get(),
            [d('10'), d('2')],
          );
          expect(
            await db.entries
                .where((e) => e.bucket.eq('a'))
                .orderBy((e) => [e.id.asc()])
                .select((e) => mean(e).rounded(0, rounding: .halfEven))
                .get(),
            [d('1'), d('2'), d('2')],
          );
          final cte = db.entries.select(mean).asCte('running_means');
          expect(await cte.query.where((e) => e.ref(mean).gt(d('10'))).get(), [
            d('15'),
          ]);
          expect(
            await db.entries
                .orderBy((e) => [e.id.asc()])
                .select(mean)
                .stream()
                .toList(),
            ['1', '1.5', '2', '10', '15'].map(d),
          );
          final mixed = await db.entries
              .where((e) => e.bucket.eq('a'))
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => (
                  mean(e),
                  e.amount.sum().over(
                    orderBy: [e.id.asc()],
                    frame: .rowsToCurrent,
                  ),
                ).row,
              )
              .get();
          expect(mixed, [
            (d('1'), d('1')),
            (d('1.5'), d('3')),
            (d('2'), d('6')),
          ]);
          Expr<Decimal?> complete(EntriesFields e) =>
              e.amount.average(scale: 1).over(frame: .rowsAll);
          expect(
            await db.entries
                .where((e) => e.bucket.eq('a'))
                .orderBy((e) => [complete(e).asc()])
                .select(complete)
                .distinct()
                .get(),
            [d('2')],
          );
        },
      );

      test('correlated means can update values and failures roll back transactions', () async {
        await rows(['1', '2'], bucket: 'a');
        await rows(['1', '0', '0'], bucket: 'b');
        final source = db.entries;
        await db.entries
            .where((e) => e.bucket.eq('a'))
            .update(
              (e) => [
                e.fee.setExpression(
                  source
                      .where((s) => s.bucket.equals(e.bucket))
                      .select((s) => s.amount.average(scale: 1))
                      .scalar(),
                ),
              ],
            )
            .execute();
        expect(
          await db.entries
              .where((e) => e.bucket.eq('a'))
              .select((e) => e.fee)
              .get(),
          [d('1.5'), d('1.5')],
        );
        await expectLater(
          db.transaction((tx) async {
            await tx.entries
                .where((e) => e.bucket.eq('a'))
                .patch(fee: Change.set(d('99')));
            await tx.entries
                .where((e) => e.bucket.eq('b'))
                .select((e) => e.amount.average(scale: 1))
                .single();
          }),
          throwsA(isA<SqlFailure>()),
        );
        expect(
          await db.entries
              .where((e) => e.bucket.eq('a'))
              .select((e) => e.fee)
              .get(),
          [d('1.5'), d('1.5')],
        );
      });

      test('batched relationship windows keep per-parent limits', () async {
        for (final n in ['2', '4']) {
          await db.rates.create(id: d(n), label: n);
          for (var i = 0; i < 3; i++) {
            await db.allocations.create(rateId: d(n));
          }
        }
        expect(
          await db.rates
              .orderBy((r) => [r.id.asc()])
              .select(
                (r) => (
                  r.label,
                  r.allocations
                      .orderBy((a) => [a.id.desc()])
                      .take(1)
                      .select(
                        (a) => a.rateId
                            .average(scale: 1)
                            .over(
                              partitionBy: [a.rateId],
                              orderBy: [a.id.asc()],
                              frame: .rowsToCurrent,
                            ),
                      )
                      .many(),
                ).map((label, means) => (label, means.single)),
              )
              .get(),
          [('2', d('2')), ('4', d('4'))],
        );
      });

      if (backend == 'sqlite') {
        test('sliding windows remove values, reset empty frames and reject varying policies', () async {
          for (final fee in ['1', null, '3', null, null]) {
            await db.entries.create(
              amount: d('0'),
              fee: fee == null ? null : d(fee),
              bucket: 'a',
            );
          }
          final result = await db.execute(
            SqlCommand(
              'SELECT orm_decimal_avg_v1(fee, 2, 5) OVER (ORDER BY id ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) FROM entries ORDER BY id',
            ),
          );
          expect(
            result.rows.map(
              (r) => r.single == null ? null : Codecs.decimal.decode(r.single),
            ),
            [d('1'), d('1'), d('3'), d('3'), null],
          );
          await expectLater(
            db.execute(
              SqlCommand(
                'SELECT orm_decimal_avg_v1(amount, id, 5) FROM entries',
              ),
            ),
            throwsA(isA<SqlFailure>()),
          );
        });
      }

      test('window means of grouped sums run after HAVING', () async {
        await rows(['1', '3'], bucket: 'a');
        await rows(['6'], bucket: 'b');
        await rows(['100'], bucket: 'excluded');
        expect(
          await db.entries
              .groupBy((e) => [e.bucket])
              .having((e) => e.amount.sum().lt(d('50')))
              .orderBy((e) => [e.bucket.asc()])
              .select(
                (e) => (
                  e.bucket,
                  e.amount
                      .sum()
                      .average(scale: 1)
                      .over(orderBy: [e.bucket.asc()], frame: .rowsToCurrent),
                ).row,
              )
              .get(),
          [('a', d('4')), ('b', d('5'))],
        );
      });

      if (backend == 'postgres') {
        test(
          'volatile inputs and window ordering are evaluated once per row',
          () async {
            await rows(['1', '2', '3']);
            await db.execute(SqlCommand('CREATE SEQUENCE average_calls'));
            final next = sql(
              ["nextval('average_calls')::numeric"],
              [],
              Codecs.decimal,
            );
            expect(
              await db.entries.select((e) => next.average(scale: 1)).single(),
              d('2'),
            );
            expect(
              (await db.execute(
                SqlCommand('SELECT last_value FROM average_calls'),
              )).rows.single.single,
              3,
            );
            expect(
              await db.entries
                  .orderBy((e) => [e.id.asc()])
                  .select(
                    (e) => next
                        .average(scale: 1)
                        .over(orderBy: [e.id.asc()], frame: .rowsToCurrent),
                  )
                  .get(),
              [d('4'), d('4.5'), d('5')],
            );
            expect(
              (await db.execute(
                SqlCommand('SELECT last_value FROM average_calls'),
              )).rows.single.single,
              6,
            );
            expect(
              await db.entries
                  .select(
                    (e) => e.amount
                        .average(scale: 1)
                        .over(orderBy: [next.asc()], frame: .rowsToCurrent),
                  )
                  .get(),
              [d('1'), d('1.5'), d('2')],
            );
            expect(
              (await db.execute(
                SqlCommand('SELECT last_value FROM average_calls'),
              )).rows.single.single,
              9,
            );
            final repeated = db.entries
                .select((e) => e.bucket)
                .asCte('repeated_anchors');
            expect(
              await repeated.query
                  .select((e) => next.average(scale: 1))
                  .single(),
              d('11'),
            );
            expect(
              (await db.execute(
                SqlCommand('SELECT last_value FROM average_calls'),
              )).rows.single.single,
              12,
            );
            expect(
              await db.entries
                  .where((e) => e.id.lt(0))
                  .select((e) => next.average(scale: 1))
                  .single(),
              null,
            );
            expect(
              (await db.execute(
                SqlCommand('SELECT last_value FROM average_calls'),
              )).rows.single.single,
              12,
            );
          },
        );
      }
    });
  }
}
