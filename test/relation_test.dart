@Tags(['database'])
library;

import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart' hide allOf, anyOf;

import 'support/relations/schema.orm.dart';

Matcher code(String expected) =>
    isA<OrmException>().having((e) => e.code, 'code', expected);

void main() {
  runTests(
    'sqlite',
    (observe) => sqlite(const SqliteOptions.memory(), onQuery: observe),
  );
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    runTests('postgres', (observe) async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: PostgresTls.disable,
          schema: 'orm_relation_tests',
        ),
        onQuery: observe,
      );
      await db.execute(
        SqlCommand('DROP SCHEMA IF EXISTS orm_relation_tests CASCADE'),
      );
      await db.execute(SqlCommand('CREATE SCHEMA orm_relation_tests'));
      return db;
    });
  }
}

void runTests(
  String name,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open,
) {
  group(name, () {
    late Database<Backend> db;
    final events = <QueryEvent>[];
    setUp(() async {
      db = await open(events.add);
      await Migrator(db.sql).apply([
        Migration.create('0001_initial', appSchema, dialect: db.dialect),
      ]);
      await db.execute(
        SqlCommand(
          'INSERT INTO accounts(tenant,id,label,manager_id) VALUES '
          "(1,1,NULL,NULL),(1,2,'A2',1),(1,3,'A3',NULL),(2,1,'B1',NULL),(2,2,'B2',1)",
        ),
      );
      await db.execute(
        SqlCommand(
          'INSERT INTO events(id,tenant,owner,reviewer,title,score) VALUES '
          "(1,1,1,2,'e1',1),(2,1,1,NULL,'e2',2),(3,1,2,1,'e3',3),(4,1,2,NULL,'e4',4),"
          "(5,2,1,2,'e5',5),(6,2,1,NULL,'e6',6),(7,2,2,1,'e7',7),(8,2,2,NULL,'e8',8),"
          "(9,NULL,1,NULL,'e9',9),(10,1,NULL,NULL,'e10',10)",
        ),
      );
      events.clear();
    });
    tearDown(() => db.close());

    test(
      'automatic unique joins preserve root pagination in one statement',
      () async {
        final rows = await db.event
            .orderBy((e) => [e.id.asc()])
            .skip(2)
            .take(4)
            .select(
              (e) => (
                e.id,
                e.author
                    .select(
                      (a) => (
                        a.tenant,
                        a.id,
                      ).map((tenant, id) => (tenant: tenant, id: id)),
                    )
                    .required(),
              ).map((id, owner) => (id: id, owner: owner)),
            )
            .get();
        expect(rows.map((r) => r.id), [3, 4, 5, 6]);
        expect(rows.map((r) => r.owner), [
          (tenant: 1, id: 2),
          (tenant: 1, id: 2),
          (tenant: 2, id: 1),
          (tenant: 2, id: 1),
        ]);
        expect(events.length, 1);
        expect(events.single.sql, contains('LEFT JOIN'));
      },
    );

    test(
      'all-null projections still distinguish a present row from absence',
      () async {
        final rows = await db.event
            .orderBy((e) => [e.id.asc()])
            .select(
              (e) => e.author
                  .select(
                    (a) => (
                      a.label,
                      a.note,
                    ).map((label, note) => (label: label, note: note)),
                  )
                  .one(),
            )
            .get();
        expect(rows[0], (label: null, note: null));
        expect(rows[8], isNull);
        expect(rows[9], isNull);
        expect(events.length, 1);
      },
    );

    test(
      'explicit batch deduplicates composite keys and skips partial nulls',
      () async {
        final limited = Database(
          _LimitedDriver(db.driver, 7),
          onQuery: events.add,
        );
        final rows = await limited.event
            .orderBy((e) => [e.id.asc()])
            .select(
              (e) => e.author
                  .select(
                    (a) => (
                      a.tenant,
                      a.id,
                    ).map((tenant, id) => (tenant: tenant, id: id)),
                  )
                  .one(strategy: .batch),
            )
            .get();
        expect(rows, [
          (tenant: 1, id: 1),
          (tenant: 1, id: 1),
          (tenant: 1, id: 2),
          (tenant: 1, id: 2),
          (tenant: 2, id: 1),
          (tenant: 2, id: 1),
          (tenant: 2, id: 2),
          (tenant: 2, id: 2),
          null,
          null,
        ]);
        expect(events.length, 3);
        expect(events.skip(1).every((e) => e.parameterCount <= 7), isTrue);
        events.clear();
        expect(
          await limited.event
              .where((e) => e.id.gt(8))
              .select((e) => e.author.one(strategy: .batch))
              .get(),
          [null, null],
        );
        expect(events.length, 1);
      },
    );

    test(
      'composite chunks include filter and window parameters with nested joins',
      () async {
        final limited = Database(
          _LimitedDriver(db.driver, 9),
          onQuery: events.add,
        );
        final rows = await limited.account
            .orderBy((a) => [a.tenant.asc(), a.id.asc()])
            .select(
              (a) => a.events
                  .where((e) => e.score.gt(0))
                  .orderBy((e) => [e.id.desc()])
                  .skip(1)
                  .take(1)
                  .select(
                    (e) => (
                      e.title,
                      e.author
                          .where((a) => a.id.gt(0))
                          .select((a) => a.tenant)
                          .required(),
                    ).map((title, tenant) => (title: title, tenant: tenant)),
                  )
                  .many(),
            )
            .get();
        expect(rows, [
          [(title: 'e1', tenant: 1)],
          [(title: 'e3', tenant: 1)],
          <({String title, int tenant})>[],
          [(title: 'e5', tenant: 2)],
          [(title: 'e7', tenant: 2)],
        ]);
        expect(events.length, 4);
        expect(events.skip(1).every((e) => e.parameterCount <= 9), isTrue);
        expect(
          events
              .skip(1)
              .every(
                (e) =>
                    e.sql.contains('LEFT JOIN') &&
                    e.sql.contains('PARTITION BY'),
              ),
          isTrue,
        );
      },
    );

    test(
      'nested self joins and two edges to the same table use distinct aliases',
      () async {
        final rows = await db.event
            .where((e) => e.id.eq(3))
            .select(
              (e) => (
                e.author
                    .select(
                      (a) => (
                        a.id,
                        a.manager.select((m) => m.id).one(),
                      ).map((id, manager) => (id: id, manager: manager)),
                    )
                    .required(),
                e.reviewerAccount.select((a) => a.id).required(),
              ).map((author, reviewer) => (author: author, reviewer: reviewer)),
            )
            .get();
        expect(rows, [(author: (id: 2, manager: 1), reviewer: 1)]);
        expect(events.length, 1);
        expect('LEFT JOIN'.allMatches(events.single.sql).length, 3);
      },
    );

    test(
      'batch collection below a joined optional parent loads on the same plan',
      () async {
        final rows = await db.event
            .where((e) => anyOf([e.id.eq(1), e.id.eq(9)]))
            .orderBy((e) => [e.id.asc()])
            .select(
              (e) => e.author
                  .select(
                    (a) => (
                      a.id,
                      a.events
                          .orderBy((e) => [e.id.asc()])
                          .take(1)
                          .select((e) => e.title)
                          .many(),
                    ).map((id, titles) => (id: id, titles: titles)),
                  )
                  .one(),
            )
            .get();
        expect(rows.first!.id, 1);
        expect(rows.first!.titles, ['e1']);
        expect(rows.last, isNull);
        expect(events.length, 2);
      },
    );

    test(
      'join refuses unproven cardinality while automatic batch checks it',
      () async {
        expect(
          () => db.account.select((a) => a.events.one(strategy: .join)),
          throwsA(code('RELATION.JOIN_KEY')),
        );
        expect(events, isEmpty);
        await expectLater(
          db.account.byId(tenant: 1, id: 1).select((a) => a.events.one()).get(),
          throwsA(code('RELATION.CARDINALITY')),
        );
      },
    );

    test('filters and to-one pagination do not drop root rows', () async {
      for (final strategy in [ToOneStrategy.join, ToOneStrategy.batch]) {
        final query = db.event.where((e) => e.id.eq(3));
        expect(
          await query
              .select(
                (e) =>
                    e.author.where((a) => a.id.eq(99)).one(strategy: strategy),
              )
              .single(),
          isNull,
        );
        expect(
          await query
              .select((e) => e.author.take(0).one(strategy: strategy))
              .single(),
          isNull,
        );
        expect(
          await query
              .select((e) => e.author.skip(1).one(strategy: strategy))
              .single(),
          isNull,
        );
        await expectLater(
          query
              .select(
                (e) => e.author
                    .where((a) => a.id.eq(99))
                    .required(strategy: strategy),
              )
              .get(),
          throwsA(code('RELATION.MISSING')),
        );
      }
    });

    test('joined records survive CTE projection and cursor decoding', () async {
      final cte = db.event
          .orderBy((e) => [e.id.asc()])
          .select(
            (e) => (
              e.id,
              e.author.select((a) => a.id).one(),
            ).map((id, owner) => (id: id, owner: owner)),
          )
          .asCte('cards');
      final rows = await cte.query
          .orderBy((c) => [c.ref((e) => e.id).asc()])
          .stream(batchSize: 3)
          .toList();
      expect(rows.map((r) => r.owner), [1, 1, 2, 2, 1, 1, 2, 2, null, null]);
      expect(events.where((e) => e.operation == .cursorOpen).length, 1);
      expect(
        events.where((e) => e.operation == .cursorFetch).map((e) => e.rowCount),
        [3, 3, 3, 1],
      );
    });

    test(
      'required tests row presence independently of nullable selected values',
      () async {
        for (final strategy in [ToOneStrategy.join, ToOneStrategy.batch]) {
          final result = await db.event
              .byId(1)
              .select(
                (e) => e.author
                    .select((a) => a.label)
                    .required(strategy: strategy),
              )
              .single();
          expect(result, isNull);
          await expectLater(
            db.event
                .byId(9)
                .select(
                  (e) => e.author
                      .select((a) => a.label)
                      .required(strategy: strategy),
                )
                .get(),
            throwsA(code('RELATION.MISSING')),
          );
        }
      },
    );

    test(
      'relation aggregates restore the alias used by a joined selection',
      () async {
        final row = await db.event.byId(3).select((e) {
          final author = e.author;
          return (
            author.select((a) => a.id).required(),
            author.count(),
            author.any(),
          ).map((id, count, exists) => (id: id, count: count, exists: exists));
        }).single();
        expect(row, (id: 2, count: 1, exists: true));
        expect(events.length, 1);
      },
    );

    test('reusing an identical edge deduplicates its join', () async {
      final query = db.event.where((e) => e.id.eq(3)).select((e) {
        final author = e.author;
        return (
          author.select((a) => a.id).required(),
          author.select((a) => a.label).one(),
        ).map((id, label) => (id: id, label: label));
      });
      expect(await query.single(), (id: 2, label: 'A2'));
      expect('LEFT JOIN'.allMatches(events.single.sql).length, 1);
    });

    test('different filters need fresh relation occurrences', () async {
      final query = db.event.select((e) {
        final author = e.author;
        return (
          author.where((a) => a.id.eq(1)).one(),
          author.where((a) => a.id.eq(2)).one(),
        ).map((a, b) => (a, b));
      });
      await expectLater(query.get(), throwsA(code('RELATION.ALIAS')));
      expect(events, isEmpty);
    });

    test('large composite batches avoid expression-depth failure', () async {
      await db.execute(
        SqlCommand(
          'WITH RECURSIVE n(x) AS ('
          'SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1200) '
          'INSERT INTO accounts(tenant,id) SELECT 3,x FROM n',
        ),
      );
      await db.execute(
        SqlCommand(
          'INSERT INTO events(id,tenant,owner,title,score) '
          "SELECT id+100,3,id,'large'||id,id FROM accounts WHERE tenant=3",
        ),
      );
      events.clear();
      final rows = await db.account
          .where((a) => a.tenant.eq(3))
          .orderBy((a) => [a.id.asc()])
          .select((a) => a.events.select((e) => e.title).many())
          .get();
      expect(rows.length, 1200);
      expect(rows.first, ['large1']);
      expect(rows.last, ['large1200']);
      expect(events.length, 2);
      expect(events.last.parameterCount, 2400);
      expect(events.last.sql, isNot(contains(' OR ')));
    });
  }, tags: name);
}

final class _LimitedDriver(final Driver<Backend> inner, final int limit)
    implements Driver<Backend> {
  @override
  Capabilities get capabilities => Capabilities(
    dialect: inner.capabilities.dialect,
    maxParameters: limit,
    streaming: inner.capabilities.streaming,
    cancellation: inner.capabilities.cancellation,
  );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      inner.run(action);
  @override
  Future<void> close() async {}
}
