import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/schema.orm.dart';
import '../example/schema.snapshot.dart' as physical;

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
    final initial = Migration.create(
      '0001_initial',
      appSchema,
      dialect: SqlDialect.values.byName(name),
    );
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
        expect(await Migrator(db.sql).apply([initial]), ['0001_initial']);
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
        expect(await verifyColumns(db.sql, appSchema), isEmpty);
        await db.users.byId(user.id).delete().execute();
        expect(await db.posts.count(), 0);
      },
    );

    test('planning is read-only and repeat migration is a no-op', () async {
      expect((await Migrator(db.sql).plan([initial])).map((m) => m.id), [
        '0001_initial',
      ]);
      expect(await inspectColumns(db.sql, '_orm_migrations'), isEmpty);
      await Migrator(db.sql).apply([initial]);
      expect(await Migrator(db.sql).apply([initial]), isEmpty);
      expect(
        (await Migrator(db.sql).history()).single.checksum,
        initial.checksum,
      );
    });

    test(
      'compiled physical snapshot and full managed catalog comparison',
      () async {
        final snapshot = physical.schema;
        await Migrator(db.sql).apply([initial]);
        final verification = await verifySchema(db.sql, snapshot);
        expect(verification.differences, isEmpty);
        expect(verification.unmanaged, isEmpty);
        await db.execute(SqlCommand('DROP INDEX author_timeline'));
        expect(
          (await verifySchema(db.sql, snapshot)).differences,
          contains('posts indexes differs'),
        );
      },
    );

    test('baseline preserves existing rows and verifies keys before recording history', () async {
      for (final statement in createSchema(appSchema, db.dialect)) {
        await db.execute(statement);
      }
      final user = await db.users.create(email: 'already-exists');
      final verification = await Migrator(db.sql)
          .baseline([initial], expected: SchemaSnapshot(appSchema));
      expect(verification.matches, true);
      expect((await db.users.byId(user.id).single()).email, 'already-exists');
      expect(await Migrator(db.sql).plan([initial]), isEmpty);
      await expectLater(
        Migrator(db.sql)
            .baseline([initial], expected: SchemaSnapshot(appSchema)),
        throwsA(isA<OrmException>()),
      );
    });

    test(
      'full verification sees defaults and additional unique constraints',
      () async {
        await Migrator(db.sql).apply([initial]);
        await db.execute(
          SqlCommand(
            'CREATE UNIQUE INDEX unexpected_unique ON users(nickname)',
          ),
        );
        final changed = SchemaSnapshot([
          TableSchema(
            'users',
            columns: [
              ...usersSchema.columns.where((c) => c.name != 'score'),
              Column('score', Codecs.integer, defaultSql: '1'),
            ],
            primaryKey: usersSchema.primaryKey,
            uniqueKeys: usersSchema.uniqueKeys,
          ),
          postsSchema,
        ]);
        final differences = (await verifySchema(db.sql, changed)).differences;
        expect(differences, contains('users.score default differs'));
        expect(differences, contains('users indexes differs'));
      },
    );

    test('history tampering and missing applied migrations fail', () async {
      await Migrator(db.sql).apply([initial]);
      final changed = Migration.steps(initial.id, [
        ...initial.steps,
        ExecuteSql('SELECT 1'),
      ], dialect: db.dialect);
      await expectLater(
        Migrator(db.sql).plan([changed]),
        throwsA(isA<OrmException>()),
      );
      await expectLater(
        Migrator(db.sql).plan([]),
        throwsA(isA<OrmException>()),
      );
      expect(await db.users.count(), 0);
    });

    test('failed DDL rolls back schema and history atomically', () async {
      final broken = Migration('0002_broken', [
        'ALTER TABLE users ADD COLUMN migrated TEXT',
        'INSERT INTO table_does_not_exist VALUES (1)',
      ], dialect: db.dialect);
      await expectLater(
        Migrator(db.sql).apply([initial, broken]),
        throwsA(anything),
      );
      expect(await inspectColumns(db.sql, 'users'), isEmpty);
      expect(await Migrator(db.sql).history(), isEmpty);
      await Migrator(db.sql).apply([initial]);
      await expectLater(
        Migrator(db.sql).apply([initial, broken]),
        throwsA(anything),
      );
      expect(
        (await inspectColumns(db.sql, 'users')).map((c) => c.name),
        isNot(contains('migrated')),
      );
      expect((await Migrator(db.sql).history()).length, 1);
    });

    test('actual column drift is detected independently of history', () async {
      await Migrator(db.sql).apply([initial]);
      await db.execute(SqlCommand('ALTER TABLE users ADD COLUMN extra TEXT'));
      expect(await verifyColumns(db.sql, appSchema), [
        'users.extra is unmanaged',
      ]);
      expect(await Migrator(db.sql).plan([initial]), isEmpty);
    });

    test('transaction control cannot be hidden behind SQL comments', () async {
      final bad = Migration('0001_bad', [
        '/* outer /* nested */ */ -- comment\n COMMIT',
      ], dialect: db.dialect);
      await expectLater(
        Migrator(db.sql).apply([bad]),
        throwsA(isA<OrmException>()),
      );
      expect(await Migrator(db.sql).history(), isEmpty);
    });

    test(
      'concurrent migration callers serialize against shared history',
      () async {
        final result = await Future.wait([
          Migrator(db.sql).apply([initial]),
          Migrator(db.sql).apply([initial]),
        ]);
        expect(result.expand((v) => v), ['0001_initial']);
        expect((await Migrator(db.sql).history()).length, 1);
      },
    );
  });
}
