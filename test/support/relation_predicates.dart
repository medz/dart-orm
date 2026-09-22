import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';
import 'package:test/test.dart' hide allOf, anyOf;

import '../../example/teams/schema.orm.dart' as teams;
import 'relations/schema.orm.dart';

Matcher _code(String expected) =>
    isA<OrmException>().having((error) => error.code, 'code', expected);

/// The same relationship predicates execute against every supported engine.
void relationPredicateTests(
  String engine,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open, {
  String? skip,
}) {
  group(
    engine,
    () {
      late Database<Backend> db;
      final observations = <QueryEvent>[];
      setUp(() async {
        db = await open(observations.add);
        await Migrator(db.sql).apply([
          Migration.create('0001_relations', [
            ...appSchema,
            ...teams.appSchema,
          ], dialect: db.dialect),
        ]);
        await db.execute(
          SqlCommand(
            'INSERT INTO accounts(tenant,id,label,manager_id) VALUES '
            "(1,1,NULL,NULL),(1,2,'A2',1),(1,3,'A3',NULL),"
            "(2,1,'B1',NULL),(2,2,'B2',1)",
          ),
        );
        await db.execute(
          SqlCommand(
            'INSERT INTO events(id,tenant,owner,reviewer,title,score) VALUES '
            "(1,1,1,2,'e1',1),(2,1,1,NULL,'e2',2),"
            "(3,1,2,1,'e3',3),(4,1,2,NULL,'e4',4),"
            "(5,2,1,2,'e5',5),(6,2,1,NULL,'e6',6),"
            "(7,2,2,1,'e7',7),(8,2,2,NULL,'e8',8),"
            "(9,NULL,1,NULL,'e9',9),(10,1,NULL,NULL,'e10',10)",
          ),
        );
        observations.clear();
      });
      tearDown(() => db.close());

      test('nested boolean relationship filters select, update and delete the same rows', () async {
        final query = db.event.where(
          (e) => allOf([
            allOf([
              e.author
                  .where(
                    (a) => allOf([
                      anyOf([
                        a.id.eq(1),
                        a.manager.where((m) => m.label.isNull()).any(),
                      ]),
                      a.tenant.eq(1),
                    ]),
                  )
                  .any(),
              e.reviewerAccount.where((a) => a.label.isNull()).none(),
            ]),
            e.title.eq('e4').not(),
          ]),
        );
        expect(
          await query.orderBy((e) => [e.id.asc()]).select((e) => e.id).get(),
          [1, 2],
        );
        expect(observations, hasLength(1));
        expect(observations.single.sql, contains('EXISTS'));
        observations.clear();
        expect(
          await query.update((e) => [e.score.increment(100)]).execute(),
          2,
        );
        expect(observations, hasLength(1));
        expect(observations.single.sql, startsWith('UPDATE'));
        expect(observations.single.sql, contains('EXISTS'));
        observations.clear();
        expect(
          await db.event
              .where((e) => e.score.gt(100))
              .orderBy((e) => [e.id.asc()])
              .select((e) => e.id)
              .get(),
          [1, 2],
        );
        observations.clear();
        expect(await query.delete().execute(), 2);
        expect(observations, hasLength(1));
        expect(observations.single.sql, startsWith('DELETE'));
        expect(observations.single.sql, contains('EXISTS'));
        expect(
          await db.event.orderBy((e) => [e.id.asc()]).select((e) => e.id).get(),
          [3, 4, 5, 6, 7, 8, 9, 10],
        );
      });

      test(
        'self-reference mutation target follows the database capability',
        () async {
          final query = db.account.where(
            (a) => allOf([a.id.eq(3), a.manager.none()]),
          );
          expect(await query.select((a) => (a.tenant, a.id).row).get(), [
            (1, 3),
          ]);
          if (db.dialect == SqlDialect.mysql) {
            observations.clear();
            await expectLater(
              query.update((a) => [a.note.set('changed')]).execute(),
              throwsA(_code('CAPABILITY.MUTATION_SELF_REFERENCE')),
            );
            await expectLater(
              query.delete().execute(),
              throwsA(_code('CAPABILITY.MUTATION_SELF_REFERENCE')),
            );
            expect(observations, isEmpty);
            return;
          }
          expect(
            await query.update((a) => [a.note.set('changed')]).execute(),
            1,
          );
          expect(await query.delete().execute(), 1);
          expect(observations, hasLength(3));
        },
      );

      test(
        'nested back-reference mutation target follows the database capability',
        () async {
          final query = db.event.where(
            (e) => e.author
                .where(
                  (a) => a.events.where((other) => other.title.eq('e1')).any(),
                )
                .any(),
          );
          expect(
            await query.orderBy((e) => [e.id.asc()]).select((e) => e.id).get(),
            [1, 2],
          );
          if (db.dialect == SqlDialect.mysql) {
            observations.clear();
            await expectLater(
              query.update((e) => [e.score.increment(100)]).execute(),
              throwsA(_code('CAPABILITY.MUTATION_SELF_REFERENCE')),
            );
            await expectLater(
              query.delete().execute(),
              throwsA(_code('CAPABILITY.MUTATION_SELF_REFERENCE')),
            );
            expect(observations, isEmpty);
            return;
          }
          expect(
            await query.update((e) => [e.score.increment(100)]).execute(),
            2,
          );
          expect(await query.delete().execute(), 2);
          expect(observations, hasLength(3));
        },
      );

      test('relation counts that read the mutation target follow the database capability', () async {
        final query = db.account.where(
          (a) => allOf([a.id.eq(3), a.reports.count().eq(0)]),
        );
        expect(await query.select((a) => (a.tenant, a.id).row).get(), [(1, 3)]);
        observations.clear();
        if (db.dialect == SqlDialect.mysql) {
          await expectLater(
            query.update((a) => [a.note.set('changed')]).execute(),
            throwsA(_code('CAPABILITY.MUTATION_SELF_REFERENCE')),
          );
          await expectLater(
            query.delete().execute(),
            throwsA(_code('CAPABILITY.MUTATION_SELF_REFERENCE')),
          );
          expect(observations, isEmpty);
        } else {
          expect(
            await query.update((a) => [a.note.set('changed')]).execute(),
            1,
          );
          expect(await query.delete().execute(), 1);
          expect(observations, hasLength(2));
        }
      });

      test('scalar subqueries compare physical mutation table names across definitions', () async {
        final anotherAccount = Table<Account, AccountFields>(
          TableSchema(
            'accounts',
            columns: accountSchema.columns,
            primaryKey: accountSchema.primaryKey,
          ),
          AccountFields.new,
          accountTable.selectRow,
        );
        final query = db.account.where(
          (a) => allOf([
            a.id.eq(3),
            db
                .table(anotherAccount)
                .where((other) => allOf([other.id.eq(1), other.tenant.eq(1)]))
                .select((other) => other.id)
                .take(1)
                .scalar()
                .eq(1),
          ]),
        );
        expect(await query.select((a) => (a.tenant, a.id).row).get(), [(1, 3)]);
        observations.clear();
        if (db.dialect == SqlDialect.mysql) {
          await expectLater(
            query.update((a) => [a.note.set('changed')]).execute(),
            throwsA(_code('CAPABILITY.MUTATION_SELF_REFERENCE')),
          );
          await expectLater(
            query.delete().execute(),
            throwsA(_code('CAPABILITY.MUTATION_SELF_REFERENCE')),
          );
          expect(observations, isEmpty);
        } else {
          expect(
            await query.update((a) => [a.note.set('changed')]).execute(),
            1,
          );
          expect(await query.delete().execute(), 1);
          expect(observations, hasLength(2));
        }
      });

      test('same-child conjunction differs from independent matches', () async {
        final same = db.account.where(
          (a) => a.events
              .where((e) => allOf([e.score.eq(1), e.title.eq('e2')]))
              .any(),
        );
        expect(await same.get(), isEmpty);
        final separate = db.account.where(
          (a) => allOf([
            a.events.where((e) => e.score.eq(1)).any(),
            a.events.where((e) => e.title.eq('e2')).any(),
          ]),
        );
        expect(await separate.select((a) => (a.tenant, a.id).row).get(), [
          (1, 1),
        ]);
        expect(observations, hasLength(2));
      });

      test('successive filters preserve earlier conditions and relation immutability', () async {
        final rows = await db.account
            .orderBy((a) => [a.tenant.asc(), a.id.asc()])
            .select((a) {
              final events = a.events.where((e) => e.score.gte(2));
              return (
                events.where((e) => e.title.eq('e1')).any(),
                events.any(),
                events.where((e) => e.score.gte(6)).none(),
                events.count(),
              ).row;
            })
            .get();
        expect(rows, [
          (false, true, true, 1),
          (false, true, true, 2),
          (false, false, true, 0),
          (false, true, false, 2),
          (false, true, false, 2),
        ]);
        expect(observations, hasLength(1));
      });

      test(
        'nullable composite keys do not cross tenants or match partial nulls',
        () async {
          final rows = await db.event
              .orderBy((e) => [e.id.asc()])
              .select(
                (e) => (
                  e.author.where((a) => a.tenant.eq(1)).any(),
                  e.author.none(),
                  e.reviewerAccount.where((a) => a.id.eq(2)).any(),
                ).row,
              )
              .get();
          expect(rows, [
            (true, false, true),
            (true, false, false),
            (true, false, false),
            (true, false, false),
            (false, false, true),
            (false, false, false),
            (false, false, false),
            (false, false, false),
            (false, true, false),
            (false, true, false),
          ]);
          expect(observations, hasLength(1));
        },
      );

      test(
        'every rejects UNKNOWN and accepts an empty filtered relation',
        () async {
          final rows = await db.account
              .orderBy((a) => [a.tenant.asc(), a.id.asc()])
              .select(
                (a) => (
                  a.events.every((e) => e.reviewer.eq(2)),
                  a.events
                      .where((e) => e.reviewer.isNotNull())
                      .every((e) => e.reviewer.eq(2)),
                  allOf([a.events.any(), a.events.every((e) => e.score.gt(0))]),
                  a.events
                      .where((e) => e.score.gt(100))
                      .every((e) => e.title.eq('missing')),
                ).row,
              )
              .get();
          expect(rows, [
            (false, true, true, true),
            (false, false, true, true),
            (true, true, false, true),
            (false, true, true, true),
            (false, false, true, true),
          ]);
          expect(observations, hasLength(1));
        },
      );

      test(
        'self references and independent edges retain their own aliases',
        () async {
          final rows = await db.account
              .where(
                (a) => allOf([
                  allOf([
                    a.reports.where((r) => r.label.eq('A2')).any(),
                    a.events
                        .where(
                          (e) => e.reviewerAccount
                              .where((r) => r.label.eq('A2'))
                              .any(),
                        )
                        .any(),
                  ]),
                  a.reviews.where((e) => e.title.eq('e3')).any(),
                ]),
              )
              .select((a) => (a.tenant, a.id).row)
              .get();
          expect(rows, [(1, 1)]);
          expect(observations, hasLength(1));
        },
      );

      test(
        'root filters and collection loading filters have independent scopes',
        () async {
          final rows = await db.account
              .where((a) => a.events.where((e) => e.title.eq('e1')).any())
              .select(
                (a) => a.events
                    .orderBy((e) => [e.id.asc()])
                    .select((e) => e.title)
                    .many(),
              )
              .get();
          expect(rows, [
            ['e1', 'e2'],
          ]);
          expect(observations, hasLength(2));
          observations.clear();
          final filtered = await db.account
              .orderBy((a) => [a.tenant.asc(), a.id.asc()])
              .select(
                (a) => a.events
                    .where((e) => e.title.eq('e1'))
                    .select((e) => e.title)
                    .many(),
              )
              .get();
          expect(filtered, [
            ['e1'],
            <String>[],
            <String>[],
            <String>[],
            <String>[],
          ]);
          expect(observations, hasLength(2));
        },
      );

      test('nested many-to-many filters and filtered counts use a single statement', () async {
        await db.user.insertMany([
          (1, 'Ada'),
          (2, 'Ben'),
          (3, 'Cy'),
        ], (u, row) => [u.id.set(row.$1), u.name.set(row.$2)]).execute();
        await db.team.insertMany([
          (10, 'Core'),
          (20, 'Docs'),
        ], (t, row) => [t.id.set(row.$1), t.name.set(row.$2)]).execute();
        await db.membership.insertMany(
          [(10, 1), (20, 1), (20, 2)],
          (m, row) => [
            m.teamId.set(row.$1),
            m.userId.set(row.$2),
            m.role.set(teams.MembershipRole.member),
            m.joinedAt.set(DateTime.utc(2026)),
          ],
        ).execute();
        observations.clear();
        final rows = await db.user
            .where(
              (u) => u.memberships
                  .where((m) => m.team.where((t) => t.name.eq('Core')).any())
                  .any(),
            )
            .select(
              (u) => (
                u.name,
                u.memberships
                    .where((m) => m.team.where((t) => t.name.eq('Docs')).any())
                    .count(),
              ).row,
            )
            .get();
        expect(rows, [('Ada', 1)]);
        expect(observations, hasLength(1));
      });

      test('foreign query fields and reused nested occurrences fail before execution', () async {
        final foreign = accountTable.alias();
        await expectLater(
          db.event
              .where(
                (e) =>
                    e.author.where((a) => a.id.equals(foreign.fields.id)).any(),
              )
              .get(),
          throwsA(_code('QUERY.SCOPE')),
        );
        await expectLater(
          db.event.where((e) {
            final author = e.author;
            return author.where((a) => author.any()).any();
          }).get(),
          throwsA(_code('QUERY.ALIAS')),
        );
        expect(observations, isEmpty);
      });

      test('relationship aggregate and window predicates fail before all CRUD execution', () async {
        for (final predicate in <Expr<bool?> Function(AccountFields)>[
          (a) => a.id.count().gt(0),
          (a) => rowNumber(orderBy: [a.id.asc()]).gt(0),
        ]) {
          final query = db.event.where((e) => e.author.where(predicate).any());
          await expectLater(query.get(), throwsA(_code('QUERY.AGGREGATE')));
          await expectLater(
            query.update((e) => [e.score.increment(1)]).execute(),
            throwsA(_code('QUERY.AGGREGATE')),
          );
          await expectLater(
            query.delete().execute(),
            throwsA(_code('QUERY.AGGREGATE')),
          );
          await expectLater(
            db.event.where((e) => e.author.where(predicate).none()).get(),
            throwsA(_code('QUERY.AGGREGATE')),
          );
          await expectLater(
            db.event.where((e) => e.author.every(predicate)).get(),
            throwsA(_code('QUERY.AGGREGATE')),
          );
          await expectLater(
            db.event.select((e) => e.author.where(predicate).count()).get(),
            throwsA(_code('QUERY.AGGREGATE')),
          );
        }
        expect(observations, isEmpty);
      });

      test('relation pagination and joined or paginated mutations have explicit diagnostics', () async {
        for (final quantifier
            in <Expr<bool?> Function(Relation<Event, EventFields>)>[
              (r) => r.any(),
              (r) => r.none(),
              (r) => r.every((e) => e.score.gt(0)),
              (r) => r.count().gt(0),
            ]) {
          await expectLater(
            db.account.where((a) => quantifier(a.events.take(1))).get(),
            throwsA(_code('RELATION.AGGREGATE')),
          );
        }
        final joined = accountTable.alias();
        final queries = [
          db.event.take(1),
          db.event.skip(1),
          db.event.orderBy((e) => [e.id.asc()]),
          db.event.join(joined, on: (e, a) => e.owner.equals(a.id)),
        ];
        for (final query in queries) {
          await expectLater(
            query.update((e) => [e.score.increment(1)]).execute(),
            throwsA(_code('MUTATION.QUERY')),
          );
          await expectLater(
            query.delete().execute(),
            throwsA(_code('MUTATION.QUERY')),
          );
        }
        expect(observations, isEmpty);
      });
    },
    tags: engine,
    skip: skip,
  );
}
