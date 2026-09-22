@Tags(['core'])
library;

import 'dart:async';

import 'package:orm/runtime.dart';
import 'package:test/test.dart';

void main() {
  test(
    'raw sessions retain one connection and expire borrowed views',
    () async {
      final driver = _Driver<Sqlite>(SqlDialect.sqlite);
      final db = SqlDatabase(driver);
      SqlDatabase<Sqlite>? borrowed;
      await db.session((session) async {
        borrowed = session;
        final result = await session.execute(SqlCommand('SELECT value', [7]));
        expect(result.rows, [
          [7],
        ]);
        await session.transaction((tx) async {
          await tx.execute(SqlCommand('SELECT value', [8]));
        });
      });
      expect(driver.leases, 1);
      expect(
        () => borrowed!.execute(SqlCommand('SELECT value')),
        throwsA(_code('SESSION.CLOSED')),
      );
      await db.close();
      expect(driver.closed, isTrue);
    },
  );

  test(
    'raw table notifications merge through successful savepoints only',
    () async {
      final db = SqlDatabase(_Driver<Sqlite>(SqlDialect.sqlite));
      final changes = <Set<String>>[];
      db.addChangeListener(changes.add);
      await db.transaction((tx) async {
        tx.notifyChanged(['parent']);
        try {
          await tx.savepoint<void>((child) async {
            child.notifyChanged(['rolled_back']);
            throw StateError('undo child');
          });
        } on StateError catch (_) {}
        await tx.savepoint((child) async {
          await child.execute(
            SqlCommand('UPDATE data'),
            changedTables: ['child'],
          );
        });
        expect(changes, isEmpty);
      });
      expect(changes, [
        {'parent'},
        {'child'},
      ]);
      await db.close();
    },
  );

  test(
    'rollback discards runtime invalidation hooks and raw notifications',
    () async {
      final db = SqlDatabase(_Driver<Sqlite>(SqlDialect.sqlite));
      var hooks = 0;
      final changes = <Set<String>>[];
      db.addChangeListener(changes.add);
      await expectLater(
        db.transaction<void>((tx) async {
          tx.deferInvalidation(() => hooks++);
          tx.notifyChanged(['data']);
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(hooks, 0);
      expect(changes, isEmpty);
      await db.close();
    },
  );

  test(
    'uncertain commit invalidates once without replaying a callback',
    () async {
      final driver = _Driver<Sqlite>(SqlDialect.sqlite);
      driver.connection.onExecute = (command) {
        if (command.sql == 'COMMIT') {
          driver.connection.active = false;
          throw StateError('acknowledgement lost');
        }
      };
      final db = SqlDatabase(driver);
      var calls = 0, hooks = 0;
      final changes = <Set<String>>[];
      db.addChangeListener(changes.add);
      await expectLater(
        db.transaction<void>((tx) async {
          calls++;
          tx.deferInvalidation(() => hooks++);
          tx.notifyChanged(['data']);
        }),
        throwsA(_code('TRANSACTION.COMMIT')),
      );
      expect(calls, 1);
      expect(hooks, 1);
      expect(changes, [
        {'data'},
      ]);
      await db.close();
    },
  );

  test(
    'retry discards invalidation callbacks from the rolled back attempt',
    () async {
      final driver = _Driver<Sqlite>(SqlDialect.sqlite);
      var executions = 0;
      driver.connection.onExecute = (command) {
        if (command.sql == 'UPDATE retry' && ++executions == 1) {
          throw const _RetryableFailure();
        }
      };
      final db = SqlDatabase(driver);
      var calls = 0;
      final hooks = <int>[];
      await db.transaction((tx) async {
        final attempt = ++calls;
        tx.deferInvalidation(() => hooks.add(attempt));
        await tx.execute(SqlCommand('UPDATE retry'));
      }, retry: const TransactionRetry(delay: Duration.zero));
      expect(calls, 2);
      expect(hooks, [2]);
      expect(
        driver.connection.commands.where((sql) => sql == 'ROLLBACK'),
        hasLength(1),
      );
      await db.close();
    },
  );

  test('MySQL transaction setup is ordered on the leased connection', () async {
    final driver = _Driver<Mysql>(SqlDialect.mysql);
    final db = SqlDatabase(driver);
    await db.transaction(
      (tx) async {
        await tx.execute(SqlCommand('SELECT value', [1]));
      },
      options: const MysqlTransaction(isolation: .serializable, readOnly: true),
    );
    expect(driver.connection.commands, [
      'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE',
      'START TRANSACTION READ ONLY',
      'SELECT value',
      'COMMIT',
    ]);
    expect(driver.leases, 1);
    await db.close();
  });

  test(
    'failed multi-statement transaction setup discards changed session state',
    () async {
      final driver = _Driver<Mariadb>(SqlDialect.mariadb);
      driver.connection.onExecute = (command) {
        if (command.sql.startsWith('START TRANSACTION')) {
          throw StateError('start rejected');
        }
      };
      final db = SqlDatabase(driver);
      var calls = 0;
      await expectLater(
        db.transaction<void>((_) async {
          calls++;
        }, options: const MariadbTransaction()),
        throwsStateError,
      );
      expect(calls, 0);
      expect(driver.connection.invalidated, isTrue);
      await db.close();
    },
  );

  test(
    'close stops registered resources once and clears change listeners',
    () async {
      final db = SqlDatabase(_Driver<Sqlite>(SqlDialect.sqlite));
      final stopped = Completer<void>();
      var stops = 0, notifications = 0;
      db.addChangeListener((_) => notifications++);
      db.addCloseListener(() async {
        stops++;
        await stopped.future;
      });
      final closing = db.close();
      final second = db.close();
      expect(stops, 1);
      expect(
        () => db.notifyChanged(['data']),
        throwsA(_code('SESSION.CLOSED')),
      );
      stopped.complete();
      await Future.wait([closing, second]);
      expect(stops, 1);
      expect(notifications, 0);
    },
  );
}

Matcher _code(String code) =>
    isA<OrmException>().having((e) => e.code, 'code', code);

final class _Driver<B extends Backend> implements Driver<B> {
  @override
  final Capabilities capabilities;
  final connection = _Connection();
  int leases = 0;
  bool closed = false;
  _Driver(SqlDialect dialect)
    : capabilities = Capabilities(
        dialect: dialect,
        maxParameters: 999,
        returning:
            dialect == SqlDialect.sqlite || dialect == SqlDialect.postgres,
        cancellation: true,
      );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) {
    leases++;
    return Future.sync(() => action(connection));
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _Connection implements SqlConnection {
  final commands = <String>[];
  bool active = false;
  bool invalidated = false;
  void Function(SqlCommand)? onExecute;
  @override
  bool get transactionActive => active;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    options.check();
    commands.add(command.sql);
    onExecute?.call(command);
    if (command.sql.startsWith('BEGIN') ||
        command.sql.startsWith('START TRANSACTION')) {
      active = true;
    } else if (command.sql == 'COMMIT' || command.sql == 'ROLLBACK') {
      active = false;
    }
    return SqlResult(
      command.sql.startsWith('SELECT') ? [command.parameters] : [],
      columns: command.sql.startsWith('SELECT') ? ['value'] : const [],
      affectedRows: command.sql.startsWith('UPDATE') ? 1 : 0,
    );
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => throw UnsupportedError('This test connection has no cursor.');
  @override
  Future<void> invalidate() async {
    invalidated = true;
  }
}

final class _RetryableFailure implements SqlFailure {
  const _RetryableFailure();
  @override
  bool get retryTransaction => true;
  @override
  bool get retryCommit => false;
  @override
  bool get commitRejected => true;
}
