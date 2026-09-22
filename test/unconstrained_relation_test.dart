@Tags(['database'])
library;

import 'dart:async';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/unconstrained/schema.orm.dart';

Matcher code(String value) =>
    isA<OrmException>().having((e) => e.code, 'code', value);

void main() {
  for (final dialect in [SqlDialect.sqlite, SqlDialect.postgres]) {
    group(
      'unconstrained ${dialect.name}',
      () {
        late Database<Backend> db;
        final events = <QueryEvent>[];
        setUp(() async {
          if (dialect == SqlDialect.sqlite) {
            db = await sqlite(
              const SqliteOptions.memory(),
              onQuery: events.add,
            );
          } else {
            db = postgres(
              PostgresOptions(
                url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                tls: .disable,
                schema: 'orm_unconstrained_tests',
              ),
              onQuery: events.add,
            );
            await db.execute(
              SqlCommand(
                'DROP SCHEMA IF EXISTS orm_unconstrained_tests CASCADE',
              ),
            );
            await db.execute(
              SqlCommand('CREATE SCHEMA orm_unconstrained_tests'),
            );
          }
          await Migrator(db.sql).apply([
            Migration.create('0001_initial', appSchema, dialect: db.dialect),
          ]);
          await db.execute(
            SqlCommand(
              'INSERT INTO accounts(tenant,id,display_label,manager_id) VALUES '
              "(1,1,'dup',NULL),(1,2,'dup',1),(1,3,NULL,404),(2,1,'dup',NULL)",
            ),
          );
          await db.execute(
            SqlCommand(
              'INSERT INTO entries(id,tenant,owner,lookup_label) VALUES '
              "(1,1,1,'dup'),(2,1,99,'dup'),(3,NULL,1,'dup'),(4,1,NULL,NULL),"
              "(5,2,1,'dup'),(6,3,1,'absent'),(7,1,3,NULL)",
            ),
          );
          events.clear();
        });
        tearDown(() => db.close());

        test(
          'catalogs contain no FK, implicit index or uniqueness promise',
          () async {
            for (final table in appSchema) {
              expect(table.foreignKeys, isEmpty);
              final actual = await inspectTable(db.sql, table.name);
              expect(actual.foreignKeys, isEmpty);
              expect(actual.uniqueKeys, isEmpty);
              expect(actual.indexes, isEmpty);
            }
            expect(
              (await verifySchema(db.sql, SchemaSnapshot(appSchema))).matches,
              true,
            );
            // A dangling reference and duplicate lookup keys are valid stored data.
            expect(await db.entry.count(), 7);
            expect(
              await db.account.where((a) => a.label.eq(.value('dup'))).count(),
              3,
            );
          },
        );

        test(
          'adding and removing a real FK remains a reviewed physical migration',
          () async {
            final constrained = [
              accountSchema,
              TableSchema(
                entrySchema.name,
                columns: entrySchema.columns,
                primaryKey: entrySchema.primaryKey,
                foreignKeys: [
                  const ForeignKey(
                    ['tenant', 'owner'],
                    'accounts',
                    ['tenant', 'id'],
                  ),
                ],
              ),
              readingSchema,
            ];
            final first = Migration.create(
              '0001_initial',
              appSchema,
              dialect: db.dialect,
            );
            final enforce = Migration.diff(
              '0002_enforce',
              from: SchemaSnapshot(appSchema),
              to: SchemaSnapshot(constrained),
              previous: first.checksum,
              dialect: db.dialect,
            );
            await expectLater(
              Migrator(db.sql).apply([first, enforce]),
              throwsA(anything),
            );
            expect(
              (await verifySchema(db.sql, SchemaSnapshot(appSchema))).matches,
              true,
            );
            expect(await db.entry.count(), 7);
            await db.entry.byId(2).patch(owner: .set(1));
            await db.entry.byId(6).patch(tenant: .set(1));
            await Migrator(db.sql).apply([first, enforce]);
            expect(
              (await inspectTable(db.sql, 'entries')).foreignKeys.length,
              1,
            );
            final release = Migration.diff(
              '0003_unconstrain',
              from: SchemaSnapshot(constrained),
              to: SchemaSnapshot(appSchema),
              previous: enforce.checksum,
              dialect: db.dialect,
            );
            await Migrator(db.sql).apply([first, enforce, release]);
            expect(
              (await verifySchema(db.sql, SchemaSnapshot(appSchema))).matches,
              true,
            );
            await db.entry.create(id: 8, tenant: 9, owner: 99);
            expect(await db.entry.count(), 8);
            expect(
              await db.entry
                  .byId(8)
                  .select((e) => e.ownerAccount.one())
                  .single(),
              isNull,
            );
          },
        );

        test('unique joins preserve root rows, NULL components and missing targets', () async {
          final rows = await db.entry
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => (
                  e.id,
                  e.ownerAccount.select((a) => (a.id, a.label).row).one(),
                ).map((id, owner) => (id, owner)),
              )
              .get();
          expect(rows, [
            (1, (1, 'dup')),
            (2, null),
            (3, null),
            (4, null),
            (5, (1, 'dup')),
            (6, null),
            (7, (3, null)),
          ]);
          expect(events.length, 1);
          expect(events.single.sql, contains('LEFT JOIN'));
          events.clear();
          final page = await db.entry
              .orderBy((e) => [e.id.asc()])
              .skip(1)
              .take(2)
              .select(
                (e) => (
                  e.id,
                  e.ownerAccount.select((a) => a.id).one(),
                ).map((id, owner) => (id, owner)),
              )
              .get();
          expect(page, [(2, null), (3, null)]);
          expect(events.length, 1);
        });

        test('required target and filter visibility remain explicit', () async {
          await expectLater(
            db.entry.byId(2).select((e) => e.ownerAccount.required()).single(),
            throwsA(code('RELATION.MISSING')),
          );
          expect(
            await db.entry
                .byId(1)
                .select(
                  (e) => e.ownerAccount.where((a) => a.id.eq(.value(2))).one(),
                )
                .single(),
            isNull,
          );
          expect(
            await db.entry
                .byId(7)
                .select((e) => e.ownerAccount.select((a) => a.label).required())
                .single(),
            isNull,
          );
          expect(await db.entry.count(), 7);
        });

        test(
          'nonunique composite collections batch by tuple and page per parent',
          () async {
            final rows = await db.entry
                .orderBy((e) => [e.id.asc()])
                .select(
                  (e) => e.matchingAccounts
                      .orderBy((a) => [a.id.asc()])
                      .select((a) => a.id)
                      .many(),
                )
                .get();
            expect(rows, <List<int>>[
              [1, 2],
              [1, 2],
              [],
              [],
              [1],
              [],
              [],
            ]);
            expect(events.length, 2);
            events.clear();
            final pages = await db.entry
                .orderBy((e) => [e.id.asc()])
                .select(
                  (e) => e.matchingAccounts
                      .orderBy((a) => [a.id.asc()])
                      .skip(1)
                      .take(1)
                      .select((a) => a.id)
                      .many(),
                )
                .get();
            expect(pages, <List<int>>[
              [2],
              [2],
              [],
              [],
              [],
              [],
              [],
            ]);
            expect(events.length, 2);
            expect(events.last.sql, contains('ROW_NUMBER()'));
          },
        );

        test(
          'to-one uses cardinality checks without assuming a unique lookup',
          () async {
            expect(
              () => db.entry.select(
                (e) => e.matchingAccounts.one(strategy: .join),
              ),
              throwsA(code('RELATION.JOIN_KEY')),
            );
            expect(events, isEmpty);
            await expectLater(
              db.entry.byId(1).select((e) => e.matchingAccounts.one()).single(),
              throwsA(code('RELATION.CARDINALITY')),
            );
            expect(events.length, 2);
            expect(
              await db.entry
                  .byId(1)
                  .select(
                    (e) => e.matchingAccounts
                        .where((a) => a.id.eq(.value(2)))
                        .select((a) => a.id)
                        .one(),
                  )
                  .single(),
              2,
            );
            expect(
              await db.entry
                  .byId(1)
                  .select(
                    (e) => e.matchingAccounts
                        .orderBy((a) => [a.id.desc()])
                        .take(1)
                        .select((a) => a.id)
                        .one(),
                  )
                  .single(),
              2,
            );
          },
        );

        test(
          'correlated filters and counts do not materialize related rows',
          () async {
            final rows = await db.entry
                .orderBy((e) => [e.id.asc()])
                .select(
                  (e) => (
                    e.matchingAccounts.count(),
                    e.matchingAccounts.any(),
                    e.matchingAccounts.none(),
                    e.matchingAccounts.every((a) => a.id.gte(.value(2))),
                  ).row,
                )
                .get();
            expect(rows, [
              (2, true, false, false),
              (2, true, false, false),
              (0, false, true, true),
              (0, false, true, true),
              (1, true, false, false),
              (0, false, true, true),
              (0, false, true, true),
            ]);
            expect(events.length, 1);
          },
        );

        test(
          'self relations and inverse collections share the existing planner',
          () async {
            final rows = await db.account
                .orderBy((a) => [a.tenant.asc(), a.id.asc()])
                .select(
                  (a) => (
                    a.manager.select((m) => m.id).one(),
                    a.reports
                        .orderBy((r) => [r.id.asc()])
                        .select((r) => r.id)
                        .many(),
                  ).map((manager, reports) => (manager, reports)),
                )
                .get();
            expect(rows.map((r) => r.$1), [null, 1, null, null]);
            expect(rows.map((r) => r.$2), <List<int>>[
              [2],
              [],
              [],
              [],
            ]);
            expect(events.length, 2);
            final entries = await db.account
                .byId(tenant: 1, id: 1)
                .select((a) => a.entries.select((e) => e.id).many())
                .single();
            expect(entries, [1]);
          },
        );

        test(
          'delete has no cascade and watches track the joined target',
          () async {
            final snapshots = StreamIterator(
              db.entry
                  .byId(1)
                  .select((e) => e.ownerAccount.select((a) => a.id).one())
                  .watch(),
            );
            try {
              expect(
                await snapshots.moveNext().timeout(const Duration(seconds: 5)),
                true,
              );
              expect(snapshots.current, [1]);
              await db.account.byId(tenant: 1, id: 1).delete().execute();
              expect(
                await snapshots.moveNext().timeout(const Duration(seconds: 5)),
                true,
              );
              expect(snapshots.current, [null]);
              expect(await db.entry.count(), 7);
              expect((await db.entry.byId(1).single()).owner, 1);
              expect(
                (await db.account.byId(tenant: 1, id: 2).single()).managerId,
                1,
              );
            } finally {
              await snapshots.cancel();
            }
          },
        );

        test('transaction reads observe writes and outer rollback restores targets', () async {
          await expectLater(
            db.transaction((tx) async {
              await tx.account.byId(tenant: 1, id: 1).delete().execute();
              expect(
                await tx.entry
                    .byId(1)
                    .select((e) => e.ownerAccount.one())
                    .single(),
                isNull,
              );
              throw StateError('rollback');
            }),
            throwsStateError,
          );
          expect(
            await db.entry
                .byId(1)
                .select((e) => e.ownerAccount.select((a) => a.id).one())
                .single(),
            1,
          );
        });

        test(
          'streaming preserves optional and batched relation result shapes',
          () async {
            final rows = await db.entry
                .orderBy((e) => [e.id.asc()])
                .select(
                  (e) => (
                    e.ownerAccount.select((a) => a.id).one(),
                    e.matchingAccounts
                        .orderBy((a) => [a.id.asc()])
                        .select((a) => a.id)
                        .many(),
                  ).map((owner, matches) => (owner, matches)),
                )
                .stream(batchSize: 2)
                .toList();
            expect(rows.map((r) => r.$1), [1, null, null, null, 1, null, 3]);
            expect(rows.map((r) => r.$2), <List<int>>[
              [1, 2],
              [1, 2],
              [],
              [],
              [1],
              [],
              [],
            ]);
          },
        );

        test(
          'floating relation keys retain storage intent and key equality',
          () async {
            await db.reading.create(id: 1, value: 1e20);
            await db.reading.create(id: 2, value: 1e20);
            await db.reading.create(id: 3, value: 2e20);
            final rows = await db.reading
                .orderBy((r) => [r.id.asc()])
                .select(
                  (r) => r.peers
                      .orderBy((p) => [p.id.asc()])
                      .select((p) => p.id)
                      .many(),
                )
                .get();
            expect(rows, [
              [1, 2],
              [1, 2],
              [3],
            ]);
          },
        );
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
      tags: dialect.name,
    );
  }
}
