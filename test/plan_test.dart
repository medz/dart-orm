import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/teams/schema.dart';
import '../example/teams/schema.orm.dart';
import 'support/relations/schema.orm.dart' as composite;

void main() {
  for (final dialect in SqlDialect.values) {
    test(
      'inspect ${dialect.name} reports composite key width and validates each potential batch',
      () {
        final db = Database(_NoConnection(dialect));
        final query = db
            .table(composite.accountsTable)
            .select(
              (a) => a.events
                  .orderBy((e) => [e.id.asc()])
                  .take(1)
                  .select((e) => e.title)
                  .many(),
            );
        final load = query.inspect().loads.single;
        expect(load.keyWidth, 2);
        expect(load.parentColumns, hasLength(2));
        expect(load.childColumns, hasLength(2));
        expect(load.fixedParameters, 2);
        expect(load.maxKeysPerBatch, 1);
        expect(load.query!.sql, contains('PARTITION BY'));
        expect(
          () => db.users.select((u) => u.memberships.take(1).many()).inspect(),
          throwsA(
            isA<OrmException>().having((e) => e.code, 'code', 'RELATION.ORDER'),
          ),
        );
        expect(
          () => db
              .table(composite.accountsTable)
              .select(
                (a) => a.events
                    .where((e) => e.id.gt(0).and(e.score.gt(0)))
                    .orderBy((e) => [e.id.asc()])
                    .take(1)
                    .many(),
              )
              .inspect(),
          throwsA(
            isA<OrmException>().having(
              (e) => e.code,
              'code',
              'QUERY.PARAMETERS',
            ),
          ),
        );
      },
    );
    test(
      'inspect ${dialect.name} compiles nested plans without acquiring or decoding',
      () {
        final driver = _NoConnection(dialect), db = Database(driver);
        var decoded = false;
        final query = db.users
            .where((u) => u.name.eq('bound-secret'))
            .select(
              (u) =>
                  (
                    u.name,
                    u.memberships
                        .where((m) => m.role.eq(MembershipRole.member))
                        .orderBy((m) => [m.joinedAt.desc(), m.teamId.desc()])
                        .take(2)
                        .select(
                          (m) => m.team
                              .select(
                                (t) =>
                                    (
                                      t.name,
                                      t.memberships
                                          .orderBy((m) => [m.userId.asc()])
                                          .select(
                                            (m) => m.user
                                                .select((u) => u.name)
                                                .required(),
                                          )
                                          .many(),
                                    ).map(
                                      (name, members) =>
                                          (name: name, members: members),
                                    ),
                              )
                              .required(),
                        )
                        .many(),
                  ).map((name, teams) {
                    decoded = true;
                    return (name, teams);
                  }),
            );
        final plan = query.inspect();
        expect(decoded, false);
        expect(plan.sql, query.compile().sql);
        expect(plan.parameterCount, 1);
        expect(plan.sqlTemplateCount, 3);
        expect(plan.reads, ['users']);
        expect(plan.opaqueReads, false);
        final load = plan.loads.single;
        expect(load.keyWidth, 1);
        expect(load.fixedParameters, 3);
        expect(load.maxKeysPerBatch, 2);
        expect(load.limitPerParent, 2);
        expect(load.query!.parameterCount, 4);
        expect(load.query!.sql, contains('PARTITION BY'));
        expect(load.query!.joins.single, (
          table: 'teams',
          left: true,
          relation: true,
        ));
        expect(load.query!.reads, ['memberships', 'teams']);
        expect(plan.columns[load.parentColumns.single].column, 'id');
        expect(load.query!.columns[load.childColumns.single].column, 'user_id');
        expect(load.query!.columns.any((c) => c.presence), true);
        expect(load.query!.loads.single.query!.joins.single.table, 'users');
        expect(jsonEncode(plan.toJson()), isNot(contains('bound-secret')));
        expect(jsonEncode(plan.toJson()), jsonEncode(query.inspect().toJson()));
        expect(() => plan.loads.clear(), throwsUnsupportedError);
        expect(() => load.parentColumns.clear(), throwsUnsupportedError);
      },
    );

    test(
      'inspect ${dialect.name} distinguishes same-statement joins and skipped batches',
      () {
        final db = Database(_NoConnection(dialect));
        final plan = db.memberships
            .select(
              (m) => (
                m.team.select((t) => t.name).one(),
                m.user.select((u) => u.name).required(),
              ).map((team, user) => (team, user)),
            )
            .inspect();
        expect(plan.sqlTemplateCount, 1);
        expect(plan.loads, isEmpty);
        expect(plan.joins.map((j) => j.table), ['teams', 'users']);
        final skipped = db.users
            .select((u) => u.memberships.take(0).many())
            .inspect();
        expect(skipped.loads.single.skipped, true);
        expect(skipped.loads.single.query, isNull);
        expect(skipped.sqlTemplateCount, 1);
      },
    );

    test(
      'inspect ${dialect.name} retains CTE, UNION and raw SQL boundaries',
      () {
        final db = Database(_NoConnection(dialect));
        final cte = db.users.select((u) => u.name).asCte('names');
        final plan = cte.query.union(db.teams.select((t) => t.name)).inspect();
        expect(plan.reads, ['teams', 'users']);
        expect(plan.sql, contains('UNION'));
        expect(plan.sqlTemplateCount, 1);
        final raw = db.users
            .select((u) => sql<int>(['length(name)'], [], Codecs.integer))
            .inspect();
        expect(raw.opaqueReads, true);
      },
    );

    group(
      'plan execution ${dialect.name}',
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
                schema: 'orm_plan_tests',
                tls: .disable,
              ),
              onQuery: events.add,
            );
            await db.execute(
              SqlCommand('DROP SCHEMA IF EXISTS orm_plan_tests CASCADE'),
            );
            await db.execute(SqlCommand('CREATE SCHEMA orm_plan_tests'));
          }
          await Migrator(db).apply([Migration.create('0001_teams', appSchema)]);
          await db.users.create(id: 1, name: 'Ada');
          await db.teams.create(id: 10, name: 'Core');
          await db.memberships.create(
            teamId: 10,
            userId: 1,
            joinedAt: DateTime.utc(2026),
          );
          events.clear();
        });
        tearDown(() => db.close());
        test(
          'one-key SQL templates match executed SQL and internal slots',
          () async {
            final query = db.users.select(
              (u) => u.memberships
                  .orderBy((m) => [m.teamId.asc()])
                  .take(2)
                  .select((m) => m.team.select((t) => t.name).required())
                  .many(),
            );
            final plan = query.inspect();
            expect(events, isEmpty);
            expect(await query.get(), [
              ['Core'],
            ]);
            expect(events.map((e) => e.sql), [
              plan.sql,
              plan.loads.single.query!.sql,
            ]);
            expect(events.map((e) => e.parameterCount), [
              plan.parameterCount,
              plan.loads.single.query!.parameterCount,
            ]);
            expect(
              plan.loads.single.maxKeysPerBatch,
              db.capabilities.maxParameters - 2,
            );
          },
        );
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
    );
  }
}

final class _NoConnection(final SqlDialect dialect) implements Driver<Backend> {
  @override
  Capabilities get capabilities => Capabilities(
    dialect: dialect,
    maxParameters: 5,
    temporal: true,
    exactDecimal: true,
  );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      throw StateError('Inspection acquired a connection.');
  @override
  Future<void> close() async {}
}
