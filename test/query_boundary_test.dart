import 'dart:async';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart' hide allOf, anyOf;

import 'support/tables.dart';

Matcher code(String value) =>
    isA<OrmException>().having((e) => e.code, 'code', value);

void main() {
  test('one failing cancellation listener cannot block other operations', () {
    final token = CancellationToken();
    var notified = 0;
    token.listen(() => throw StateError('listener'));
    token.listen(() => notified++);
    token.cancel();
    token.cancel();
    token.listen(() => notified++);
    expect(notified, 2);
  });
  run(
    'sqlite',
    (observe) => sqlite(const SqliteOptions.memory(), onQuery: observe),
  );
  if (Platform.environment['ORM_TEST_POSTGRES'] case final url?) {
    run('postgres', (observe) async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          schema: 'orm_boundary_tests',
        ),
        onQuery: observe,
      );
      await db.execute(
        SqlCommand('DROP SCHEMA IF EXISTS orm_boundary_tests CASCADE'),
      );
      await db.execute(SqlCommand('CREATE SCHEMA orm_boundary_tests'));
      return db;
    });
  }
}

void run(
  String name,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open,
) {
  group(name, () {
    late Database<Backend> db;
    final events = <QueryEvent>[];
    setUp(() async {
      db = await open(events.add);
      await Migrator(db.sql).apply([
        Migration.create('0001_initial', [
          usersSchema,
          postsSchema,
        ], dialect: db.dialect),
      ]);
      await db.table(users).createRow((u) => [u.email.set('one')]);
      await db.table(users).createRow((u) => [u.email.set('two')]);
      events.clear();
    });
    tearDown(() => db.close());

    test('explicit Backend construction rejects wrong transaction options before SQL', () {
      final TransactionOptions<Backend> wrong = db.dialect == .sqlite
          ? const PostgresTransaction()
          : const SqliteTransaction();
      final wide = Database<Backend>(db.driver, onQuery: events.add);
      expect(
        () => wide.transaction((tx) async {}, options: wrong),
        throwsA(code('TRANSACTION.OPTIONS')),
      );
      expect(events, isEmpty);
    });

    test(
      'every close caller waits until the same pending lease is drained',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final lease = db.session((session) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var closed = false;
        final first = db.close();
        final second = db.close().then((_) => closed = true);
        try {
          await Future<void>.delayed(Duration.zero);
          expect(closed, false);
        } finally {
          release.complete();
          await lease;
          await first;
          await second;
        }
        expect(closed, true);
      },
    );

    test(
      'subqueries and CTEs cannot escape their database or transaction',
      () async {
        await db.transaction((tx) async {
          final rootIds = db.table(users).select((u) => u.id);
          final cte = rootIds.asCte('root_ids').alias();
          final queries = [
            tx.table(users).where((u) => u.id.isInQuery(rootIds)),
            tx.table(users).select((_) => rootIds.take(1).scalar()),
            tx.table(users).where((_) => rootIds.existsExpression()),
            tx
                .table(users)
                .join(cte, on: (u, c) => u.id.eq(c.ref((u) => u.id))),
          ];
          events.clear();
          for (final query in queries) {
            expect(query.compile, throwsA(code('QUERY.SESSION')));
            await expectLater(query.get(), throwsA(code('QUERY.SESSION')));
          }
          await expectLater(
            tx
                .table(users)
                .where((u) => u.id.isInQuery(rootIds))
                .delete()
                .execute(),
            throwsA(code('QUERY.SESSION')),
          );
          expect(events, isEmpty);
          final localIds = tx
              .table(users)
              .where((u) => u.email.eq(.value('one')))
              .select((u) => u.id);
          expect(
            await tx
                .table(users)
                .where((u) => u.id.isInQuery(localIds))
                .count(),
            1,
          );
        });
      },
    );

    test('expired query cannot be embedded in its former parent', () async {
      final expired = await db.session(
        (session) async => session.table(users).select((u) => u.id),
      );
      expect(
        () => db.table(users).where((u) => u.id.isInQuery(expired)).compile(),
        throwsA(code('QUERY.SESSION')),
      );
      expect(events, isEmpty);
    });

    test('optional presence covers only its own left join', () async {
      final present = users.alias(), absent = users.alias();
      final query = db
          .table(users)
          .leftJoin(present, on: (u, p) => u.id.eq(p.id))
          .leftJoin(absent, on: (u, a) => a.id.eq(.value(-1)));
      expect(
        () => query
            .select((_) => present.optional(absent.fields.email))
            .compile(),
        throwsA(code('QUERY.NULLABILITY')),
      );
      expect(events, isEmpty);
      expect(
        await query
            .select(
              (_) => present.optional(
                (
                  present.fields.email,
                  absent.optional(absent.fields.email),
                ).rowMap,
              ),
            )
            .get(),
        [('one', null), ('two', null)],
      );
    });

    test('nested CTE decoding retains its nullable presence guards', () async {
      final alias = users.alias();
      final source = db
          .table(users)
          .leftJoin(
            alias,
            on: (u, a) => allOf([u.id.eq(a.id), a.id.eq(.value(1))]),
          )
          .select((_) => alias.optional(alias.fields.email))
          .asCte('optional_email');
      expect(await source.query.asCte('rebound_email').query.get(), [
        'one',
        null,
      ]);
    });

    test('mutation predicates and assignments reject aggregate/window SQL before execution', () async {
      for (final mutation in [
        db.table(users).where((u) => u.id.count().gt(.value(0))).delete(),
        db.table(users).update((u) => [u.score.setExpression(u.id.count())]),
        db.table(users).update((u) => [u.score.setExpression(rowNumber())]),
      ]) {
        await expectLater(mutation.execute(), throwsA(code('QUERY.AGGREGATE')));
      }
      expect(events, isEmpty);
      expect(await db.table(users).count(), 2);
    });

    test(
      'returning rejects empty selections and joined relationships',
      () async {
        await expectLater(
          db
              .table(users)
              .insert((u) => [u.email.set('three')])
              .returning((_) => fields({}))
              .get(),
          throwsA(code('QUERY.EMPTY_SELECTION')),
        );
        await expectLater(
          db
              .table(postsTable)
              .insert((p) => [p.authorId.set(1), p.title.set('title')])
              .returning((p) => p.author.one())
              .get(),
          throwsA(code('MUTATION.RELATION')),
        );
        expect(events, isEmpty);
      },
    );
  }, tags: name);
}

extension<A, B> on (Selection<A>, Selection<B>) {
  Selection<(A, B)> get rowMap => map((a, b) => (a, b));
}
