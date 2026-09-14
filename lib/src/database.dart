part of '../orm.dart';

sealed class Backend {
  const Backend();
}

final class Postgres extends Backend {
  const Postgres();
}

final class Sqlite extends Backend {
  const Sqlite();
}

final class Capabilities {
  final SqlDialect dialect;
  final int maxParameters;
  final bool returning;
  final bool windowFunctions;
  const Capabilities({
    required this.dialect,
    required this.maxParameters,
    this.returning = true,
    this.windowFunctions = true,
  });
}

final class SqlResult {
  final List<List<Object?>> rows;
  final List<String> columns;
  final int affectedRows;
  const SqlResult(this.rows, {this.columns = const [], this.affectedRows = 0});
}

abstract interface class SqlConnection {
  Future<SqlResult> execute(SqlCommand command);

  /// Permanently discard a connection whose protocol or transaction is uncertain.
  Future<void> invalidate();
}

abstract interface class Driver<B extends Backend> {
  Capabilities get capabilities;
  Future<R> run<R>(Future<R> Function(SqlConnection) action);
  Future<void> close();
}

sealed class TransactionOptions<B extends Backend> {
  const TransactionOptions();
  String get _begin;
}

enum Isolation { readCommitted, repeatableRead, serializable }

final class PostgresTransaction extends TransactionOptions<Postgres> {
  final Isolation isolation;
  final bool readOnly;
  const PostgresTransaction({
    this.isolation = Isolation.readCommitted,
    this.readOnly = false,
  });
  @override
  String get _begin =>
      'BEGIN ISOLATION LEVEL ${switch (isolation) {
        Isolation.readCommitted => 'READ COMMITTED',
        Isolation.repeatableRead => 'REPEATABLE READ',
        Isolation.serializable => 'SERIALIZABLE',
      }} ${readOnly ? 'READ ONLY' : 'READ WRITE'}';
}

enum SqliteTransactionMode { deferred, immediate, exclusive }

final class SqliteTransaction extends TransactionOptions<Sqlite> {
  final SqliteTransactionMode mode;
  const SqliteTransaction({this.mode = SqliteTransactionMode.deferred});
  @override
  String get _begin => 'BEGIN ${mode.name.toUpperCase()}';
}

final class QueryEvent {
  final String sql;
  final int parameterCount;
  final Duration elapsed;
  final int? rowCount;
  final Object? error;
  const QueryEvent({
    required this.sql,
    required this.parameterCount,
    required this.elapsed,
    this.rowCount,
    this.error,
  });
}

/// Database owns its driver. A transaction view borrows one connection and
/// becomes unusable as soon as its callback finishes.
class Database<B extends Backend> {
  final Driver<B> driver;
  final void Function(QueryEvent)? onQuery;
  final SqlConnection? _connection;
  final bool _transaction;
  final Set<Future<void>> _pending = {};
  bool _active = true;
  bool _childActive = false;
  bool _statementFailed = false;
  int _savepointId = 0;

  Database(this.driver, {this.onQuery})
    : _connection = null,
      _transaction = false;
  Database._(
    this.driver,
    this._connection,
    this.onQuery, {
    this._transaction = true,
  });
  Capabilities get capabilities => driver.capabilities;
  SqlDialect get dialect => capabilities.dialect;
  bool get inTransaction => _transaction;
  bool get inSession => _connection != null;

  TableSet<R, F> table<R, F extends Fields>(Table<R, F> table) =>
      TableSet(this, table);

  void _checkActive() {
    if (!_active) {
      throw const OrmException('SESSION.CLOSED', 'Database session has ended.');
    }
    if (_childActive) {
      throw const OrmException(
        'SESSION.SAVEPOINT',
        'Use the active nested session.',
      );
    }
  }

  Future<R> _run<R>(Future<R> Function(SqlConnection) action) {
    _checkActive();
    final connection = _connection;
    final result = connection != null
        ? Future.sync(() => action(connection))
        : driver.run(action);
    final done = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending.add(done);
    unawaited(done.then((_) => _pending.remove(done)));
    return result;
  }

  Future<SqlResult> _execute(
    SqlConnection connection,
    SqlCommand command,
  ) async {
    if (command.parameters.length > capabilities.maxParameters) {
      throw const OrmException(
        'QUERY.PARAMETERS',
        'Query exceeds the driver parameter limit.',
      );
    }
    final watch = Stopwatch()..start();
    SqlResult? result;
    Object? error;
    try {
      return result = await connection.execute(command);
    } catch (e) {
      error = e;
      if (inTransaction) _statementFailed = true;
      rethrow;
    } finally {
      watch.stop();
      // Instrumentation cannot turn a successful commit into an apparent failure.
      try {
        onQuery?.call(
          QueryEvent(
            sql: command.sql,
            parameterCount: command.parameters.length,
            elapsed: watch.elapsed,
            rowCount: result?.rows.length,
            error: error,
          ),
        );
      } catch (_) {}
    }
  }

  Future<SqlResult> execute(SqlCommand command) =>
      _run((c) => _execute(c, command));

  /// Retains one connection across transactions and session-scoped operations.
  /// The borrowed view expires when the callback returns.
  Future<R> session<R>(Future<R> Function(Database<B> session) action) {
    if (_connection != null) {
      throw const OrmException(
        'SESSION.NESTED',
        'This session already owns a connection lease.',
      );
    }
    return _run((connection) async {
      final session = Database<B>._(
        driver,
        connection,
        onQuery,
        transaction: false,
      );
      try {
        final result = await action(session);
        session._active = false;
        if (session._pending.isNotEmpty) {
          await Future.wait(session._pending.toList());
          throw const OrmException(
            'SESSION.UNAWAITED',
            'Await all work before releasing a session.',
          );
        }
        return result;
      } finally {
        session._active = false;
        await Future.wait(session._pending.toList());
      }
    });
  }

  /// Discards a leased connection after its state can no longer be recovered.
  Future<void> discard() async {
    final connection = _connection;
    if (connection == null) {
      throw const OrmException(
        'SESSION.REQUIRED',
        'Discard requires a leased session.',
      );
    }
    _active = false;
    await connection.invalidate();
  }

  Future<R> transaction<R>(
    Future<R> Function(Database<B> tx) action, {
    TransactionOptions<B>? options,
  }) {
    if (inTransaction) {
      throw const OrmException(
        'TRANSACTION.NESTED',
        'Use savepoint() inside a transaction.',
      );
    }
    return _run((connection) async {
      if (_connection != null) _childActive = true;
      try {
        await _execute(connection, SqlCommand(options?._begin ?? 'BEGIN'));
        final tx = Database<B>._(driver, connection, onQuery);
        var committing = false;
        try {
          final result = await action(tx);
          tx._active = false;
          if (tx._pending.isNotEmpty || tx._childActive) {
            await Future.wait(tx._pending.toList());
            throw const OrmException(
              'TRANSACTION.UNAWAITED',
              'Await every operation before leaving the transaction.',
            );
          }
          if (tx._statementFailed) {
            throw const OrmException(
              'TRANSACTION.FAILED',
              'A statement failed. Use a savepoint for recoverable errors.',
            );
          }
          committing = true;
          await _execute(connection, SqlCommand('COMMIT'));
          return result;
        } catch (error, stack) {
          tx._active = false;
          await Future.wait(tx._pending.toList());
          try {
            await _execute(connection, SqlCommand('ROLLBACK'));
          } catch (_) {
            await connection.invalidate();
          }
          if (committing) {
            throw OrmException(
              'TRANSACTION.COMMIT',
              'Commit failed; do not retry without checking its outcome.',
              cause: error,
            );
          }
          Error.throwWithStackTrace(error, stack);
        } finally {
          tx._active = false;
        }
      } finally {
        if (_connection != null) _childActive = false;
      }
    });
  }

  Future<R> savepoint<R>(Future<R> Function(Database<B> tx) action) {
    if (!inTransaction) {
      throw const OrmException(
        'TRANSACTION.REQUIRED',
        'Savepoints need a transaction.',
      );
    }
    return _run((connection) async {
      _childActive = true;
      final name = 'orm_sp_${_savepointId++}';
      final child = Database<B>._(driver, connection, onQuery);
      try {
        await _execute(connection, SqlCommand('SAVEPOINT $name'));
        final result = await action(child);
        child._active = false;
        if (child._pending.isNotEmpty || child._childActive) {
          await Future.wait(child._pending.toList());
          throw const OrmException(
            'TRANSACTION.UNAWAITED',
            'Await every savepoint operation.',
          );
        }
        if (child._statementFailed) {
          throw const OrmException(
            'TRANSACTION.FAILED',
            'A statement in the savepoint failed.',
          );
        }
        await _execute(connection, SqlCommand('RELEASE SAVEPOINT $name'));
        return result;
      } catch (error, stack) {
        child._active = false;
        await Future.wait(child._pending.toList());
        try {
          await _execute(connection, SqlCommand('ROLLBACK TO SAVEPOINT $name'));
          await _execute(connection, SqlCommand('RELEASE SAVEPOINT $name'));
        } catch (_) {
          _active = false;
          await connection.invalidate();
        }
        Error.throwWithStackTrace(error, stack);
      } finally {
        child._active = false;
        _childActive = false;
      }
    });
  }

  Future<void> close() async {
    if (_connection != null) {
      throw const OrmException(
        'SESSION.BORROWED',
        'A borrowed session cannot close its driver.',
      );
    }
    if (!_active) return;
    _active = false;
    await Future.wait(_pending.toList());
    await driver.close();
  }
}
