import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';

import 'support/temporals/schema.orm.dart';
import 'support/temporals/schema.snapshot.dart' as physical;

void main() {
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    for (final enabled in [false, true]) {
      test(
        'borrowed PostgreSQL pool local calendar capability: $enabled',
        () async {
          final uri = Uri.parse(url);
          final pool = pg.Pool<void>.withEndpoints(
            [
              pg.Endpoint(
                host: uri.host,
                port: uri.port,
                database: uri.pathSegments.single,
                username: uri.userInfo.split(':').first,
              ),
            ],
            settings: pg.PoolSettings(
              sslMode: pg.SslMode.disable,
              maxConnectionCount: 1,
              typeRegistry: enabled ? postgresTypeRegistry() : null,
            ),
          );
          final db = Database(PostgresDriver.borrow(pool, temporal: enabled));
          try {
            if (!enabled) {
              expect(
                () => db.appointments.select((a) => a.day).compile(),
                throwsA(
                  isA<OrmException>().having(
                    (e) => e.code,
                    'code',
                    'CAPABILITY.TEMPORAL',
                  ),
                ),
              );
            } else {
              await db.session((session) async {
                await session.execute(
                  SqlCommand(
                    'CREATE TEMPORARY TABLE appointments (id BIGINT, day DATE, time TIME WITHOUT TIME ZONE, starts TIMESTAMP WITHOUT TIME ZONE)',
                  ),
                );
                await session.execute(
                  SqlCommand(
                    "INSERT INTO appointments VALUES (1, '5874897-12-31', '24:00', '294276-12-31 23:59:59.999999')",
                  ),
                );
                final row = await session.appointments.single();
                expect(row.day, LocalDate(5874897, 12, 31));
                expect(row.time, LocalTime(24));
                expect(
                  row.starts,
                  LocalDateTime.parse('294276-12-31 23:59:59.999999'),
                );
              });
            }
            await db.close();
            expect((await pool.execute('SELECT 7')).single.single, 7);
          } finally {
            await db.close();
            await pool.close();
          }
        },
      );
    }
  }

  test('Gregorian cycles, era boundaries and full finite date range', () {
    expect(LocalDate(-4713, 11, 24).julianDay, 0);
    expect(LocalDate(5874897, 12, 31).julianDay, LocalDate.maxJulianDay);
    expect(LocalDate(2000, 1, 1).julianDay, 2451545);
    expect(LocalDate(1970, 1, 1).julianDay, 2440588);
    expect(LocalDate(0, 12, 31).addDays(1), LocalDate(1, 1, 1));
    expect(LocalDate.parse('0001-01-01 BC'), LocalDate(0, 1, 1));
    expect(LocalDate.parse('-0001-01-01'), LocalDate(-1, 1, 1));
    expect(LocalDate(0, 2, 28).addDays(1), LocalDate(0, 2, 29));
    expect(LocalDate(1900, 2, 28).addDays(1), LocalDate(1900, 3, 1));
    final random = Random(194);
    for (var i = 0; i < 10000; i++) {
      final ordinal = random.nextInt(LocalDate.maxJulianDay + 1);
      final date = LocalDate.fromJulianDay(ordinal);
      expect(LocalDate(date.year, date.month, date.day).julianDay, ordinal);
      expect(LocalDate.parse(date.toString()), date);
    }
    for (var i = -150000; i < 150000; i += 53) {
      final expected = DateTime.utc(2000).add(Duration(days: i));
      expect(
        LocalDate.fromJulianDay(2451545 + i),
        LocalDate(expected.year, expected.month, expected.day),
      );
    }
    expect(() => LocalDate(-4713, 11, 23), throwsRangeError);
    expect(() => LocalDate(5874898, 1, 1), throwsRangeError);
    expect(() => LocalDate(2025, 2, 29), throwsRangeError);
    expect(
      () => LocalDate(2000, 1, 1).addDays(9223372036854775807),
      throwsRangeError,
    );
    expect(LocalDate.tryParse('2024-13-01'), null);
    expect(LocalDate.tryParse('2024-01-01Z'), null);
    expect(LocalDate.tryParse('2024-01-01\n'), null);
  });

  test('local time precision, day endpoint and timestamp arithmetic', () {
    expect(LocalTime.parse('12:34'), LocalTime(12, 34));
    expect(LocalTime.parse('12:34:56.000001').microsecond, 1);
    expect(LocalTime(24).microseconds, 86400000000);
    expect(LocalTime(24).compareTo(LocalTime(0)), greaterThan(0));
    expect(LocalTime.tryParse('24:00:00.000001'), null);
    expect(LocalTime.tryParse('12:00:60'), null);
    expect(LocalTime.tryParse('12:00:00.0000001'), null);
    expect(LocalTime.tryParse('12:00:00+08:00'), null);
    final midnight = LocalDateTime.parse('0001-01-01 00:00');
    expect(
      midnight.add(const Duration(microseconds: -1)),
      LocalDateTime.parse('0001-12-31 23:59:59.999999 BC'),
    );
    expect(
      midnight
          .add(const Duration(microseconds: -1))
          .add(const Duration(microseconds: 1)),
      midnight,
    );
    expect(
      LocalDateTime.parse('2024-02-29T24:00'),
      LocalDateTime.parse('2024-03-01 00:00'),
    );
    expect(LocalDateTime.tryParse('2024-01-01 00:00Z'), null);
    expect(LocalDateTime.tryParse('294276-12-31 24:00'), null);
    expect(
      () =>
          LocalDateTime.parse('4714-11-24 00:00 BC')
              .add(const Duration(microseconds: -1)),
      throwsRangeError,
    );
    expect(() => Codecs.date.decode(DateTime.utc(2024)), throwsFormatException);
    expect(
      () => Codecs.localDateTime.decode(DateTime.utc(2024)),
      throwsFormatException,
    );
  });

  test(
    'PostgreSQL binary registry covers boundaries without DateTime',
    () async {
      final registry = postgresTypeRegistry();
      final context = pg.CodecContext.withDefaults(typeRegistry: registry);
      // Use the public registry API; no dependency on private driver internals.
      final limits = [-211813488000000000, -1, 0, 9223371331199999999];
      for (final ticks in limits) {
        final data = ByteData(8)..setInt64(0, ticks);
        final decoded = await registry.decode(
          pg.EncodedValue.binary(
            data.buffer.asUint8List(),
            typeOid: pg.Type.timestampWithoutTimezone.oid,
          ),
          context,
        );
        expect(decoded, isA<LocalDateTime>());
      }
    },
  );

  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('local temporal $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_temporal_tests',
            ),
          );
          await db.execute(
            SqlCommand('DROP SCHEMA IF EXISTS orm_temporal_tests CASCADE'),
          );
          await db.execute(SqlCommand('CREATE SCHEMA orm_temporal_tests'));
        }
      });
      tearDown(() => db.close());
      Future<void> create() => Migrator(
        db.sql,
      ).apply([Migration.create('0001_local', appSchema, dialect: db.dialect)]);

      if (backend == 'postgres') {
        test(
          'catalog retains time-truncating casts in expression defaults',
          () async {
            final schema = TableSchema(
              'defaults',
              columns: [
                Column(
                  'moment',
                  Codecs.localDateTime,
                  defaultSql: 'CURRENT_TIMESTAMP',
                ),
              ],
            );
            final first = Migration.create('0001_default', [
              schema,
            ], dialect: db.dialect);
            await Migrator(db.sql).apply([first]);
            expect(
              (await verifySchema(db.sql, first.snapshot!)).differences,
              isEmpty,
            );
            await db.execute(
              SqlCommand(
                'ALTER TABLE defaults ALTER COLUMN moment SET DEFAULT (CURRENT_TIMESTAMP)::date',
              ),
            );
            expect(
              (await verifySchema(db.sql, first.snapshot!)).differences,
              contains('defaults.moment default differs'),
            );
          },
        );
      }

      test(
        'generated writes, defaults, null patches and typed parameters',
        () async {
          await create();
          final day = LocalDate(2024, 2, 29);
          final row = await db.appointments.create(day: day);
          expect(row, (
            id: row.id,
            day: day,
            time: LocalTime(12, 30),
            starts: null,
          ));
          final stamp = LocalDateTime.parse('2024-02-29 12:34:56.000001');
          await db.appointments.byId(row.id).patch(starts: Change.set(stamp));
          expect((await db.appointments.byId(row.id).single()).starts, stamp);
          expect(
            await db.appointments
                .select(
                  (a) => (
                    value(day, Codecs.date),
                    value(LocalTime(24), Codecs.time),
                    value(stamp, Codecs.localDateTime),
                  ).row,
                )
                .single(),
            (day, LocalTime(24), stamp),
          );
          await db.appointments
              .byId(row.id)
              .patch(starts: const Change.set(null));
          expect((await db.appointments.single()).starts, null);
        },
      );

      test(
        'finite extremes and microseconds survive native rows and streams',
        () async {
          await create();
          final dates = [
            LocalDate.fromJulianDay(0),
            LocalDate(0, 1, 1),
            LocalDate(10000, 1, 1),
            LocalDate.fromJulianDay(LocalDate.maxJulianDay),
          ];
          final stamps = [
            LocalDateTime.parse('4714-11-24 00:00 BC'),
            LocalDateTime.parse('0001-12-31 23:59:59.999999 BC'),
            LocalDateTime.parse('2000-01-01 00:00:00.000001'),
            LocalDateTime.parse('294276-12-31 23:59:59.999999'),
          ];
          for (var i = 0; i < dates.length; i++) {
            final time = i == 3 ? LocalTime(24) : LocalTime(0, 0, 0, i);
            expect(
              (await db.appointments.create(
                day: dates[i],
                time: Change.set(time),
                starts: stamps[i],
              )).starts,
              stamps[i],
            );
          }
          final query = db.appointments.orderBy((a) => [a.id.asc()]);
          expect((await query.get()).map((a) => a.day), dates);
          expect(
            (await query.stream(batchSize: 1).toList()).map((a) => a.starts),
            stamps,
          );
          if (backend == 'postgres') {
            await db.session((s) async {
              await s.execute(SqlCommand("SET DateStyle TO 'SQL, DMY'"));
              await s.execute(SqlCommand("SET TIME ZONE 'Pacific/Auckland'"));
              expect(
                (await s.appointments.orderBy((a) => [a.id.asc()]).get()).map(
                  (a) => a.starts,
                ),
                stamps,
              );
            });
          }
        },
      );

      test(
        'calendar ordering, min/max, grouping and stable date cursors',
        () async {
          await create();
          final dates = [
            LocalDate(10000, 1, 1),
            LocalDate(2, 1, 1),
            LocalDate(-10, 1, 1),
            LocalDate(0, 1, 1),
          ];
          for (final day in dates) {
            await db.appointments.create(day: day);
          }
          final ordered = [...dates]..sort();
          expect(
            await db.appointments
                .orderBy((a) => [a.day.asc()])
                .select((a) => a.day)
                .get(),
            ordered,
          );
          expect(
            await db.appointments
                .select((a) => (a.day.min(), a.day.max()).row)
                .single(),
            (ordered.first, ordered.last),
          );
          expect(
            await db.appointments
                .where((a) => a.day.isIn(dates.take(2)))
                .count(),
            2,
          );
          final token = db.appointments.cursorToken(
            (a) => [a.day.cursor(ordered[1]), a.id.cursor(4)],
          );
          expect(
            (await db.appointments
                    .seekToken(token, orderBy: (a) => [a.day.asc(), a.id.asc()])
                    .get())
                .map((a) => a.day),
            ordered.skip(2),
          );
          final rolling = await db.appointments
              .orderBy((a) => [a.id.asc()])
              .select(
                (a) => a.day.min().over(
                  orderBy: [a.id.asc()],
                  frame: .rowsToCurrent,
                ),
              )
              .get();
          expect(rolling, [dates[0], dates[1], dates[2], dates[2]]);
        },
      );

      test(
        'equivalent date keys drive batched relations and unique indexes',
        () async {
          await create();
          final bc = LocalDate(0, 1, 1);
          await db.holidays.create(day: bc, label: 'era');
          await db.execute(
            SqlCommand("INSERT INTO visits (day) VALUES ('0001-01-01 BC')"),
          );
          expect(
            await db.holidays
                .select((h) => h.visits.select((v) => v.day).many())
                .single(),
            [bc],
          );
          expect(
            await db.visits
                .select((v) => v.holiday.select((h) => h.label).one())
                .single(),
            'era',
          );
          await expectLater(
            db.holidays.create(day: bc, label: 'duplicate'),
            throwsA(isA<SqlFailure>()),
          );
          if (backend == 'sqlite') {
            await db.execute(
              SqlCommand("UPDATE visits SET day = '0000-01-01'"),
            );
            expect(
              await db.holidays
                  .select((h) => h.visits.select((v) => v.day).many())
                  .single(),
              [bc],
            );
            final command = db.holidays.byId(bc).compile();
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

      test(
        'time and local timestamp comparisons retain calendar semantics',
        () async {
          await create();
          final times = [
            LocalTime(24),
            LocalTime(0, 0, 0, 1),
            LocalTime(0),
            LocalTime(23, 59, 59, 999999),
          ];
          final stamps = [
            LocalDateTime.parse('10000-01-01 00:00'),
            LocalDateTime.parse('0001-01-01 00:00 BC'),
            LocalDateTime.parse('0002-01-01 00:00 BC'),
            LocalDateTime.parse('2024-01-01 00:00'),
          ];
          for (var i = 0; i < times.length; i++) {
            await db.appointments.create(
              day: LocalDate(2024, 1, 1),
              time: Change.set(times[i]),
              starts: stamps[i],
            );
          }
          expect(
            await db.appointments
                .orderBy((a) => [a.time.asc()])
                .select((a) => a.time)
                .get(),
            [...times]..sort(),
          );
          expect(
            await db.appointments
                .orderBy((a) => [a.starts.asc()])
                .select((a) => a.starts)
                .get(),
            [...stamps]..sort(),
          );
          expect(
            await db.appointments.where((a) => a.time.gt(LocalTime(0))).count(),
            3,
          );
          expect(
            await db.appointments
                .select(
                  (a) => (
                    a.time.min(),
                    a.time.max(),
                    a.starts.min(),
                    a.starts.max(),
                  ).row,
                )
                .single(),
            (times[2], times[0], stamps[2], stamps[0]),
          );
          final grouped = await db.appointments
              .groupBy((a) => [a.day])
              .select((a) => (a.day, a.time.count()).row)
              .single();
          expect(grouped, (LocalDate(2024, 1, 1), 4));
          final cte = db.appointments
              .select((a) => a.starts)
              .asCte('local_starts');
          expect(
            await cte.query
                .where((a) => a.ref((s) => s.starts).gt(stamps[3]))
                .get(),
            [stamps[0]],
          );
          final query = db.appointments.select((a) => a.time);
          expect(await query.union(query).get(), unorderedEquals(times));
        },
      );

      test('reviewed text-to-time migration rolls back duplicate clock values', () async {
        TableSchema schema(Codec<Object?> codec) => TableSchema(
          'converted',
          columns: [Column('id', Codecs.integer), Column('clock', codec)],
          primaryKey: ['id'],
          uniqueKeys: [
            ['clock'],
          ],
        );
        final first = Migration.create('0001_text', [
          schema(Codecs.text),
        ], dialect: db.dialect);
        await Migrator(db.sql).apply([first]);
        await db.execute(
          SqlCommand(
            "INSERT INTO converted VALUES (1, '12:30'), (2, '12:30:00.000000')",
          ),
        );
        final second = Migration.diff(
          '0002_time',
          from: first.snapshot!,
          to: SchemaSnapshot([schema(Codecs.time)]),
          previous: first.checksum,
          using: (db.dialect == SqlDialect.sqlite
              ? {
                  'converted': {'clock': 'clock'},
                }
              : {
                  'converted': {
                    'clock': 'CAST(clock AS TIME WITHOUT TIME ZONE)',
                  },
                }),
          dialect: db.dialect,
        );
        await expectLater(
          Migrator(db.sql).apply([first, second]),
          throwsA(isA<SqlFailure>()),
        );
        expect((await Migrator(db.sql).history()).length, 1);
        expect(
          (await verifySchema(db.sql, first.snapshot!)).differences,
          isEmpty,
        );
        await db.execute(SqlCommand('DELETE FROM converted WHERE id = 2'));
        await Migrator(db.sql).apply([first, second]);
        expect(
          (await verifySchema(db.sql, second.snapshot!)).differences,
          isEmpty,
        );
        expect(
          Codecs.time.decode(
            (await db.execute(SqlCommand('SELECT clock FROM converted')))
                .rows
                .single
                .single,
          ),
          LocalTime(12, 30),
        );
      });

      test('invalid external dates fail typed reads without damaging the connection', () async {
        await create();
        await db.execute(
          SqlCommand(
            "INSERT INTO appointments (day, starts) VALUES ('${backend == 'sqlite' ? 'invalid' : 'infinity'}', '${backend == 'sqlite' ? 'invalid' : '-infinity'}')",
          ),
        );
        await expectLater(
          db.appointments.select((a) => a.day).get(),
          throwsFormatException,
        );
        await expectLater(
          db.appointments.select((a) => a.starts).get(),
          throwsFormatException,
        );
        await db.appointments.create(day: LocalDate(2024, 1, 1));
        expect(
          await db.appointments
              .where((a) => a.day.eq(LocalDate(2024, 1, 1)))
              .count(),
          1,
        );
      });

      test(
        'snapshots, catalog import and regenerated defaults agree',
        () async {
          await create();
          final snapshot = SchemaSnapshot(appSchema);
          expect(physical.schema.checksum, snapshot.checksum);
          expect((await verifySchema(db.sql, snapshot)).differences, isEmpty);
          expect((await verifySchema(db.sql, snapshot)).unmanaged, isEmpty);
          expect(await verifyColumns(db.sql, appSchema), isEmpty);
          final imported = await importSchema(db.sql);
          expect(imported.issues, isEmpty);
          expect(imported.dart, contains('LocalDateTime'));
          final directory = await Directory(
            '.dart_tool/orm-temporal-import-$backend',
          ).create(recursive: true);
          try {
            final file = File('${directory.path}/schema.dart');
            await file.writeAsString(imported.dart);
            final generated = await generateSchema(file.path);
            expect(
              (await verifySchema(db.sql, generated.snapshot)).differences,
              isEmpty,
            );
          } finally {
            await directory.delete(recursive: true);
          }
        },
      );

      test(
        'historical date keys resume a bounded backfill in calendar order',
        () async {
          await create();
          for (final year in [10000, 2, -10, 0]) {
            await db.holidays.create(
              day: LocalDate(year, 1, 1),
              label: 'pending',
            );
          }
          final first = Migration.create(
            '0001_local',
            appSchema,
            dialect: db.dialect,
          );
          final second = Migration.steps(
            '0002_backfill',
            [
              Backfill(
                holidaysSchema,
                set: {'label': "'done'"},
                where: "label = 'pending'",
                doneWhen: "SELECT NOT EXISTS (SELECT 1 FROM holidays WHERE label = 'pending')",
                batchSize: 1,
              ),
            ],
            previous: first.checksum,
            dialect: db.dialect,
          );
          await Migrator(db.sql).apply([first, second], maxBackfillBatches: 1);
          expect(
            (await db.holidays.where((h) => h.label.eq('done')).single()).day,
            LocalDate(-10, 1, 1),
          );
          await Migrator(db.sql).apply([first, second]);
          expect(await db.holidays.where((h) => h.label.eq('done')).count(), 4);
        },
      );
    });
  }
}
