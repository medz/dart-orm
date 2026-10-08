import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Database database;
  setUp(() => database = openDatabase(SqliteDriver.memory()));
  tearDown(() => database.close());

  test(
    'SQLite preserves positional values, result order and affected rows',
    () async {
      await database.session.run(
        'CREATE TABLE entries (id INTEGER PRIMARY KEY, label TEXT, enabled INTEGER, '
        'score REAL, recorded INTEGER, payload BLOB, missing TEXT)',
      );
      final recorded = DateTime.parse('2026-10-09T04:05:06.123456+08:00');
      final inserted = await database.session.run(
        'INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id, label',
        parameters: [
          1,
          "O'Reilly",
          true,
          1.25,
          recorded,
          Uint8List.fromList([0, 255]),
          null,
        ],
      );
      expect(inserted.columns, ['id', 'label']);
      expect(inserted.rows, [
        [1, "O'Reilly"],
      ]);
      expect(inserted.affectedRows, 1);
      final result = await database.session.run('SELECT * FROM entries');
      expect(result.rows.single, [
        1,
        "O'Reilly",
        1,
        1.25,
        recorded.microsecondsSinceEpoch,
        Uint8List.fromList([0, 255]),
        null,
      ]);
      expect(result.affectedRows, 0);
      expect(
        await database.session
            .run('UPDATE entries SET enabled = ?', parameters: [false])
            .then((result) => result.affectedRows),
        1,
      );
      await expectLater(
        database.session.run('SELECT ?', parameters: [Object()]),
        throwsArgumentError,
      );
      await expectLater(
        database.session.run('SELECT 1; SELECT 2'),
        throwsArgumentError,
      );
    },
  );

  test('SQLite enables foreign keys on every owned connection', () async {
    await database.session.run('CREATE TABLE parents (id INTEGER PRIMARY KEY)');
    await database.session.run(
      'CREATE TABLE children (parent INTEGER REFERENCES parents(id))',
    );
    await expectLater(
      database.session.run('INSERT INTO children VALUES (1)'),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'DDL and transaction events do not reuse a prior row-write count',
    () async {
      final driver = SqliteDriver.memory();
      addTearDown(driver.close);
      await driver.withConnection((connection) async {
        await connection.run('CREATE TABLE entries (id INTEGER)', const []);
        expect(
          (await connection.run(
            'INSERT INTO entries VALUES (1), (2)',
            const [],
          )).affectedRows,
          2,
        );
        for (final sql in [
          'CREATE TABLE other (id INTEGER)',
          'CREATE INDEX by_id ON entries(id)',
          'PRAGMA user_version = 1',
          'BEGIN IMMEDIATE',
          'COMMIT',
        ]) {
          expect(
            (await connection.run(sql, const [])).affectedRows,
            0,
            reason: sql,
          );
        }
        expect(
          (await connection.run(
            '-- counted write\nWITH first AS (SELECT 3 AS id) '
            'INSERT INTO entries SELECT id FROM first',
            const [],
          )).affectedRows,
          1,
        );
        expect(
          (await connection.run(
            'WITH all_ids AS (SELECT id FROM entries) '
            'SELECT * FROM all_ids',
            const [],
          )).affectedRows,
          0,
        );
      });
    },
  );

  test(
    'transaction commits, rolls back and invalidates escaped sessions',
    () async {
      await database.session.run(
        'CREATE TABLE entries (id INTEGER PRIMARY KEY)',
      );
      late Session escaped;
      final value = await database.transaction((session) async {
        escaped = session;
        expect(session.inTransaction, isTrue);
        await session.run('INSERT INTO entries VALUES (1)');
        return 7;
      });
      expect(value, 7);
      await expectLater(escaped.run('SELECT 1'), throwsStateError);
      final failure = StateError('callback failure');
      await expectLater(
        database.transaction((session) async {
          await session.run('INSERT INTO entries VALUES (2)');
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect((await database.session.run('SELECT id FROM entries')).rows, [
        [1],
      ]);
    },
  );

  test('captured SQL failure prevents a transaction from committing', () async {
    await database.session.run('CREATE TABLE entries (id INTEGER PRIMARY KEY)');
    await expectLater(
      database.transaction((session) async {
        await session.run('INSERT INTO entries VALUES (1)');
        try {
          await session.run('INSERT INTO entries VALUES (1)');
        } catch (_) {}
      }),
      throwsA(isA<Exception>()),
    );
    expect((await database.session.run('SELECT * FROM entries')).rows, isEmpty);
  });

  test(
    'root work waits outside a SQLite transaction in admission order',
    () async {
      await database.session.run(
        'CREATE TABLE entries (id INTEGER PRIMARY KEY)',
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final first = database.transaction((session) async {
        await session.run('INSERT INTO entries VALUES (1)');
        entered.complete();
        await release.future;
      });
      await entered.future;
      final order = <int>[];
      final second = database.session.run('SELECT COUNT(*) FROM entries').then((
        result,
      ) {
        order.add(2);
        return result;
      });
      final third = database.session.run('INSERT INTO entries VALUES (3)').then(
        (result) {
          order.add(3);
          return result;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);
      release.complete();
      await first;
      expect((await second).rows, [
        [1],
      ]);
      await third;
      expect(order, [2, 3]);
    },
  );

  test(
    'transaction rejects root session, nesting and close callback misuse',
    () async {
      await database.transaction((session) async {
        await expectLater(database.session.run('SELECT 1'), throwsStateError);
        await expectLater(database.transaction((_) async {}), throwsStateError);
        expect(database.close, throwsStateError);
        await session.run('SELECT 1');
      });
      for (final sql in [
        'BEGIN',
        '-- comment\nCOMMIT',
        '/* outer /* nested */ */ ROLLBACK',
      ]) {
        await expectLater(database.session.run(sql), throwsArgumentError);
      }
    },
  );

  test(
    'SQLite checks isolation and enforces/restores read-only transactions',
    () async {
      await expectLater(
        database.transaction((_) async {}, isolation: Isolation.readCommitted),
        throwsUnsupportedError,
      );
      await database.session.run('CREATE TABLE entries (id INTEGER)');
      await database.transaction((session) async {
        expect((await session.run('SELECT COUNT(*) FROM entries')).rows, [
          [0],
        ]);
        await expectLater(
          session.run('PRAGMA query_only = OFF'),
          throwsArgumentError,
        );
      }, readOnly: true);
      await expectLater(
        database.transaction((session) async {
          await session.run('INSERT INTO entries VALUES (1)');
        }, readOnly: true),
        throwsA(isA<Exception>()),
      );
      await database.session.run('INSERT INTO entries VALUES (2)');
      expect((await database.session.run('SELECT * FROM entries')).rows, [
        [2],
      ]);
    },
  );

  test(
    'events include transaction boundaries and isolate observer failures',
    () async {
      await database.close();
      final events = <DatabaseEvent>[];
      database = openDatabase(
        SqliteDriver.memory(),
        observer: (event) {
          events.add(event);
          throw StateError('instrumentation failure');
        },
      );
      await database.session.run('CREATE TABLE entries (id INTEGER)');
      await database.transaction((session) async {
        await session.run('INSERT INTO entries VALUES (?)', parameters: [1]);
      });
      await expectLater(
        database.transaction((session) async {
          await session.run('INSERT INTO missing VALUES (2)');
        }),
        throwsA(isA<Exception>()),
      );
      expect(events.map((event) => event.kind), [
        'statement',
        'begin',
        'statement',
        'commit',
        'begin',
        'statementError',
        'rollback',
      ]);
      expect(events[2].sql, 'INSERT INTO entries VALUES (?)');
      expect(events[2].rows, 1);
      expect(events[1].transactionId, events[3].transactionId);
      expect(events[4].transactionId, isNot(events[1].transactionId));
      expect((await database.session.run('SELECT * FROM entries')).rows, [
        [1],
      ]);
    },
  );

  test(
    'close drains admitted work, rejects new work and is idempotent',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final work = database.transaction((session) async {
        entered.complete();
        await release.future;
        await session.run('SELECT 1');
      });
      await entered.future;
      final closing = database.close();
      expect(database.close(), same(closing));
      var closed = false;
      unawaited(closing.then((_) => closed = true));
      await expectLater(database.session.run('SELECT 2'), throwsStateError);
      expect(closed, isFalse);
      release.complete();
      await work;
      await closing;
      expect(closed, isTrue);
    },
  );

  test(
    'driver acquisition expires and unfinished direct transactions rollback',
    () async {
      final driver = SqliteDriver.memory();
      addTearDown(driver.close);
      late Connection escaped;
      await driver.withConnection((connection) async {
        escaped = connection;
        await connection.run('CREATE TABLE entries (id INTEGER)', const []);
        await connection.run('BEGIN', const []);
        await connection.run('INSERT INTO entries VALUES (1)', const []);
        await expectLater(
          driver.withConnection((_) async {}),
          throwsStateError,
        );
        await expectLater(driver.close(), throwsStateError);
      });
      await expectLater(escaped.run('SELECT 1', const []), throwsStateError);
      expect(
        (await driver.withConnection(
          (connection) => connection.run('SELECT * FROM entries', const []),
        )).rows,
        isEmpty,
      );
    },
  );

  test(
    'read-only file configuration reads and rejects persistent writes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orm-driver-sqlite-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/test.sqlite';
      final writable = openDatabase(SqliteDriver.open(path));
      await writable.session.run('CREATE TABLE entries (id INTEGER)');
      await writable.session.run('INSERT INTO entries VALUES (1)');
      await writable.close();
      final readonly = openDatabase(SqliteDriver.openReadOnly(path));
      addTearDown(readonly.close);
      await readonly.transaction((session) async {
        expect((await session.run('SELECT * FROM entries')).rows, [
          [1],
        ]);
      }, readOnly: true);
      await expectLater(
        readonly.session.run('INSERT INTO entries VALUES (2)'),
        throwsA(isA<Exception>()),
      );
    },
  );
}
