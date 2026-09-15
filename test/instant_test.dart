import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/instants/schema.orm.dart';
import 'support/instants/m0001_legacy.dart' as historical;

DateTime instant(String value) => Codecs.dateTime.decode(value);

void main() {
  test('strict UTC parsing handles eras, offsets, endpoints and invalid components', () {
    expect(instant('2024-01-01 08:00+08'), DateTime.utc(2024));
    expect(instant('2024-01-01 00:00'), DateTime.utc(2024));
    expect(
      instant('2024-01-01 00:00:01.000001+00:00:01'),
      DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1),
    );
    expect(instant('0001-01-01 00:00Z BC'), DateTime.utc(0));
    expect(
      instant('275760-09-13 15:59:59+15:59:59').microsecondsSinceEpoch,
      8640000000000000000,
    );
    expect(
      instant('4714-11-23 23:00-01 BC').microsecondsSinceEpoch,
      -210866803200000000,
    );
    for (final ticks in [-210866803200000000, -1, 0, 1, 8640000000000000000]) {
      final value = DateTime.fromMicrosecondsSinceEpoch(ticks, isUtc: true);
      expect(instant(Codecs.dateTime.encode(value) as String), value);
    }
    for (final text in [
      '2024-02-30 00:00Z',
      '2024-01-01 24:00:00.000001Z',
      '2024-01-01 00:00:60Z',
      '2024-01-01 00:00+16',
      '2024-01-01 00:00+01:99',
      '2024-01-01 00:00:00.0000001Z',
      '275760-09-13 00:00:00.000001Z',
      '4714-11-24 00:00+00:00:01 BC',
      'infinity',
      '2024-01-01 00:00Z\n',
    ]) {
      expect(() => instant(text), throwsFormatException, reason: text);
    }
    expect(
      () => Codecs.dateTime.encode(DateTime.utc(-4713, 11, 23)),
      throwsFormatException,
    );
    expect(
      () => Codecs.dateTime.decode(LocalDateTime.parse('2024-01-01 00:00')),
      throwsFormatException,
    );
  });

  test('UTC defaults and local DateTime inputs do not depend on the process timezone', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'test/support/instants/native.dart'],
      environment: {'TZ': 'Asia/Shanghai'},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      result.stdout,
      contains(
        'Instant UTC, precision, ordering, relations and defaults verified.',
      ),
    );
  });

  Future<Migration> legacy() async => historical.migration;
  test(
    'historical migration checksum and timestamp tag remain immutable',
    () async {
      final first = await legacy();
      // Captured with the 00853b4 sources, before instant storage existed.
      expect(
        first.checksum,
        '3796f4361abf4ae7a9aaee65f7130958083c34f03e23e92679ecca5dbf19f7d6',
      );
      expect(
        first.snapshot!.tables.single.columns.first.codec.sqlType,
        'timestamp',
      );
      expect(first.checksum, historical.migrationChecksum);
      expect(Codecs.dateTime.sqlType, 'instant');
    },
  );

  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    group('UTC instant $backend', () {
      late Database<Backend> db;
      setUp(() async {
        if (backend == 'sqlite') {
          db = await sqlite(const SqliteOptions.memory());
        } else {
          db = postgres(
            PostgresOptions(
              url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
              tls: .disable,
              schema: 'orm_instant_tests',
            ),
          );
          await db.execute(
            SqlCommand('DROP SCHEMA IF EXISTS orm_instant_tests CASCADE'),
          );
          await db.execute(SqlCommand('CREATE SCHEMA orm_instant_tests'));
        }
      });
      tearDown(() => db.close());
      Future<void> create() =>
          Migrator(db).apply([Migration.create('0001_instant', appSchema)]);
      Migration upgrade(Migration first) => Migration.diff(
        '0002_instant',
        from: first.snapshot!,
        to: SchemaSnapshot([momentsSchema]),
        previous: first.checksum,
        using: {
          SqlDialect.sqlite: {
            'moments': {'at': 'orm_instant_v1(at)'},
          },
          SqlDialect.postgres: {
            'moments': {'at': 'at'},
          },
        },
      );

      test('native round trips and streams preserve exact microseconds and common endpoints', () async {
        await create();
        final dates = [
          DateTime.utc(-4713, 11, 24),
          DateTime.utc(0),
          DateTime.utc(10000),
          DateTime.fromMicrosecondsSinceEpoch(-1, isUtc: true),
          DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
          DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true),
          DateTime.fromMicrosecondsSinceEpoch(8640000000000000000, isUtc: true),
        ];
        for (final date in dates) {
          final row = await db.events.create(at: date);
          expect(row.at, date);
          expect(row.created.isUtc, true);
          expect(
            await db.events
                .byId(row.id)
                .select((e) => value(date, Codecs.dateTime))
                .single(),
            date,
          );
        }
        expect(
          (await db.events
                  .orderBy((e) => [e.id.asc()])
                  .stream(batchSize: 1)
                  .toList())
              .map((e) => e.at),
          dates,
        );
        if (backend == 'postgres') {
          await db.session((s) async {
            await s.execute(SqlCommand("SET DateStyle TO 'SQL, DMY'"));
            await s.execute(SqlCommand("SET TIME ZONE 'Europe/Paris'"));
            expect(
              (await s.events.orderBy((e) => [e.id.asc()]).get()).map(
                (e) => e.at,
              ),
              dates,
            );
          });
        }
      });

      test('chronological comparisons, grouping, windows, union and CTEs use instants', () async {
        await create();
        final epoch = DateTime.utc(2024),
            next = DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1);
        await db.events.create(at: epoch);
        await db.events.create(at: next);
        await db.execute(
          SqlCommand("INSERT INTO events (at) VALUES ('2024-01-01 08:00+08')"),
        );
        expect(
          await db.events
              .orderBy((e) => [e.at.asc(), e.id.asc()])
              .select((e) => e.at)
              .get(),
          [epoch, epoch, next],
        );
        expect(await db.events.where((e) => e.at.gt(epoch)).count(), 1);
        expect(await db.events.where((e) => e.at.isIn([epoch])).count(), 2);
        expect(
          await db.events.select((e) => (e.at.min(), e.at.max()).row).single(),
          (epoch, next),
        );
        expect(
          await db.events
              .groupBy((e) => [e.at])
              .orderBy((e) => [e.at.asc()])
              .select((e) => (e.at, e.id.count()).row)
              .get(),
          [(epoch, 2), (next, 1)],
        );
        expect(
          await db.events
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => e.at.max().over(
                  orderBy: [e.id.asc()],
                  frame: .rowsToCurrent,
                ),
              )
              .get(),
          [epoch, next, next],
        );
        final source = db.events.select((e) => e.at),
            cte = source.asCte('times');
        expect(
          await cte.query.where((c) => c.ref((e) => e.at).gt(epoch)).get(),
          [next],
        );
        expect(
          await source.union(source).get(),
          unorderedEquals([epoch, next]),
        );
        final token = db.events.cursorToken(
          (e) => [e.at.cursor(epoch), e.id.cursor(3)],
        );
        expect(
          (await db.events
                  .seekToken(token, orderBy: (e) => [e.at.asc(), e.id.asc()])
                  .get())
              .map((e) => e.at),
          [next],
        );
      });

      test(
        'offset-equivalent keys join and batch through the same unique index',
        () async {
          await create();
          final date = DateTime.utc(2024);
          await db.moments.create(at: date);
          await db.execute(
            SqlCommand(
              "INSERT INTO links (at) VALUES ('2024-01-01 08:00:00+0800')",
            ),
          );
          expect(
            await db.moments
                .select((m) => m.links.select((l) => l.at).many())
                .single(),
            [date],
          );
          expect(
            await db.links
                .select((l) => l.moment.select((m) => m.at).one())
                .single(),
            date,
          );
          await expectLater(
            db.execute(
              SqlCommand(
                "INSERT INTO moments (at) VALUES ('2023-12-31 23:00-01')",
              ),
            ),
            throwsA(isA<SqlFailure>()),
          );
          if (backend == 'sqlite') {
            final command = db.moments.byId(date).compile();
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

      test('current snapshots, physical catalog and imported DateTime declarations agree', () async {
        await create();
        final snapshot = SchemaSnapshot(appSchema);
        expect((await verifySchema(db, snapshot)).differences, isEmpty);
        expect((await verifySchema(db, snapshot)).unmanaged, isEmpty);
        expect(await verifyColumns(db, appSchema), isEmpty);
        final imported = await importSchema(db);
        expect(imported.issues, isEmpty);
        expect(imported.dart, contains('DateTime'));
        final directory = await Directory(
          '.dart_tool/orm-instant-import-$backend',
        ).create(recursive: true);
        try {
          final file = File('${directory.path}/schema.dart');
          await file.writeAsString(imported.dart);
          final generated = await generateSchema(file.path);
          expect(
            (await verifySchema(db, generated.snapshot)).differences,
            isEmpty,
          );
        } finally {
          await directory.delete(recursive: true);
        }
      });

      test('offset literals compare by value while expression casts remain visible', () async {
        final table = TableSchema(
          'defaults',
          columns: [
            Column('at', Codecs.dateTime, defaultSql: "'2024-01-01 08:00+08'"),
          ],
        );
        final migration = Migration.create('0001_defaults', [table]);
        await Migrator(db).apply([migration]);
        expect(
          (await verifySchema(db, migration.snapshot!)).differences,
          isEmpty,
        );
        final row = await db.execute(
          SqlCommand('INSERT INTO defaults DEFAULT VALUES RETURNING at'),
        );
        expect(
          Codecs.dateTime.decode(row.rows.single.single),
          DateTime.utc(2024),
        );
        if (backend == 'postgres') {
          await db.execute(
            SqlCommand(
              'ALTER TABLE defaults ALTER COLUMN at SET DEFAULT (CURRENT_TIMESTAMP::date)::timestamp with time zone',
            ),
          );
          final expected = SchemaSnapshot([
            TableSchema(
              'defaults',
              columns: [
                Column(
                  'at',
                  Codecs.dateTime,
                  defaultSql: 'CURRENT_TIMESTAMP::date',
                ),
              ],
            ),
          ]);
          expect((await verifySchema(db, expected)).differences, isNotEmpty);
        }
      });

      test('reviewed migration preserves history and repairs legacy timestamp ordering', () async {
        final first = await legacy();
        await Migrator(db).apply([first]);
        await db.execute(
          SqlCommand(
            "INSERT INTO moments (at) VALUES ('2024-01-01T00:00:00.000Z'), ('2024-01-01T00:00:00.000001Z')",
          ),
        );
        final second = upgrade(first);
        expect(second.snapshot!.checksum, isNot(first.snapshot!.checksum));
        await Migrator(db).apply([first, second]);
        expect((await Migrator(db).history()).first.checksum, first.checksum);
        expect((await verifySchema(db, second.snapshot!)).differences, isEmpty);
        expect(
          await db.moments
              .orderBy((m) => [m.at.asc()])
              .select((m) => m.at)
              .get(),
          [DateTime.utc(2024), DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1)],
        );
      });

      if (backend == 'sqlite') {
        test('legacy key collisions and invalid calendar values roll back conversion', () async {
          final first = await legacy();
          await Migrator(db).apply([first]);
          await db.execute(
            SqlCommand(
              "INSERT INTO moments (at) VALUES ('2024-01-01T00:00:00Z'), ('2024-01-01 08:00+08')",
            ),
          );
          final second = upgrade(first);
          await expectLater(
            Migrator(db).apply([first, second]),
            throwsA(isA<SqlFailure>()),
          );
          expect((await Migrator(db).history()).length, 1);
          expect(
            (await verifySchema(db, first.snapshot!)).differences,
            isEmpty,
          );
          await db.execute(
            SqlCommand("DELETE FROM moments WHERE at = '2024-01-01 08:00+08'"),
          );
          await db.execute(
            SqlCommand("INSERT INTO moments (at) VALUES ('2024-02-31 00:00')"),
          );
          await expectLater(
            Migrator(db).apply([first, second]),
            throwsA(isA<SqlFailure>()),
          );
          expect((await Migrator(db).history()).length, 1);
          await db.execute(
            SqlCommand("DELETE FROM moments WHERE at = '2024-02-31 00:00'"),
          );
          await Migrator(db).apply([first, second]);
          expect((await db.moments.single()).at, DateTime.utc(2024));
        });
      }

      test('instant primary-key backfills resume across sub-millisecond boundaries', () async {
        await create();
        final times = [
          DateTime.utc(2024),
          DateTime.utc(2024, 1, 1, 0, 0, 0, 0, 1),
          DateTime.utc(0),
        ];
        for (final time in times) {
          await db.moments.create(at: time);
        }
        final first = Migration.create('0001_instant', appSchema);
        final second = Migration.steps('0002_backfill', {
          for (final dialect in SqlDialect.values)
            dialect: [
              Backfill(
                momentsSchema,
                set: {'label': "'done'"},
                where: "label = 'pending'",
                doneWhen: "SELECT NOT EXISTS (SELECT 1 FROM moments WHERE label = 'pending')",
                batchSize: 1,
              ),
            ],
        }, previous: first.checksum);
        await Migrator(db).apply([first, second], maxBackfillBatches: 1);
        expect(
          (await db.moments.where((m) => m.label.eq('done')).single()).at,
          DateTime.utc(0),
        );
        await Migrator(db).apply([first, second]);
        expect(await db.moments.where((m) => m.label.eq('done')).count(), 3);
      });

      test('external infinity and out-of-DateTime values fail decoding without wrapping', () async {
        await create();
        for (final text in [
          'infinity',
          '-infinity',
          '294276-12-31 23:59:59.999999+00',
        ]) {
          await db.execute(
            SqlCommand("INSERT INTO events (at) VALUES ('$text')"),
          );
        }
        final raw = await db.execute(
          SqlCommand('SELECT at FROM events ORDER BY id'),
        );
        expect(raw.rows.every((r) => r.single is String), true);
        for (final row in raw.rows) {
          expect(
            () => Codecs.dateTime.decode(row.single),
            throwsFormatException,
          );
        }
        await expectLater(db.events.get(), throwsFormatException);
        expect(
          (await db.events.create(at: DateTime.utc(2024))).at,
          DateTime.utc(2024),
        );
      });
    });
  }
}
