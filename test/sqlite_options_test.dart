import 'dart:async';
import 'dart:io';

import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

void main() {
  test(
    'persistent uses the explicit native path and retains committed data',
    () async {
      final directory = await Directory.systemTemp.createTemp('orm-options-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/data.sqlite';
      final db = await sqlite(
        SqliteOptions.persistent('app', nativePath: path),
      );
      try {
        await db.execute(
          SqlCommand('CREATE TABLE item (id INTEGER PRIMARY KEY)'),
        );
        await db.transaction(
          (tx) => tx.execute(SqlCommand('INSERT INTO item VALUES (7)')),
        );
      } finally {
        await db.close();
      }
      final read = await sqlite(SqliteOptions.readOnly(path));
      try {
        expect((await read.execute(SqlCommand('SELECT id FROM item'))).rows, [
          [7],
        ]);
      } finally {
        await read.close();
      }
    },
  );

  test(
    'native persistent storage never guesses a path or falls back to memory',
    () async {
      await expectLater(
        sqlite(const SqliteOptions.persistent('app')),
        throwsArgumentError,
      );
      await expectLater(
        sqlite(const SqliteOptions.persistent('app', nativePath: ':memory:')),
        throwsArgumentError,
      );
    },
  );

  test('all driver close callers wait for active work and shutdown', () async {
    final driver = await SqliteDriver.open(const SqliteOptions.memory());
    final entered = Completer<void>(), release = Completer<void>();
    final operation = driver.run((connection) async {
      entered.complete();
      await release.future;
      return connection.execute(SqlCommand('SELECT 1'));
    });
    await entered.future;
    final first = driver.close();
    final second = driver.close();
    expect(identical(first, second), isTrue);
    var closed = false;
    first.then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    release.complete();
    expect((await operation).rows, [
      [1],
    ]);
    await Future.wait([first, second]);
    expect(() => driver.run((_) async {}), throwsA(isA<OrmException>()));
  });
}
