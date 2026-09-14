import 'dart:async';
import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/tables.dart';

void main() {
  runDatabaseTests('sqlite', () => sqlite(const SqliteOptions.memory()));
  final postgresUrl = Platform.environment['ORM_TEST_POSTGRES'];
  if (postgresUrl != null) {
    runDatabaseTests(
      'postgres',
      () async => postgres(
        PostgresOptions(url: Uri.parse(postgresUrl), tls: PostgresTls.disable),
      ),
    );
  }
}

void runDatabaseTests(String name, Future<Database<Backend>> Function() open) {
  group(name, () {
    late Database<Backend> db;
    setUp(() async {
      db = await open();
      await db.execute(SqlCommand('DROP TABLE IF EXISTS posts'));
      await db.execute(SqlCommand('DROP TABLE IF EXISTS users'));
      await createTables(db);
    });
    tearDown(() => db.close());

    Future<User> create(String email, {String? nickname}) => db
        .table(users)
        .createRow((u) => [u.email.set(email), u.nickname.set(nickname)]);

    test('typed CRUD, exact projection and parameter binding', () async {
      const input = "a' OR 1=1 --";
      final user = await create(input);
      expect(user, (id: 1, email: input, nickname: null, score: 0));
      final query = db
          .table(users)
          .where((u) => u.email.eq(input))
          .select((u) => u.email);
      expect(query.compile().sql, isNot(contains(input)));
      expect(query.compile().sql, isNot(contains('nickname')));
      expect(query.compile().parameters, [input]);
      final List<String> emails = await query.get();
      expect(emails, [input]);
      await db
          .table(users)
          .where((u) => u.id.eq(user.id))
          .update((u) => [u.score.increment(2), u.nickname.set('Seven')])
          .execute();
      expect((await db.table(users).single()).score, 2);
      expect(
        await db
            .table(users)
            .where((u) => u.email.eq(input))
            .delete()
            .execute(),
        1,
      );
      expect(await db.table(users).exists(), false);
    });

    test('record and DTO mapping run only when decoding', () async {
      await create('one');
      var mapped = 0;
      final query = db
          .table(users)
          .select(
            (u) => (u.id, u.email).map((id, email) {
              mapped++;
              return (key: id, label: email);
            }),
          );
      query.compile();
      expect(mapped, 0);
      expect(await query.single(), (key: 1, label: 'one'));
      expect(mapped, 1);
    });

    test('immutable filters, empty IN, null and pagination', () async {
      for (var i = 0; i < 5; i++) {
        await create('user$i');
      }
      final base = db.table(users).orderBy((u) => [u.id.desc()]);
      expect(await base.count(), 5);
      expect(await base.take(2).count(), 2);
      expect(await base.skip(2).select((u) => u.id).get(), [3, 2, 1]);
      expect(await base.where((u) => u.id.isIn([])).exists(), false);
      expect(await base.where((u) => u.nickname.isNull()).count(), 5);
      expect(await base.take(0).first(), null);
      expect(base.single(), throwsA(isA<OrmException>()));
    });

    test(
      'cross-table identity and duplicate assignments rejected before IO',
      () async {
        late UserFields foreign;
        db.table(users).select((u) {
          foreign = u;
          return u.id;
        });
        expect(
          () => db.table(users).where((u) => u.id.equals(foreign.id)).compile(),
          throwsA(isA<OrmException>()),
        );
        expect(
          () => db
              .table(users)
              .update((u) => [u.score.set(1), u.score.set(2)])
              .compile(),
          throwsA(isA<OrmException>()),
        );
        expect(
          () => db.table(users).update((u) => []).compile(),
          throwsA(isA<OrmException>()),
        );
      },
    );

    test('commit, rollback, savepoint recovery and escaped session', () async {
      late Database<Backend> escaped;
      await db.transaction((tx) async {
        escaped = tx;
        await tx.table(users).createRow((u) => [u.email.set('kept')]);
        await expectLater(
          tx.savepoint((sp) async {
            await sp.table(users).createRow((u) => [u.email.set('discarded')]);
            throw StateError('rollback inner');
          }),
          throwsStateError,
        );
        expect(await tx.table(users).count(), 1);
      });
      expect(await db.table(users).count(), 1);
      expect(() => escaped.table(users).get(), throwsA(isA<OrmException>()));
      await expectLater(
        db.transaction((tx) async {
          await tx.table(users).delete().execute();
          throw StateError('rollback outer');
        }),
        throwsStateError,
      );
      expect(await db.table(users).count(), 1);
    });

    test('caught statement failures cannot masquerade as a commit', () async {
      await expectLater(
        db.transaction((tx) async {
          await tx.table(users).createRow((u) => [u.email.set('same')]);
          try {
            await tx.table(users).createRow((u) => [u.email.set('same')]);
          } catch (_) {}
        }),
        throwsA(isA<OrmException>()),
      );
      expect(await db.table(users).count(), 0);
    });

    test('recoverable constraint errors stay within their savepoint', () async {
      await db.transaction((tx) async {
        await tx.table(users).createRow((u) => [u.email.set('same')]);
        await expectLater(
          tx.savepoint((sp) async {
            await sp.table(users).createRow((u) => [u.email.set('same')]);
          }),
          throwsA(anything),
        );
        await tx.table(users).createRow((u) => [u.email.set('after')]);
      });
      expect(await db.table(users).count(), 2);
    });

    test('unawaited work is drained and rolled back', () async {
      await expectLater(
        db.transaction((tx) async {
          unawaited(
            tx
                .table(users)
                .insert((u) => [u.email.set('not-committed')])
                .execute(),
          );
        }),
        throwsA(isA<OrmException>()),
      );
      expect(await db.table(users).count(), 0);
    });

    test('close waits for active operations and rejects further use', () async {
      final work = db.transaction((tx) async {
        await tx.table(users).createRow((u) => [u.email.set('one')]);
      });
      final closed = db.close();
      await work;
      await closed;
      expect(() => db.table(users).get(), throwsA(isA<OrmException>()));
    });

    group('relations', () {
      setUp(() async {
        await db.execute(
          SqlCommand(
            'CREATE TABLE posts (id INTEGER PRIMARY KEY, '
            'author_id ${name == 'postgres' ? 'BIGINT' : 'INTEGER'} NOT NULL REFERENCES users(id), '
            'title TEXT NOT NULL, tag TEXT)',
          ),
        );
        for (var i = 0; i < 4; i++) {
          await create('user$i');
        }
        for (var i = 1; i <= 12; i++) {
          await db
              .table(postsTable)
              .insert(
                (p) => [
                  p.id.set(i),
                  p.authorId.set((i - 1) ~/ 4 + 1),
                  p.title.set('post$i'),
                  p.tag.set(i.isEven ? 'even' : null),
                ],
              )
              .execute();
        }
      });

      test('root pagination and each parent limit use two queries', () async {
        final events = <QueryEvent>[];
        final observed = Database(db.driver, onQuery: events.add);
        final rows = await observed
            .table(users)
            .orderBy((u) => [u.id.asc()])
            .skip(1)
            .take(2)
            .select(
              (u) => (
                u.email,
                u.posts
                    .orderBy((p) => [p.id.desc()])
                    .take(2)
                    .select((p) => p.title)
                    .many(),
              ).map((email, titles) => (email: email, titles: titles)),
            )
            .get();
        expect(rows.map((r) => r.email).toList(), ['user1', 'user2']);
        expect(rows.map((r) => r.titles).toList(), [
          ['post8', 'post7'],
          ['post12', 'post11'],
        ]);
        expect(events.length, 2);
        expect(events.last.sql, contains('PARTITION BY'));
        expect(events.last.rowCount, 4);
      });

      test(
        'empty roots skip child queries; empty lists remain typed lists',
        () async {
          final events = <QueryEvent>[];
          final observed = Database(db.driver, onQuery: events.add);
          expect(
            await observed
                .table(users)
                .where((u) => u.id.eq(100))
                .select((u) => u.posts.many())
                .get(),
            isEmpty,
          );
          expect(events.length, 1);
          final List<Post> rows = await observed
              .table(users)
              .where((u) => u.id.eq(4))
              .select((u) => u.posts.many())
              .single();
          expect(rows, isEmpty);
        },
      );

      test(
        'nested relation projections and optional all-null projection',
        () async {
          final rows = await db
              .table(users)
              .where((u) => u.id.eq(1))
              .select(
                (u) => u.posts
                    .orderBy((p) => [p.id.asc()])
                    .take(1)
                    .select(
                      (p) => (
                        p.title,
                        p.author.select((a) => a.email).required(),
                      ).map((title, email) => (title: title, author: email)),
                    )
                    .many(),
              )
              .single();
          expect(rows, [(title: 'post1', author: 'user0')]);
          final missing = await db
              .table(postsTable)
              .where((p) => p.id.eq(1))
              .select((p) => p.author.where((u) => u.id.eq(99)).one())
              .single();
          expect(missing, null);
          final present = await db
              .table(postsTable)
              .where((p) => p.id.eq(1))
              .select(
                (p) => p.author
                    .select(
                      (u) => u.nickname.map((nickname) => (nickname: nickname)),
                    )
                    .one(),
              )
              .single();
          expect(present, (nickname: null));
        },
      );

      test('correlated any, none, count and every with SQL nulls', () async {
        expect(await db.table(users).where((u) => u.posts.any()).count(), 3);
        expect(
          await db
              .table(users)
              .where((u) => u.posts.none())
              .select((u) => u.id)
              .get(),
          [4],
        );
        expect(
          await db
              .table(users)
              .orderBy((u) => [u.id.asc()])
              .select((u) => u.posts.count())
              .get(),
          [4, 4, 4, 0],
        );
        expect(
          await db
              .table(users)
              .where((u) => u.posts.every((p) => p.tag.eq('even')))
              .select((u) => u.id)
              .get(),
          [4],
        );
        expect(
          await db
              .table(users)
              .where(
                (u) => u.posts.where((p) => p.tag.eq('even')).count().eq(2),
              )
              .count(),
          3,
        );
      });

      test(
        'relation parameters bind correctly in projection and filter',
        () async {
          final rows = await db
              .table(users)
              .where((u) => u.id.eq(1))
              .select(
                (u) => u.posts
                    .where((p) => p.id.gt(1))
                    .orderBy((p) => [p.id.asc()])
                    .skip(1)
                    .take(1)
                    .select((p) => p.id.plus(100))
                    .many(),
              )
              .single();
          expect(rows, [103]);
        },
      );
    });
  });
}
