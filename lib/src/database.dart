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
  final bool streaming;
  final bool cancellation;
  const Capabilities({
    required this.dialect,
    required this.maxParameters,
    this.returning = true,
    this.windowFunctions = true,
    this.streaming = false,
    this.cancellation = false,
  });
}

final class SqlResult {
  final List<List<Object?>> rows;
  final List<String> columns;
  final int affectedRows;
  const SqlResult(this.rows, {this.columns = const [], this.affectedRows = 0});
}

abstract interface class SqlConnection {
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  });
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  });

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

enum QueryOperation { execute, cursorOpen, cursorFetch, cursorClose }

final class QueryEvent {
  final QueryOperation operation;
  final String sql;
  final int parameterCount;
  final Duration elapsed;
  final int? rowCount;
  final Object? error;
  const QueryEvent({
    this.operation = QueryOperation.execute,
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
  final Set<Future<void> Function()> _streams = {};
  Future<void> _stopStreams() =>
      Future.wait(_streams.toList().map((stop) => stop()));
  bool _active = true;
  bool _childActive = false;
  bool _statementFailed = false;
  int _savepointId = 0;
  late final _ChangeHub _changes = _changeHubs[driver] ??= _ChangeHub();
  final Map<String, bool> _pendingChanges = {};

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

  /// Register declared FK effects for query invalidation. Generated accessors
  /// register their schema once; hand-authored clients can do the same here.
  void registerSchema(Iterable<TableSchema> tables) =>
      _changes.register(tables);

  /// Explicit notification for raw SQL, triggers or externally committed work.
  /// Inside a transaction this is deferred until its successful commit.
  void invalidate(Iterable<TableSchema> tables) {
    _checkActive();
    _recordChanges(tables, cascade: true);
  }

  void _recordChanges(Iterable<TableSchema> tables, {required bool cascade}) {
    final changes = <String, bool>{};
    for (final table in tables) {
      _changes.registerTable(table);
      changes[table.name] = cascade;
    }
    if (inTransaction) {
      _mergeChanges(_pendingChanges, changes);
    } else {
      _changes.publish(changes);
    }
  }

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

  Future<R> _run<R>(
    Future<R> Function(SqlConnection) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) {
    _checkActive();
    acquire.check();
    final connection = _connection;
    if (connection == null &&
        (acquire.timeout != null || acquire.cancellation != null)) {
      final wait = _ConnectionWait(driver, action, acquire);
      _track(wait.drained);
      return wait.result;
    }
    final result = connection != null
        ? Future.sync(() => action(connection))
        : driver.run(action);
    final done = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _track(done);
    return result;
  }

  void _track(Future<void> done) {
    _pending.add(done);
    unawaited(done.then((_) => _pending.remove(done)));
  }

  Future<SqlResult> _execute(
    SqlConnection connection,
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    options.check();
    if ((options.cancellation != null || options.timeout != null) &&
        !capabilities.cancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver cannot cancel a running statement.',
      );
    }
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
      return result = await connection.execute(command, options: options);
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

  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
  }) =>
      _executeCommand(command, options: options, changedTables: changedTables);

  Future<SqlResult> _executeCommand(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
    bool affectedOnly = false,
    bool cascade = true,
  }) {
    options.check();
    if ((options.cancellation != null || options.timeout != null) &&
        !capabilities.cancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver cannot cancel a running statement.',
      );
    }
    final tables = List<TableSchema>.unmodifiable(changedTables);
    if (tables.isEmpty) {
      return _run(
        (c) => _execute(c, command, options: options),
        acquire: options._acquisition,
      );
    }
    return _run((c) async {
      final result = await _execute(c, command, options: options);
      if (!affectedOnly || result.affectedRows > 0) {
        _recordChanges(tables, cascade: cascade);
      }
      return result;
    }, acquire: options._acquisition);
  }

  /// Retains one connection across transactions and session-scoped operations.
  /// The borrowed view expires when the callback returns.
  Future<R> session<R>(
    Future<R> Function(Database<B> session) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) {
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
          await session._stopStreams();
          await Future.wait(session._pending.toList());
          throw const OrmException(
            'SESSION.UNAWAITED',
            'Await all work before releasing a session.',
          );
        }
        return result;
      } finally {
        session._active = false;
        await session._stopStreams();
        await Future.wait(session._pending.toList());
      }
    }, acquire: acquire);
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
    AcquisitionOptions acquire = const AcquisitionOptions(),
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
            await tx._stopStreams();
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
          _changes.publish(tx._pendingChanges);
          return result;
        } catch (error, stack) {
          tx._active = false;
          await tx._stopStreams();
          await Future.wait(tx._pending.toList());
          try {
            await _execute(connection, SqlCommand('ROLLBACK'));
          } catch (_) {
            await connection.invalidate();
          }
          if (committing) {
            // The server may have committed before the acknowledgement failed.
            // Re-read affected queries rather than promising a rollback.
            _changes.publish(tx._pendingChanges);
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
    }, acquire: acquire);
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
          await child._stopStreams();
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
        _mergeChanges(_pendingChanges, child._pendingChanges);
        return result;
      } catch (error, stack) {
        child._active = false;
        await child._stopStreams();
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
    try {
      await _changes.stop();
      await _stopStreams();
    } finally {
      await Future.wait(_pending.toList());
      await driver.close();
    }
  }
}
