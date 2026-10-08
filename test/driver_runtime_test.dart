import 'dart:async';

import 'package:orm/database.dart';
import 'package:test/test.dart';

void main() {
  test(
    'transaction drains issued work before commit and expires immediately',
    () async {
      final driver = _Driver();
      final database = openDatabase(driver);
      addTearDown(database.close);
      final release = Completer<void>();
      driver.delay = release.future;
      late Session escaped;
      final transaction = database.transaction((session) async {
        escaped = session;
        unawaited(session.run('SELECT delayed'));
      });
      await driver.statementEntered.future;
      await expectLater(escaped.run('SELECT escaped'), throwsStateError);
      expect(driver.statements, [
        'BEGIN ISOLATION LEVEL SERIALIZABLE READ WRITE',
        'SELECT delayed',
      ]);
      release.complete();
      await transaction;
      expect(driver.statements.last, 'COMMIT');
      expect(driver.acquisitions, 1);
    },
  );

  test('commit failure rolls back and preserves the original cause', () async {
    final driver = _Driver()..failCommit = true;
    final database = openDatabase(driver);
    addTearDown(database.close);
    await expectLater(
      database.transaction((session) async {
        await session.run('SELECT 1');
      }),
      throwsA(same(driver.failure)),
    );
    expect(driver.statements, [
      'BEGIN ISOLATION LEVEL SERIALIZABLE READ WRITE',
      'SELECT 1',
      'COMMIT',
      'ROLLBACK',
    ]);
  });

  test(
    'PostgreSQL isolation and read-only options compile explicitly',
    () async {
      final driver = _Driver();
      final database = openDatabase(driver);
      addTearDown(database.close);
      for (final isolation in Isolation.values) {
        await database.transaction(
          (_) async {},
          isolation: isolation,
          readOnly: true,
        );
      }
      expect(driver.statements.where((sql) => sql.startsWith('BEGIN')), [
        'BEGIN ISOLATION LEVEL READ COMMITTED READ ONLY',
        'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY',
        'BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY',
      ]);
    },
  );

  test(
    'prepared transactions reject before SQL while ordinary PREPARE is allowed',
    () async {
      final driver = _Driver();
      final database = openDatabase(driver);
      addTearDown(database.close);
      await database.transaction((session) async {
        await expectLater(
          session.run("/* boundary */ PREPARE TRANSACTION 'detached'"),
          throwsArgumentError,
        );
        await session.run('PREPARE statement AS SELECT 1');
      });
      expect(driver.statements, [
        'BEGIN ISOLATION LEVEL SERIALIZABLE READ WRITE',
        'PREPARE statement AS SELECT 1',
        'COMMIT',
      ]);
    },
  );
}

final class _Driver implements Driver, Connection {
  final statements = <String>[];
  final failure = StateError('commit failure');
  final statementEntered = Completer<void>();
  Future<void>? delay;
  bool failCommit = false;
  int acquisitions = 0;
  @override
  Engine get engine => Engine.postgresql;
  @override
  Capabilities get capabilities =>
      const Capabilities(returning: true, maxParameters: 10);
  @override
  Future<T> withConnection<T>(
    Future<T> Function(Connection connection) action,
  ) {
    acquisitions++;
    return action(this);
  }

  @override
  Future<QueryResult> run(String sql, List<Object?> parameters) async {
    statements.add(sql);
    if (sql == 'COMMIT' && failCommit) throw failure;
    if (sql == 'SELECT delayed') {
      statementEntered.complete();
      await delay;
    }
    return const QueryResult();
  }

  @override
  Future<void> close() async {}
}
