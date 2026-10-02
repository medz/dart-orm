@Tags(['sqlite'])
library;

import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart' show SqlDatabase;
import 'package:orm/sqlite.dart'
    show Sqlite, SqliteFailure, SqliteOptions, sqlite;
import 'package:orm/values.dart' show OrmException;
import 'package:test/test.dart';

Matcher _code(String value) =>
    isA<OrmException>().having((error) => error.code, 'code', value);

void main() {
  late SqlDatabase<Sqlite> db;

  setUp(() async {
    db = (Database.fromSql(await sqlite(const SqliteOptions.memory()))).sql;
    await db.execute(SqlCommand('CREATE TABLE items (id INTEGER PRIMARY KEY)'));
  });
  tearDown(() => db.close());

  Future<List<Object?>> ids(SqlDatabase<Sqlite> view) async =>
      (await view.execute(SqlCommand('SELECT id FROM items ORDER BY id'))).rows
          .map((row) => row.single)
          .toList();

  for (final scope in ['session', 'transaction', 'savepoint']) {
    for (final failed in [false, true]) {
      test(
        'expired $scope after ${failed ? 'failure' : 'success'} cannot discard a reused lease',
        () async {
          late SqlDatabase<Sqlite> expired;
          final failure = StateError('leave the borrowed scope');
          Future<void> capture(SqlDatabase<Sqlite> view) async {
            expired = view;
            if (failed) throw failure;
          }

          Future<void> finishScope() => switch (scope) {
            'session' => db.session(capture),
            'transaction' => db.transaction(capture),
            _ => db.transaction((tx) => tx.savepoint(capture)),
          };
          if (failed) {
            await expectLater(finishScope(), throwsA(same(failure)));
          } else {
            await finishScope();
          }

          await db.session((current) async {
            await current.execute(SqlCommand('INSERT INTO items VALUES (1)'));
            await expectLater(
              expired.discard(),
              throwsA(_code('SESSION.CLOSED')),
            );
            expect(await ids(current), [1]);
          });
          await db.execute(SqlCommand('INSERT INTO items VALUES (2)'));
          expect(await ids(db), [1, 2]);
        },
      );
    }
  }

  test('parent session cannot discard its active transaction lease', () async {
    await db.session((session) async {
      await session.transaction((tx) async {
        await expectLater(
          session.discard(),
          throwsA(_code('SESSION.SAVEPOINT')),
        );
        await tx.execute(SqlCommand('INSERT INTO items VALUES (1)'));
      });
      expect(await ids(session), [1]);
    });
    expect(await ids(db), [1]);
  });

  test(
    'parent transaction cannot discard its active savepoint lease',
    () async {
      await db.transaction((tx) async {
        await tx.savepoint((child) async {
          await expectLater(tx.discard(), throwsA(_code('SESSION.SAVEPOINT')));
          await child.execute(SqlCommand('INSERT INTO items VALUES (1)'));
        });
        await tx.execute(SqlCommand('INSERT INTO items VALUES (2)'));
      });
      expect(await ids(db), [1, 2]);
    },
  );

  test('a root database cannot discard without a borrowed lease', () async {
    await expectLater(db.discard(), throwsA(_code('SESSION.REQUIRED')));
    expect(await ids(db), isEmpty);
  });

  test('an active session can discard its unrecoverable lease once', () async {
    await db.session((session) async {
      await session.discard();
      await expectLater(session.discard(), throwsA(_code('SESSION.CLOSED')));
    });
  });

  test('an active failed transaction can still discard for cleanup', () async {
    var discarded = false;
    await expectLater(
      db.transaction((tx) async {
        await tx.execute(SqlCommand('INSERT INTO items VALUES (1)'));
        await expectLater(
          tx.execute(SqlCommand('INSERT INTO items VALUES (1)')),
          throwsA(isA<SqliteFailure>()),
        );
        await tx.discard();
        discarded = true;
        throw StateError('connection discarded');
      }),
      throwsA(_code('TRANSACTION.ROLLBACK')),
    );
    expect(discarded, isTrue);
  });

  test('a view can discard after SQLite ends its transaction', () async {
    var discarded = false;
    await expectLater(
      db.transaction((tx) async {
        await tx.execute(SqlCommand('INSERT INTO items VALUES (1)'));
        await expectLater(
          tx.execute(SqlCommand('INSERT OR ROLLBACK INTO items VALUES (1)')),
          throwsA(isA<SqliteFailure>()),
        );
        await expectLater(
          Future.sync(() => tx.execute(SqlCommand('SELECT 1'))),
          throwsA(_code('TRANSACTION.ENDED')),
        );
        await tx.discard();
        discarded = true;
        throw StateError('connection discarded');
      }),
      throwsA(_code('TRANSACTION.ROLLBACK')),
    );
    expect(discarded, isTrue);
  });
}
