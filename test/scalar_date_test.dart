import 'package:orm/database.dart';
import 'package:orm/migration.dart';
import 'package:orm/query.dart';
import 'package:orm/schema.dart';
import 'package:test/test.dart';

import '../example/migrations/postgres/v001_initial.dart' as postgres;
import '../example/migrations/sqlite/v001_initial.dart' as sqlite;
import 'support/database.dart';

void main() {
  for (final engine in Engine.values) {
    group(
      'exact dates on ${engine.name}',
      skip: engine == Engine.postgresql && !hasPostgres
          ? 'Set ORM_TEST_POSTGRES_HOST or ORM_TEST_POSTGRES_SOCKET for a real database'
          : false,
      () {
        test('frozen literal defaults retain dates across year boundaries', () async {
          final fixture = await openTestDatabase(engine);
          addTearDown(fixture.db.close);
          final initial = engine == Engine.sqlite
              ? sqlite.migration
              : postgres.migration;
          final dates = [
            DateTime.utc(-1, 12, 31, 23, 59, 59, 999, 999),
            DateTime.utc(0),
            DateTime.utc(1),
            DateTime.fromMicrosecondsSinceEpoch(-1, isUtc: true),
            DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999),
            DateTime.utc(10000),
          ];
          final after = SchemaSnapshot(
            engine: engine,
            tables: [
              ...initial.snapshot.tables,
              for (final (index, date) in dates.indexed)
                TableDefinition('date_default_$index', [
                  ColumnDefinition(
                    name: 'instant',
                    field: 'instant',
                    type: ScalarType.dateTime,
                    defaultValue: date,
                  ),
                ]),
            ],
          );
          final plan = planSchemaChange(initial.snapshot, after);
          final addition = Migration(
            version: 2,
            name: 'date defaults',
            engine: engine,
            steps: plan.steps,
            snapshot: after,
            reviewedFingerprint: migrationFingerprint(
              version: 2,
              name: 'date defaults',
              engine: engine,
              steps: plan.steps,
              snapshot: after,
            ),
          );
          final runner = MigrationRunner(
            fixture.db.database,
            MigrationHistory(engine: engine, migrations: [initial, addition]),
          );
          expect(await runner.apply(), [2]);
          expect(await runner.apply(), isEmpty);
          for (final (index, date) in dates.indexed) {
            final result = await fixture.db.session.run(
              'INSERT INTO "date_default_$index" DEFAULT VALUES RETURNING instant',
            );
            expect(decodeValue<DateTime>(result.rows.single.single), date);
          }
        });

        test(
          'orders and filters across fractional precision boundaries',
          () async {
            final fixture = await openTestDatabase(engine);
            addTearDown(fixture.db.close);
            final db = fixture.db;
            final base = DateTime.utc(2026, 10, 9);
            final offsets = [1000, -1, 999, 0, 1];
            for (final offset in offsets) {
              await db.users.create(
                username: 'offset$offset',
                age: 1,
                joinedAt: base.add(Duration(microseconds: offset)),
              );
            }
            final rows = await db.users.orderBy(joinedAt: asc).all();
            expect(rows.map((row) => row.username), [
              'offset-1',
              'offset0',
              'offset1',
              'offset999',
              'offset1000',
            ]);
            expect(
              (await db.users
                      .where(joinedAt: gt(base))
                      .orderBy(joinedAt: asc)
                      .all())
                  .map((row) => row.username),
              ['offset1', 'offset999', 'offset1000'],
            );
            expect(
              (await db.users
                      .where(joinedAt: lte(base))
                      .orderBy(joinedAt: asc)
                      .all())
                  .map((row) => row.username),
              ['offset-1', 'offset0'],
            );
            expect(
              (await db.users.where(joinedAt: eq(base)).all()).single.username,
              'offset0',
            );
            expect(rows.every((row) => row.joinedAt!.isUtc), isTrue);
          },
        );

        test(
          'negative epoch and signed or expanded years preserve order',
          () async {
            final fixture = await openTestDatabase(engine);
            addTearDown(fixture.db.close);
            final db = fixture.db;
            final instants = [
              DateTime.utc(-1, 12, 31, 23, 59, 59, 999, 999),
              DateTime.utc(0),
              DateTime.utc(1),
              DateTime.fromMicrosecondsSinceEpoch(-1, isUtc: true),
              DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
              DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true),
              DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999),
              DateTime.utc(10000),
            ];
            for (final (index, instant) in instants.indexed.toList().reversed) {
              await db.users.create(
                username: 'date$index',
                age: 1,
                joinedAt: instant,
              );
            }
            expect(
              (await db.users.orderBy(joinedAt: asc).all()).map(
                (row) => row.joinedAt,
              ),
              instants,
            );
            expect(
              (await db.users
                      .where(
                        joinedAt: lt(
                          DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
                        ),
                      )
                      .orderBy(joinedAt: asc)
                      .all())
                  .map((row) => row.joinedAt),
              instants.take(4),
            );
          },
        );
      },
    );
  }

  test('SQLite retains the full Dart DateTime range as integers', () async {
    final fixture = await openTestDatabase(Engine.sqlite);
    addTearDown(fixture.db.close);
    const bound = 8640000000000000000;
    final instants = [
      DateTime.fromMicrosecondsSinceEpoch(-bound, isUtc: true),
      DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
      DateTime.fromMicrosecondsSinceEpoch(bound, isUtc: true),
    ];
    for (final (index, instant) in instants.indexed) {
      await fixture.db.users.create(
        username: 'bound$index',
        age: 1,
        joinedAt: instant,
      );
    }
    expect(
      (await fixture.db.users.orderBy(joinedAt: asc).all()).map(
        (row) => row.joinedAt,
      ),
      instants,
    );
    expect(
      (await fixture.db.session.run('SELECT typeof(joined_at) FROM users'))
          .rows,
      [
        ['integer'],
        ['integer'],
        ['integer'],
      ],
    );
    expect(
      () => decodeValue<DateTime>('2026-10-09T00:00:00.000Z'),
      throwsFormatException,
    );
  });

  test('TableQuery rejects unsafe primary keys and identity definitions before SQL', () async {
    final fixture = await openTestDatabase(Engine.sqlite);
    addTearDown(fixture.db.close);
    const invalidColumns = [
      [
        ColumnDefinition(
          name: 'id',
          field: 'id',
          type: ScalarType.text,
          primaryKey: true,
          nullable: true,
        ),
      ],
      [
        ColumnDefinition(
          name: 'id',
          field: 'id',
          type: ScalarType.integer,
          primaryKey: true,
        ),
        ColumnDefinition(
          name: 'other',
          field: 'other',
          type: ScalarType.integer,
          primaryKey: true,
        ),
      ],
      [
        ColumnDefinition(
          name: 'id',
          field: 'id',
          type: ScalarType.integer,
          identity: true,
        ),
      ],
      [
        ColumnDefinition(
          name: 'id',
          field: 'id',
          type: ScalarType.text,
          primaryKey: true,
          identity: true,
        ),
      ],
      [
        ColumnDefinition(
          name: 'id',
          field: 'id',
          type: ScalarType.integer,
          primaryKey: true,
          identity: true,
          defaultValue: 1,
        ),
      ],
    ];
    for (final columns in invalidColumns) {
      expect(
        () => TableQuery(
          fixture.db.session,
          TableDefinition('unsafe', columns),
          (row) => row,
        ),
        throwsArgumentError,
      );
    }
    expect(fixture.events, isEmpty);
  });
}
