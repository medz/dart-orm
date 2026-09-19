import 'dart:async';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/teams/schema.dart';
import '../example/teams/schema.orm.dart';

final day1 = DateTime.utc(2026, 1, 1), day2 = DateTime.utc(2026, 1, 2);

void main() {
  for (final dialect in [SqlDialect.sqlite, SqlDialect.postgres]) {
    group(
      'many-to-many ${dialect.name}',
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
                schema: 'orm_many_to_many_tests',
              ),
              onQuery: events.add,
            );
            await db.execute(
              SqlCommand(
                'DROP SCHEMA IF EXISTS orm_many_to_many_tests CASCADE',
              ),
            );
            await db.execute(
              SqlCommand('CREATE SCHEMA orm_many_to_many_tests'),
            );
          }
          await Migrator(db.sql).apply([
            Migration.create('0001_teams', appSchema, dialect: db.dialect),
          ]);
          await db.transaction((tx) async {
            await tx.users.insertMany(
              [(1, 'Ada'), (2, 'Ben'), (3, 'Cy'), (4, 'Dee')],
              (u, value) => [u.id.set(value.$1), u.name.set(value.$2)],
            ).execute();
            await tx.teams.insertMany(
              [(10, 'Core'), (20, 'Docs'), (30, 'Tools'), (40, 'Empty')],
              (t, value) => [t.id.set(value.$1), t.name.set(value.$2)],
            ).execute();
            await tx.memberships.insertMany(
              [
                (10, 1, MembershipRole.owner, day1),
                (10, 2, MembershipRole.member, day2),
                (10, 3, MembershipRole.member, day2),
                (20, 1, MembershipRole.member, day2),
                (20, 2, MembershipRole.owner, day1),
                (30, 1, MembershipRole.member, day2),
              ],
              (m, value) => [
                m.teamId.set(value.$1),
                m.userId.set(value.$2),
                m.role.set(value.$3),
                m.joinedAt.set(value.$4),
              ],
            ).execute();
          });
          events.clear();
        });
        tearDown(() => db.close());

        test('two declared FKs and a composite primary key enforce association identity', () async {
          final info = await inspectTable(db.sql, 'memberships');
          expect(info.primaryKey, ['team_id', 'user_id']);
          expect(info.foreignKeys.map((k) => k.target).toSet(), {
            'teams',
            'users',
          });
          expect(info.foreignKeys.every((k) => k.onDelete == 'CASCADE'), true);
          expect(info.indexes.map((i) => i.name), ['user_memberships']);
          expect(
            (await verifySchema(db.sql, SchemaSnapshot(appSchema))).differences,
            isEmpty,
          );
          await expectLater(
            db.memberships.create(teamId: 10, userId: 1, joinedAt: day2),
            throwsA(isA<SqlFailure>()),
          );
          await expectLater(
            db.memberships.create(teamId: 999, userId: 4, joinedAt: day2),
            throwsA(isA<SqlFailure>()),
          );
          await expectLater(
            db.memberships.create(teamId: 40, userId: 999, joinedAt: day2),
            throwsA(isA<SqlFailure>()),
          );
          expect(await db.memberships.count(), 6);
        });

        test('forward projection keeps payload, shared targets and per-user limits in two statements', () async {
          final query = db.users
              .orderBy((u) => [u.id.asc()])
              .select(
                (u) =>
                    (
                      u.name,
                      u.memberships
                          .orderBy((m) => [m.joinedAt.desc(), m.teamId.desc()])
                          .take(2)
                          .select(
                            (m) =>
                                (
                                  m.team.select((t) => t.name).required(),
                                  m.role,
                                  m.joinedAt,
                                ).map(
                                  (team, role, joinedAt) => (
                                    team: team,
                                    role: role,
                                    joinedAt: joinedAt,
                                  ),
                                ),
                          )
                          .many(),
                    ).map(
                      (name, memberships) =>
                          (name: name, memberships: memberships),
                    ),
              );
          query.compile();
          expect(events, isEmpty);
          final List<
            ({
              String name,
              List<({String team, MembershipRole role, DateTime joinedAt})>
              memberships,
            })
          >
          rows = await query.get();
          expect(rows.map((r) => r.name), ['Ada', 'Ben', 'Cy', 'Dee']);
          expect(
            rows.map(
              (r) => r.memberships.map((m) => (m.team, m.role)).toList(),
            ),
            [
              [
                ('Tools', MembershipRole.member),
                ('Docs', MembershipRole.member),
              ],
              [('Core', MembershipRole.member), ('Docs', MembershipRole.owner)],
              [('Core', MembershipRole.member)],
              <(String, MembershipRole)>[],
            ],
          );
          expect(rows[0].memberships.every((m) => m.joinedAt == day2), true);
          expect(events, hasLength(2));
          expect(events.map((e) => e.rowCount), [4, 5]);
          expect(events.last.sql, contains('PARTITION BY'));
          expect(events.last.sql, contains('LEFT JOIN'));
        });

        test('reverse projection applies tie-breaking and offset to each team without changing root pagination', () async {
          final rows = await db.teams
              .orderBy((t) => [t.id.asc()])
              .take(3)
              .select(
                (t) => (
                  t.name,
                  t.memberships
                      .orderBy((m) => [m.joinedAt.desc(), m.userId.desc()])
                      .skip(1)
                      .take(1)
                      .select((m) => m.user.select((u) => u.name).required())
                      .many(),
                ).map((team, users) => (team, users)),
              )
              .get();
          expect(rows.map((r) => r.$1), ['Core', 'Docs', 'Tools']);
          expect(rows.map((r) => r.$2), [
            ['Ben'],
            ['Ben'],
            <String>[],
          ]);
          expect(events, hasLength(2));
          expect(events.map((e) => e.rowCount), [3, 2]);
          events.clear();
          expect(
            await db.users
                .where((u) => u.id.eq(999))
                .select((u) => u.memberships.many())
                .get(),
            isEmpty,
          );
          expect(events, hasLength(1));
        });

        test(
          'nested team rosters deduplicate shared team keys and batch by level',
          () async {
            final rows = await db.users
                .orderBy((u) => [u.id.asc()])
                .select(
                  (u) => (
                    u.name,
                    u.memberships
                        .orderBy((m) => [m.teamId.asc()])
                        .select(
                          (m) => m.team
                              .select(
                                (t) =>
                                    (
                                      t.name,
                                      t.memberships
                                          .orderBy(
                                            (member) => [member.userId.asc()],
                                          )
                                          .select(
                                            (member) => member.user
                                                .select((person) => person.name)
                                                .required(),
                                          )
                                          .many(),
                                    ).map(
                                      (name, roster) =>
                                          (name: name, roster: roster),
                                    ),
                              )
                              .required(),
                        )
                        .many(),
                  ).map((name, teams) => (name: name, teams: teams)),
                )
                .get();
            expect(rows.map((r) => r.teams.map((t) => t.name).toList()), [
              ['Core', 'Docs', 'Tools'],
              ['Core', 'Docs'],
              ['Core'],
              <String>[],
            ]);
            expect(rows.map((r) => r.teams.map((t) => t.roster).toList()), [
              [
                ['Ada', 'Ben', 'Cy'],
                ['Ada', 'Ben'],
                ['Ada'],
              ],
              [
                ['Ada', 'Ben', 'Cy'],
                ['Ada', 'Ben'],
              ],
              [
                ['Ada', 'Ben', 'Cy'],
              ],
              <List<String>>[],
            ]);
            expect(rows[3].teams, isEmpty);
            expect(events, hasLength(3));
            expect(events.map((e) => e.rowCount), [4, 6, 6]);
          },
        );

        test(
          'association predicates and counts stay in one SQL statement',
          () async {
            final rows = await db.users
                .orderBy((u) => [u.id.asc()])
                .select(
                  (u) => (
                    u.name,
                    u.memberships.count(),
                    u.memberships.every(
                      (m) => m.role.eq(MembershipRole.member),
                    ),
                    u.memberships
                        .where(
                          (m) => m.team.where((t) => t.name.eq('Core')).any(),
                        )
                        .any(),
                  ).row,
                )
                .get();
            expect(rows, [
              ('Ada', 3, false, true),
              ('Ben', 2, false, true),
              ('Cy', 1, true, true),
              ('Dee', 0, true, false),
            ]);
            expect(events, hasLength(1));
            expect(events.single.rowCount, 4);
          },
        );

        test('limited parameter capacity chunks associations without changing per-parent limits', () async {
          final limited = Database(
            _LimitedDriver(db.driver),
            onQuery: events.add,
          );
          final rows = await limited.users
              .orderBy((u) => [u.id.asc()])
              .select(
                (u) => u.memberships
                    .where((m) => m.role.eq(MembershipRole.member))
                    .orderBy((m) => [m.joinedAt.desc(), m.teamId.desc()])
                    .take(2)
                    .select((m) => m.team.select((t) => t.name).required())
                    .many(),
              )
              .get();
          expect(rows, [
            ['Tools', 'Docs'],
            ['Core'],
            ['Core'],
            <String>[],
          ]);
          expect(events, hasLength(3));
          expect(events.map((e) => e.rowCount), [4, 3, 1]);
          expect(events.skip(1).every((e) => e.parameterCount <= 5), true);
        });

        test('transaction rollback restores payload changes and new endpoints after an invalid association', () async {
          await expectLater(
            db.transaction((tx) async {
              await tx.memberships
                  .byId(teamId: 10, userId: 1)
                  .patch(role: .set(MembershipRole.member));
              await tx.users.create(id: 5, name: 'Eve');
              await tx.teams.create(id: 50, name: 'New');
              await tx.memberships.create(
                teamId: 50,
                userId: 5,
                joinedAt: day2,
              );
              await tx.memberships.create(
                teamId: 999,
                userId: 5,
                joinedAt: day2,
              );
            }),
            throwsA(isA<SqlFailure>()),
          );
          expect(
            (await db.memberships.byId(teamId: 10, userId: 1).single()).role,
            MembershipRole.owner,
          );
          expect(await db.users.byId(5).exists(), false);
          expect(await db.teams.byId(50).exists(), false);
          expect(await db.memberships.count(), 6);
        });

        test('composite-key conflict updates preserve membership dates and unlinking keeps endpoints', () async {
          await db.transaction((tx) async {
            final rows = await tx.memberships
                .insert(
                  (m) => [
                    m.teamId.set(10),
                    m.userId.set(2),
                    m.joinedAt.set(day1),
                    m.role.set(MembershipRole.owner),
                  ],
                )
                .onConflictUpdate(
                  target: (m) => [m.teamId, m.userId],
                  set: (old, incoming) => [
                    old.role.setExpression(incoming.role),
                  ],
                )
                .returning((m) => (m.role, m.joinedAt).row)
                .get();
            expect(rows, [(MembershipRole.owner, day2)]);
            await tx.memberships.byId(teamId: 10, userId: 1).delete().execute();
          });
          expect(await db.users.count(), 4);
          expect(await db.teams.count(), 4);
          expect(await db.memberships.count(), 5);
          await db.teams.byId(20).delete().execute();
          await db.users.byId(1).delete().execute();
          expect(await db.memberships.count(), 2);
          expect(await db.users.count(), 3);
          expect(await db.teams.count(), 3);
          expect(
            (await db.memberships.orderBy((m) => [m.userId.asc()]).get()).map(
              (m) => (m.teamId, m.userId),
            ),
            [(10, 2), (10, 3)],
          );
        });

        test('watch tracks junction payload and opposite endpoint changes after commit', () async {
          final iterator = StreamIterator(
            db.users
                .byId(1)
                .select(
                  (u) => u.memberships
                      .orderBy((m) => [m.teamId.asc()])
                      .select(
                        (m) => (
                          m.team.select((t) => t.name).required(),
                          m.role,
                        ).map((team, role) => (team, role)),
                      )
                      .many(),
                )
                .watch(),
          );
          try {
            expect(
              await iterator.moveNext().timeout(const Duration(seconds: 5)),
              true,
            );
            expect(iterator.current.single.first, (
              'Core',
              MembershipRole.owner,
            ));
            await db.transaction((tx) async {
              await tx.teams.byId(10).patch(name: .set('Kernel'));
              await tx.memberships
                  .byId(teamId: 10, userId: 1)
                  .patch(role: .set(MembershipRole.member));
            });
            expect(
              await iterator.moveNext().timeout(const Duration(seconds: 5)),
              true,
            );
            expect(iterator.current.single.first, (
              'Kernel',
              MembershipRole.member,
            ));
            await db.teams.byId(10).delete().execute();
            expect(
              await iterator.moveNext().timeout(const Duration(seconds: 5)),
              true,
            );
            expect(iterator.current.single.map((m) => m.$1), ['Docs', 'Tools']);
          } finally {
            await iterator.cancel();
          }
        });
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
    );
  }
}

final class _LimitedDriver(final Driver<Backend> inner)
    implements Driver<Backend> {
  @override
  Capabilities get capabilities => Capabilities(
    dialect: inner.capabilities.dialect,
    maxParameters: 5,
    returning: inner.capabilities.returning,
    windowFunctions: inner.capabilities.windowFunctions,
    streaming: inner.capabilities.streaming,
    cancellation: inner.capabilities.cancellation,
    exactDecimal: inner.capabilities.exactDecimal,
    temporal: inner.capabilities.temporal,
  );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      inner.run(action);
  @override
  Future<void> close() async {}
}
