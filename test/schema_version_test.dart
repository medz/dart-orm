import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/tables.dart';

Matcher code(String value) =>
    isA<OrmException>().having((e) => e.code, 'code', value);
final initial = Migration.create('0001_initial', [usersSchema]);
final expand = Migration('0002_expand', {
  for (final dialect in SqlDialect.values)
    dialect: ['ALTER TABLE users ADD COLUMN label TEXT'],
}, previous: initial.checksum);
final contract = Migration('0003_contract', {
  for (final dialect in SqlDialect.values)
    dialect: ['ALTER TABLE users DROP COLUMN nickname'],
}, previous: expand.checksum);
final history = [initial, expand, contract];

void main() {
  runTests('sqlite', () => sqlite(const SqliteOptions.memory()));
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    runTests('postgres', () async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          schema: 'orm_version_tests',
          maxConnections: 1,
        ),
      );
      await db.execute(
        SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_version_tests'),
      );
      return db;
    });
  }
  test('SQLite version gate works on an explicitly read-only file', () async {
    final directory = await Directory.systemTemp.createTemp('orm-version-');
    final path = '${directory.path}/db.sqlite';
    final writer = await sqlite(SqliteOptions.file(path));
    try {
      await Migrator(writer).apply([initial]);
      await writer.table(users).createRow((u) => [u.email.set('retained')]);
    } finally {
      await writer.close();
    }
    final reader = await sqlite(SqliteOptions.readOnly(path));
    try {
      expect((await Migrator(reader).requireVersion([initial])).id, initial.id);
      expect((await reader.table(users).single()).email, 'retained');
      await expectLater(
        Migrator(reader).requireVersion(history),
        throwsA(code('MIGRATION.VERSION')),
      );
      expect((await Migrator(reader).history()).length, 1);
    } finally {
      await reader.close();
      await directory.delete(recursive: true);
    }
  });
}

void runTests(String name, Future<Database<Backend>> Function() open) {
  group('schema version $name', () {
    late Database<Backend> db;
    late Migrator runner;
    final commands = <String>[];
    setUp(() async {
      final base = await open();
      db = Database(base.driver, onQuery: (event) => commands.add(event.sql));
      runner = Migrator(db);
      for (final table in [
        'users',
        '_orm_migration_steps',
        '_orm_migrations',
      ]) {
        await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
      }
      commands.clear();
    });
    tearDown(() => db.close());
    Future<void> seed(List<Migration> migrations) async {
      await runner.apply(migrations);
      await db.table(users).createRow((u) => [u.email.set('retained')]);
    }

    test(
      'invalid ranges fail before SQL; caller transactions stay usable',
      () async {
        expect(() => runner.requireVersion([]), throwsArgumentError);
        expect(
          () => runner.requireVersion(history, minimum: 'missing'),
          throwsArgumentError,
        );
        expect(
          () => runner.requireVersion(history, maximum: 'missing'),
          throwsArgumentError,
        );
        expect(
          () => runner.requireVersion(
            history,
            minimum: contract.id,
            maximum: initial.id,
          ),
          throwsArgumentError,
        );
        expect(commands, isEmpty);
        await db.transaction((tx) async {
          expect(
            () => Migrator(tx).requireVersion(history),
            throwsA(code('MIGRATION.SESSION')),
          );
          expect(
            (await tx.execute(SqlCommand('SELECT 1'))).rows.single.single,
            1,
          );
        });
      },
    );

    test(
      'unversioned existing data is rejected without creating history',
      () async {
        await createTables(db);
        await db.table(users).createRow((u) => [u.email.set('retained')]);
        commands.clear();
        await expectLater(
          runner.requireVersion(history),
          throwsA(code('MIGRATION.VERSION')),
        );
        expect(await inspectColumns(db, '_orm_migrations'), isEmpty);
        expect((await db.table(users).single()).email, 'retained');
        expect(
          commands.any(
            (sql) => sql.startsWith('CREATE') || sql.startsWith('INSERT'),
          ),
          false,
        );
      },
    );

    test(
      'default requires latest; inclusive compatibility range is explicit',
      () async {
        await seed([initial]);
        await expectLater(
          runner.requireVersion(history),
          throwsA(code('MIGRATION.VERSION')),
        );
        expect(
          (await runner.requireVersion(history, minimum: initial.id)).id,
          initial.id,
        );
        await runner.apply([initial, expand]);
        final accepted = await runner.requireVersion(
          history,
          minimum: initial.id,
          maximum: expand.id,
        );
        expect((accepted.id, accepted.checksum), (expand.id, expand.checksum));
        expect(
          (await runner.requireVersion(history, maximum: expand.id)).id,
          expand.id,
        );
        await expectLater(
          runner.requireVersion(history, maximum: initial.id),
          throwsA(code('MIGRATION.VERSION')),
        );
        await expectLater(
          runner.requireVersion(history),
          throwsA(code('MIGRATION.VERSION')),
        );
        expect((await db.table(users).single()).email, 'retained');
      },
    );

    test(
      'newer database rejects downgrade without changing data or schema',
      () async {
        await seed([initial]);
        await runner.apply(history);
        await expectLater(
          runner.requireVersion([initial, expand]),
          throwsA(code('MIGRATION.VERSION')),
        );
        await expectLater(
          runner.requireVersion(
            history,
            minimum: initial.id,
            maximum: expand.id,
          ),
          throwsA(code('MIGRATION.VERSION')),
        );
        expect((await runner.requireVersion(history)).id, contract.id);
        expect((await db.execute(SqlCommand('SELECT email FROM users'))).rows, [
          ['retained'],
        ]);
        expect(
          (await inspectColumns(db, 'users')).any((c) => c.name == 'nickname'),
          false,
        );
        expect((await runner.history()).length, 3);
      },
    );

    test('complete applied prefix is checked, including old checksums and missing entries', () async {
      await seed([initial, expand]);
      await db.execute(
        SqlCommand(
          "UPDATE _orm_migrations SET checksum = 'altered' WHERE id = '0001_initial'",
        ),
      );
      await expectLater(
        runner.requireVersion(history, minimum: initial.id),
        throwsA(code('MIGRATION.CHECKSUM')),
      );
      await db.execute(
        SqlCommand("DELETE FROM _orm_migrations WHERE id = '0001_initial'"),
      );
      await expectLater(
        runner.requireVersion(history, minimum: initial.id),
        throwsA(code('MIGRATION.CHECKSUM')),
      );
      expect((await db.table(users).single()).email, 'retained');
    });

    test(
      'matching version does not claim that the catalog is free of drift',
      () async {
        await seed([initial]);
        await db.execute(
          SqlCommand('ALTER TABLE users RENAME COLUMN email TO renamed_email'),
        );
        expect((await runner.requireVersion([initial])).id, initial.id);
        expect((await verifySchema(db, initial.snapshot!)).matches, false);
      },
    );

    test(
      'verified baseline is compatible without replaying creation',
      () async {
        for (final command in createSchema([usersSchema], db.dialect)) {
          await db.execute(command);
        }
        await db.table(users).createRow((u) => [u.email.set('retained')]);
        await runner.baseline([initial], expected: initial.snapshot!);
        expect(
          (await runner.requireVersion([initial])).checksum,
          initial.checksum,
        );
        expect((await db.table(users).single()).email, 'retained');
      },
    );

    test(
      'borrowed session uses a read snapshot and survives rejected versions',
      () async {
        await seed([initial]);
        commands.clear();
        await db.session((session) async {
          expect(
            (await Migrator(session).requireVersion([initial])).id,
            initial.id,
          );
          await expectLater(
            Migrator(session).requireVersion(history),
            throwsA(code('MIGRATION.VERSION')),
          );
          expect(
            (await session.execute(SqlCommand('SELECT 1'))).rows.single.single,
            1,
          );
        });
        expect(
          commands.first,
          name == 'postgres'
              ? 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'
              : 'BEGIN DEFERRED',
        );
        expect(
          commands.every(
            (sql) =>
                ['BEGIN', 'SELECT', 'COMMIT', 'ROLLBACK'].any(sql.startsWith),
          ),
          true,
        );
      },
    );

    if (name == 'postgres') {
      final pending = Migration.steps('0002_index', {
        SqlDialect.postgres: [
          CheckedSql(
            'UPDATE users SET score = score + 1',
            readyWhen: 'SELECT EXISTS(SELECT 1 FROM users WHERE score = 0)',
            doneWhen: 'SELECT EXISTS(SELECT 1 FROM users WHERE score = 1)',
          ),
          ExecuteSql("INSERT INTO users(email) VALUES ('retained')"),
        ],
      }, previous: initial.checksum);

      test('unfinished recoverable migration blocks startup until repaired and completed', () async {
        await seed([initial]);
        await expectLater(
          runner.apply([initial, pending]),
          throwsA(code('MIGRATION.STEP')),
        );
        await expectLater(
          runner.requireVersion([initial, pending], maximum: initial.id),
          throwsA(code('MIGRATION.INCOMPLETE')),
        );
        // Even an older app must reject recovery work it cannot recognize.
        await expectLater(
          runner.requireVersion([initial]),
          throwsA(code('MIGRATION.INCOMPLETE')),
        );
        await db.execute(SqlCommand("UPDATE users SET email = 'repaired'"));
        await runner.apply([initial, pending]);
        expect(
          (await runner.requireVersion([initial, pending])).id,
          pending.id,
        );
        expect(await db.table(users).count(), 2);
        await db.execute(
          SqlCommand(
            "UPDATE _orm_migration_steps SET state = 'failed' WHERE step = 0",
          ),
        );
        await expectLater(
          runner.requireVersion([initial, pending]),
          throwsA(code('MIGRATION.HISTORY')),
        );
      });

      test('catalog and history share a snapshot and the supplied history is frozen', () async {
        await seed([initial]);
        final other = await open();
        var upgraded = false;
        final supplied = [initial, pending];
        final driver = _ReadHook(db.driver, () async {
          if (upgraded) return;
          upgraded = true;
          supplied.clear();
          await expectLater(
            Migrator(other).apply([initial, pending]),
            throwsA(code('MIGRATION.STEP')),
          );
        });
        try {
          // After the history SELECT, another runner creates recovery checkpoints.
          final accepted = await Migrator(Database(driver))
              .requireVersion(supplied, maximum: initial.id);
          expect(accepted.id, initial.id);
          expect(upgraded, true);
          await expectLater(
            runner.requireVersion([initial]),
            throwsA(code('MIGRATION.INCOMPLETE')),
          );
          await other.execute(
            SqlCommand("UPDATE users SET email = 'repaired'"),
          );
          await Migrator(other).apply([initial, pending]);
          expect(
            (await runner.requireVersion([initial, pending])).id,
            pending.id,
          );
        } finally {
          await other.close();
        }
      });
    }
  });
}

final class _ReadHook(
  final Driver<Backend> source,
  final Future<void> Function() after,
) implements Driver<Backend> {
  @override
  Capabilities get capabilities => source.capabilities;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      source.run((c) => action(_ReadConnection(c, after)));
  @override
  Future<void> close() => source.close();
}

final class _ReadConnection(
  final SqlConnection source,
  final Future<void> Function() after,
) implements SqlConnection {
  @override
  bool? get transactionActive => source.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final result = await source.execute(command, options: options);
    if (command.sql.startsWith('SELECT id, checksum FROM')) await after();
    return result;
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => source.openCursor(command, options: options);
  @override
  Future<void> invalidate() => source.invalidate();
}
