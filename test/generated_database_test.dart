import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/schema.orm.dart';

void main() {
  runGeneratedTests('sqlite', () => sqlite(const SqliteOptions.memory()));
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    const schema = 'orm_generated_tests';
    late Database<Postgres> admin;
    setUpAll(() async {
      admin = postgres(
        PostgresOptions(url: Uri.parse(url), tls: PostgresTls.disable),
      );
      await admin.execute(SqlCommand('CREATE SCHEMA IF NOT EXISTS "$schema"'));
    });
    tearDownAll(() async {
      await admin.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
      await admin.close();
    });
    runGeneratedTests(
      'postgres',
      () async => postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: PostgresTls.disable,
          schema: schema,
        ),
      ),
    );
  }
}

void runGeneratedTests(String name, Future<Database<Backend>> Function() open) {
  group('generated $name', () {
    late Database<Backend> db;
    final initial = Migration.create('0001_initial', appSchema);
    setUp(() async {
      db = await open();
      for (final table in ['posts', 'users', '_orm_migrations']) {
        await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
      }
    });
    tearDown(() => db.close());

    test(
      'generated client, DDL, relations, dates and patches work together',
      () async {
        expect(await Migrator(db).apply([initial]), ['0001_initial']);
        final time = DateTime.utc(2026, 9, 15, 1, 2, 3, 456, 789);
        final user = await db.transaction((tx) async {
          final user = await tx.users.create(
            email: 'seven@example.com',
            score: .set(10),
          );
          await tx.posts.create(
            authorId: user.id,
            title: 'Hello',
            createdAt: time,
          );
          return user;
        });
        expect(user.score, 10);
        await db.users.byId(user.id).patch(nickname: .set('Seven'));
        expect((await db.users.byId(user.id).single()).nickname, 'Seven');
        await db.users.byId(user.id).patch(nickname: .set(null));
        final titles = await db.users
            .byId(user.id)
            .select((u) => u.posts.select((p) => p.title).many())
            .single();
        expect(titles, ['Hello']);
        expect((await db.posts.single()).createdAt, time);
        expect(await verifyColumns(db, appSchema), isEmpty);
        await db.users.byId(user.id).delete().execute();
        expect(await db.posts.count(), 0);
      },
    );

    test('planning is read-only and repeat migration is a no-op', () async {
      expect((await Migrator(db).plan([initial])).map((m) => m.id), [
        '0001_initial',
      ]);
      expect(await inspectColumns(db, '_orm_migrations'), isEmpty);
      await Migrator(db).apply([initial]);
      expect(await Migrator(db).apply([initial]), isEmpty);
      expect((await Migrator(db).history()).single.checksum, initial.checksum);
    });

    test('history tampering and missing applied migrations fail', () async {
      await Migrator(db).apply([initial]);
      final changed = Migration(initial.id, {
        for (final dialect in SqlDialect.values)
          dialect: [...initial.statements[dialect]!, 'SELECT 1'],
      });
      await expectLater(
        Migrator(db).plan([changed]),
        throwsA(isA<OrmException>()),
      );
      await expectLater(Migrator(db).plan([]), throwsA(isA<OrmException>()));
      expect(await db.users.count(), 0);
    });

    test('failed DDL rolls back schema and history atomically', () async {
      final broken = Migration('0002_broken', {
        for (final d in SqlDialect.values)
          d: [
            'ALTER TABLE users ADD COLUMN migrated TEXT',
            'INSERT INTO table_does_not_exist VALUES (1)',
          ],
      });
      await expectLater(
        Migrator(db).apply([initial, broken]),
        throwsA(anything),
      );
      expect(await inspectColumns(db, 'users'), isEmpty);
      expect(await Migrator(db).history(), isEmpty);
      await Migrator(db).apply([initial]);
      await expectLater(
        Migrator(db).apply([initial, broken]),
        throwsA(anything),
      );
      expect(
        (await inspectColumns(db, 'users')).map((c) => c.name),
        isNot(contains('migrated')),
      );
      expect((await Migrator(db).history()).length, 1);
    });

    test('actual column drift is detected independently of history', () async {
      await Migrator(db).apply([initial]);
      await db.execute(SqlCommand('ALTER TABLE users ADD COLUMN extra TEXT'));
      expect(await verifyColumns(db, appSchema), ['users.extra is unmanaged']);
      expect(await Migrator(db).plan([initial]), isEmpty);
    });

    test('transaction control cannot be hidden behind SQL comments', () async {
      final bad = Migration('0001_bad', {
        for (final d in SqlDialect.values)
          d: ['/* outer /* nested */ */ -- comment\n COMMIT'],
      });
      await expectLater(
        Migrator(db).apply([bad]),
        throwsA(isA<OrmException>()),
      );
      expect(await Migrator(db).history(), isEmpty);
    });

    test(
      'concurrent migration callers serialize against shared history',
      () async {
        final result = await Future.wait([
          Migrator(db).apply([initial]),
          Migrator(db).apply([initial]),
        ]);
        expect(result.expand((v) => v), ['0001_initial']);
        expect((await Migrator(db).history()).length, 1);
      },
    );
  });
}
