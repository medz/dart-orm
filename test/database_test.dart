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
  });
}
