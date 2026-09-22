import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/temporal_precision/schema.orm.dart';

LocalTime t(String text) => LocalTime.parse(text);
LocalDateTime dt(String text) => LocalDateTime.parse(text);
DateTime instant(String text) => Codecs.dateTime.decode(text);

void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('temporal precision $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_temporal_precision_tests',
            ),
          );
          await db.execute(
            SqlCommand(
              'DROP SCHEMA IF EXISTS orm_temporal_precision_tests CASCADE',
            ),
          );
          await db.execute(
            SqlCommand('CREATE SCHEMA orm_temporal_precision_tests'),
          );
        }
      });
      tearDown(() => db.close());
      Future<void> create() => Migrator(db.sql).apply([
        Migration.create('0001_precision', appSchema, dialect: db.dialect),
      ]);
      Future<Moment> sample() => db.moment.create(
        clock: t('12:00:00.1235'),
        local: dt('1999-12-31 23:59:59.9995'),
        instant: instant('1999-12-31 23:59:59.5Z'),
      );

      test('generated writes, defaults and computed columns use database precision', () async {
        await create();
        final a = await sample();
        expect(a.clock, t('12:00:00.124'));
        expect(a.local, dt('1999-12-31 23:59:59.999'));
        expect(a.instant, instant('1999-12-31 23:59:59Z'));
        expect(a.optional, isNull);
        expect(a.defaulted, t('24:00'));
        expect(a.rounded, t('12:00'));
        await db.moment
            .byId(a.id)
            .patch(
              clock: Change.set(t('23:59:59.9995')),
              optional: Change.set(t('01:02:03.125')),
            );
        final updated = await db.moment.byId(a.id).single();
        expect(updated.clock, t('24:00'));
        expect(updated.optional, t('01:02:03.13'));
        await db.moment
            .byId(a.id)
            .update(
              (m) => [
                m.clock.setExpression(value(t('01:00:00.7775'), Codecs.time)),
              ],
            )
            .execute();
        expect((await db.moment.byId(a.id).single()).clock, t('01:00:00.778'));
        expect(await verifyColumns(db.sql, appSchema), isEmpty);
        final verified = await verifySchema(db.sql, SchemaSnapshot(appSchema));
        expect(verified.differences, isEmpty);
        expect(verified.unmanaged, isEmpty);
      });

      test(
        'SQL casts match all precisions on both sides of the PostgreSQL epoch',
        () async {
          await create();
          await sample();
          for (var p = 0; p <= 6; p++) {
            final unit = [1000000, 100000, 10000, 1000, 100, 10, 1][p];
            for (final offset in {
              0,
              unit ~/ 2,
              unit ~/ 2 + (p == 6 ? 0 : 1),
              unit - 1,
            }) {
              final time = LocalTime.fromMicroseconds(offset);
              final after = LocalDateTime(LocalDate(2000, 1, 1), time);
              final before = LocalDateTime(
                LocalDate(2000, 1, 1),
                LocalTime(0),
              ).add(Duration(microseconds: -offset));
              final expectedTicks = offset * 2 >= unit ? unit : 0;
              final expectedAfter = dt('2000-01-01 00:00')
                  .add(Duration(microseconds: expectedTicks));
              final expectedBefore = dt('2000-01-01 00:00')
                  .add(Duration(microseconds: -expectedTicks));
              final result = await db.moment
                  .select(
                    (_) => (
                      value(time, Codecs.time).withPrecision(p),
                      value(after, Codecs.localDateTime).withPrecision(p),
                      value(before, Codecs.localDateTime).withPrecision(p),
                      value(
                        instant('${before}Z'),
                        Codecs.dateTime,
                      ).withPrecision(p),
                    ).map((a, b, c, d) => (a, b, c, d)),
                  )
                  .single();
              expect(result, (
                LocalTime.fromMicroseconds(expectedTicks),
                expectedAfter,
                expectedBefore,
                instant('${expectedBefore}Z'),
              ));
              expect(time.withPrecision(p), result.$1);
              expect(after.withPrecision(p), result.$2);
              expect(before.withPrecision(p), result.$3);
              expect(instant('${before}Z').withPrecision(p), result.$4);
            }
          }
          final end = await db.moment
              .select(
                (_) =>
                    value(t('23:59:59.999999'), Codecs.time).withPrecision(0),
              )
              .single();
          expect(end, t('24:00'));
        },
      );

      test('nulls, CTE references, grouping, streams and wrong scopes retain type semantics', () async {
        await create();
        await sample();
        expect(
          await db.moment.select((m) => m.optional.withPrecision(0)).single(),
          isNull,
        );
        final cte = db.moment
            .select((m) => m.clock.withPrecision(0))
            .asCte('whole_seconds');
        expect(
          await cte.query
              .select((c) => c.ref((m) => m.clock.withPrecision(0)))
              .single(),
          t('12:00'),
        );
        expect(
          await db.moment
              .select((m) => m.clock.withPrecision(0))
              .stream(batchSize: 1)
              .single,
          t('12:00'),
        );
        expect(
          await db.moment
              .groupBy((m) => [m.clock.withPrecision(0)])
              .select(
                (m) => (
                  m.clock.withPrecision(0),
                  m.id.count(),
                ).map((time, n) => (time, n)),
              )
              .single(),
          (t('12:00'), 1),
        );
        expect(
          () => db.moment
              .groupBy((m) => [m.clock])
              .select((m) => m.clock.withPrecision(0))
              .compile(),
          returnsNormally,
        );
        expect(
          () => db.moment
              .groupBy((m) => [m.clock.withPrecision(1)])
              .select((m) => m.clock.withPrecision(0))
              .compile(),
          throwsA(isA<OrmException>()),
        );
      });

      test('rounded keys work in batch writes, upserts and foreign-key relation loading', () async {
        await create();
        await db.slot.insertMany([
          '01:00:00.1235',
          '02:00:00.1235',
        ], (s, v) => [s.time.set(t(v)), s.label.set(v)]).execute();
        final booking = await db.booking.create(time: t('01:00:00.1239'));
        final related = await db.booking
            .byId(booking.id)
            .select((b) => b.slot.select((s) => s.label).one())
            .single();
        expect(related, '01:00:00.1235');
        await expectLater(
          db.slot.insertMany([
            '03:00:00.1235',
            '01:00:00.1236',
          ], (s, v) => [s.time.set(t(v)), s.label.set(v)]).execute(),
          throwsA(isA<SqlFailure>()),
        );
        expect(await db.slot.count(), 2);
        await db.slot
            .insert(
              (s) => [s.time.set(t('01:00:00.1238')), s.label.set('updated')],
            )
            .onConflictUpdate(
              target: (s) => [s.time],
              set: (existing, incoming) => [
                existing.label.setExpression(incoming.label),
              ],
            )
            .execute();
        expect(
          await db.slot.byId(t('01:00:00.124')).select((s) => s.label).single(),
          'updated',
        );
      });

      test(
        'catalog import preserves precision, defaults and computed expressions',
        () async {
          await create();
          await sample();
          final info = await inspectColumns(db.sql, 'moments');
          expect(
            {for (final c in info) c.name: c.temporalPrecision},
            {
              'id': null,
              'clock': 3,
              'local': 3,
              'instant': 0,
              'optional': 2,
              'defaulted': 3,
              'rounded': 0,
            },
          );
          final draft = await importSchema(
            db.sql,
            tables: ['moments', 'slots', 'bookings'],
          );
          expect(draft.issues.where((i) => i.blocking), isEmpty);
          expect(draft.dart, contains('precision: 3'));
          final dir = await Directory(
            '.dart_tool/temporal-precision-import-$backend',
          ).create(recursive: true);
          try {
            final file = File('${dir.path}/schema.dart');
            await file.writeAsString(draft.dart);
            final generated = await generateSchema(file.path);
            final verification = await verifySchema(db.sql, generated.snapshot);
            expect(verification.differences, isEmpty);
            expect(verification.unmanaged, isEmpty);
          } finally {
            await dir.delete(recursive: true);
          }
        },
      );

      test('narrowing precision requires a reviewed conversion and duplicate-key failure rolls back history', () async {
        TableSchema schema(int? p, {String column = 'stamp'}) => TableSchema(
          'narrow',
          columns: [
            Column('id', Codecs.integer),
            Column(column, Codecs.localDateTime, temporalPrecision: p),
          ],
          primaryKey: ['id'],
          uniqueKeys: [
            [column],
          ],
        );
        final first = Migration.create('0001_before', [
          schema(6),
        ], dialect: db.dialect);
        final oldChecksum = first.checksum;
        await Migrator(db.sql).apply([first]);
        await db.execute(
          SqlCommand(
            "INSERT INTO narrow VALUES (1,'2024-01-01 00:00:00.1231'),(2,'2024-01-01 00:00:00.1232')",
          ),
        );
        expect(
          () => Migration.diff(
            '0002_missing',
            from: first.snapshot!,
            to: SchemaSnapshot([schema(3)]),
            previous: first.checksum,
            dialect: db.dialect,
          ),
          throwsA(isA<OrmException>()),
        );
        final next = Migration.diff(
          '0002_narrow',
          from: first.snapshot!,
          to: SchemaSnapshot([schema(3, column: 'recorded')]),
          previous: first.checksum,
          renames: const SchemaRenames(
            columns: {
              'narrow': {'stamp': 'recorded'},
            },
          ),
          using: {
            'narrow': {'recorded': 'recorded'},
          },
          dialect: db.dialect,
        );
        await expectLater(
          Migrator(db.sql).apply([first, next]),
          throwsA(isA<SqlFailure>()),
        );
        expect((await Migrator(db.sql).history()).length, 1);
        expect(
          (await verifySchema(db.sql, first.snapshot!)).differences,
          isEmpty,
        );
        expect(first.checksum, oldChecksum);
        await db.execute(SqlCommand('DELETE FROM narrow WHERE id=2'));
        await Migrator(db.sql).apply([first, next]);
        expect(
          (await verifySchema(db.sql, next.snapshot!)).differences,
          isEmpty,
        );
        final row = await db.execute(SqlCommand('SELECT recorded FROM narrow'));
        expect(
          Codecs.localDateTime.decode(row.rows.single.single),
          dt('2024-01-01 00:00:00.123'),
        );
        final wrong = SchemaSnapshot([schema(2, column: 'recorded')]);
        expect(
          (await verifySchema(db.sql, wrong)).differences.join(),
          contains('precision'),
        );
        expect(
          (await verifyColumns(db.sql, wrong.tables)).join(),
          contains('precision'),
        );
      });

      test(
        'timestamp defaults and explicit six-digit catalogs retain precision',
        () async {
          final table = TableSchema(
            'defaults',
            columns: [
              Column(
                'stamp',
                Codecs.localDateTime,
                temporalPrecision: 3,
                defaultSql: "'1999-12-31 23:59:59.9995'",
              ),
              Column(
                'instant',
                Codecs.dateTime,
                temporalPrecision: 0,
                defaultSql: "'2000-01-01 07:59:59.5+08'",
              ),
            ],
          );
          await Migrator(db.sql).apply([
            Migration.create('0001_defaults', [table], dialect: db.dialect),
          ]);
          await db.execute(SqlCommand('INSERT INTO defaults DEFAULT VALUES'));
          final row = (await db.execute(SqlCommand('SELECT * FROM defaults')))
              .rows
              .single;
          expect(
            Codecs.localDateTime.decode(row[0]),
            dt('1999-12-31 23:59:59.999'),
          );
          expect(
            Codecs.dateTime.decode(row[1]),
            instant('1999-12-31 23:59:59Z'),
          );
          expect(
            (await verifySchema(db.sql, SchemaSnapshot([table]))).differences,
            isEmpty,
          );
          if (backend == 'postgres') {
            await db.execute(
              SqlCommand(
                'CREATE TABLE explicit_six (clock TIME(6) WITHOUT TIME ZONE, stamp TIMESTAMP(6) WITHOUT TIME ZONE, instant TIMESTAMPTZ(6))',
              ),
            );
            final expected = TableSchema(
              'explicit_six',
              columns: [
                Column('clock', Codecs.time.nullable(), nullable: true),
                Column(
                  'stamp',
                  Codecs.localDateTime.nullable(),
                  nullable: true,
                ),
                Column('instant', Codecs.dateTime.nullable(), nullable: true),
              ],
            );
            expect(await verifyColumns(db.sql, [expected]), isEmpty);
            expect(
              (await verifySchema(
                db.sql,
                SchemaSnapshot([expected]),
              )).differences,
              isEmpty,
            );
            final draft = await importSchema(db.sql, tables: ['explicit_six']);
            expect(draft.issues.where((i) => i.blocking), isEmpty);
            expect(draft.dart, isNot(contains('precision:')));
          }
        },
      );

      test(
        'extended timestamps round in SQL without total-microsecond overflow',
        () async {
          await create();
          await sample();
          for (final text in [
            '0001-01-01 00:00:00.0005 BC',
            '294276-12-31 23:59:59.999499',
          ]) {
            final original = dt(text);
            expect(
              await db.moment
                  .select(
                    (_) =>
                        value(original, Codecs.localDateTime).withPrecision(3),
                  )
                  .single(),
              original.withPrecision(3),
            );
          }
          final upper = instant('275760-09-12 23:59:59.999999+00');
          expect(
            await db.moment
                .select((_) => value(upper, Codecs.dateTime).withPrecision(0))
                .single(),
            DateTime.utc(275760, 9, 13),
          );
        },
      );

      test(
        'raw SQL respects native or managed precision constraints',
        () async {
          await create();
          if (backend == 'sqlite') {
            await expectLater(
              db.execute(
                SqlCommand("INSERT INTO slots VALUES ('01:00:00.1234','raw')"),
              ),
              throwsA(isA<SqlFailure>()),
            );
            await expectLater(
              db.execute(SqlCommand("INSERT INTO slots VALUES ('bad','raw')")),
              throwsA(isA<SqlFailure>()),
            );
          } else {
            await db.execute(
              SqlCommand("INSERT INTO slots VALUES ('01:00:00.1234','raw')"),
            );
            expect((await db.slot.single()).time, t('01:00:00.123'));
          }
        },
      );
    }, tags: backend);
  }

  test('value rounding keeps extended ranges and rejects overflow/invalid precision', () {
    expect(
      dt('0001-01-01 00:00:00.0005 BC').withPrecision(3),
      dt('0001-01-01 00:00:00 BC'),
    );
    expect(
      dt('294276-12-31 23:59:59.999499').withPrecision(3),
      dt('294276-12-31 23:59:59.999'),
    );
    expect(
      () => dt('294276-12-31 23:59:59.9995').withPrecision(3),
      throwsRangeError,
    );
    for (final p in [-1, 7]) {
      expect(() => t('12:00').withPrecision(p), throwsRangeError);
      expect(() => dt('2000-01-01 00:00').withPrecision(p), throwsRangeError);
      expect(() => DateTime.utc(2000).withPrecision(p), throwsRangeError);
      expect(
        () => value(t('12:00'), Codecs.time).withPrecision(p),
        throwsRangeError,
      );
    }
    expect(
      DateTime.utc(275760, 9, 13).withPrecision(0),
      DateTime.utc(275760, 9, 13),
    );
  });

  test('default and explicit six preserve historical snapshots and migration checksums', () {
    TableSchema schema(int? p) => TableSchema(
      'old',
      columns: [Column('clock', Codecs.time, temporalPrecision: p)],
    );
    final before = Migration.create('0001_legacy', [
          schema(null),
        ], dialect: SqlDialect.sqlite),
        after = Migration.create('0001_legacy', [
          schema(6),
        ], dialect: SqlDialect.sqlite);
    expect(before.checksum, after.checksum);
    expect(
      jsonEncode(before.snapshot!.toJson()),
      jsonEncode(after.snapshot!.toJson()),
    );
    for (final d in SqlDialect.values) {
      expect(
        createSchema([schema(null)], d).map((c) => c.sql),
        createSchema([schema(6)], d).map((c) => c.sql),
      );
    }
    for (final column in [
      Column('c', Codecs.time, temporalPrecision: 7),
      Column('c', Codecs.date, temporalPrecision: 3),
      Column('c', Codecs.text, temporalPrecision: 3),
    ]) {
      expect(
        () => createSchema([
          TableSchema('invalid', columns: [column]),
        ], .sqlite),
        throwsA(isA<OrmException>()),
      );
    }
  });

  test('generator rejects invalid precision declarations and preserves generated fixture metadata', () async {
    final generated = await generateSchema(
      'test/support/temporal_precision/schema.dart',
    );
    expect(
      generated.dart,
      File('test/support/temporal_precision/schema.orm.dart')
          .readAsStringSync(),
    );
    expect(
      generated.snapshotDart,
      File('test/support/temporal_precision/schema.snapshot.dart')
          .readAsStringSync(),
    );
    final dir = await Directory('.dart_tool/temporal-precision-invalid')
        .create(recursive: true);
    try {
      final file = File('${dir.path}/schema.dart');
      for (final field in [
        't: time(precision: -1)',
        't: localDateTime(precision: 7)',
        't: custom(Codecs.date, precision: 3)',
        't: custom(Codecs.text, precision: 3)',
        't: dateTime(precision: 3, precision: 2)',
      ]) {
        await file.writeAsString(
          "import 'package:orm/schema.dart'; final row=model('rows', ($field,));",
        );
        await expectLater(
          generateSchema(file.path),
          throwsA(isA<GenerationException>()),
        );
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
