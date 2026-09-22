import 'dart:async';

import 'package:meta/meta.dart' show internal;

import '../../driver.dart';
import 'acquisition.dart';
import 'events.dart';
import 'mysql_transaction.dart';
import 'options.dart';
import 'transaction.dart';

/// Raw SQL execution with owned driver resources and explicit callback scopes.
///
/// The root database owns its [driver]. Session and transaction callbacks receive
/// borrowed views that expire when their callback finishes. Await every operation
/// before leaving those scopes; active cursors and unfinished work are rejected.
///
/// ```dart
/// Future<void> renameUser(SqlDatabase<Sqlite> db, int id, String name) async {
///   await db.transaction((tx) async {
///     await tx.execute(SqlCommand(
///       'UPDATE users SET name = ?1 WHERE id = ?2', [name, id],
///     ));
///   });
/// }
/// ```
///
/// {@category Execution}
class SqlDatabase<B extends Backend> {
  /// Driver owned by the root database and shared with its borrowed views.
  final Driver<B> driver;

  /// Optional observer for statements and cursor operations; errors are isolated.
  final void Function(QueryEvent)? onQuery;

  /// Optional observer for connection acquisition and existing-lease reuse.
  final void Function(AcquisitionEvent)? onAcquire;
  final SqlConnection? _connection;
  final bool _transaction;
  final TransactionControl? _control;
  final Set<Future<void>> _pending = {};
  final Set<Future<void> Function()> _streams = {};
  final Set<Future<void> Function()> _cursors = {};
  Future<void> _closeCursors() async {
    for (final close in _cursors.toList()) {
      await close();
    }
  }

  Future<void> _stopStreams() =>
      Future.wait(_streams.toList().map((stop) => stop()));
  bool _active = true;
  Future<void>? _closing;
  bool _childActive = false;
  bool _statementFailed = false;
  int _savepointId = 0;
  final List<void Function()> _invalidations = [];
  final Set<Future<void> Function()> _closeListeners = {};
  final Set<void Function(Set<String>)> _changeListeners;

  /// Listen for explicitly reported physical table changes after commit.
  /// Raw SQL is never parsed to guess the tables it changes.
  /// @nodoc
  @internal
  void Function() addChangeListener(void Function(Set<String>) listener) {
    checkActive();
    _changeListeners.add(listener);
    return () => _changeListeners.remove(listener);
  }

  /// Notify listeners of external or raw-SQL changes. Rollback discards these
  /// notifications; an uncertain COMMIT invalidates conservatively.
  void notifyChanged(Iterable<String> tables) {
    checkActive();
    _notifyChanged(tables);
  }

  void _notifyChanged(Iterable<String> tables) {
    final names = Set<String>.unmodifiable(tables);
    if (names.isEmpty) return;
    deferInvalidation(() {
      for (final listener in _changeListeners.toList()) {
        _notifyInvalidation(() => listener(names));
      }
    });
  }

  /// Schedule cache invalidation after the transaction finishes. Rollback drops
  /// these callbacks; an uncertain COMMIT runs them conservatively. Savepoint
  /// callbacks join the parent transaction only after successful release.
  /// @nodoc
  @internal
  void deferInvalidation(void Function() action) {
    if (inTransaction) {
      _invalidations.add(action);
    } else {
      _notifyInvalidation(action);
    }
  }

  /// Register owned resources to stop before pending SQL is drained on close.
  /// Returns a function that removes this listener.
  /// @nodoc
  @internal
  void Function() addCloseListener(Future<void> Function() listener) {
    checkActive();
    if (inSession) {
      throw const OrmException(
        'SESSION.BORROWED',
        'Close listeners belong to the root runtime that owns the driver.',
      );
    }
    _closeListeners.add(listener);
    return () => _closeListeners.remove(listener);
  }

  void _publishInvalidations() {
    final callbacks = List<void Function()>.of(_invalidations);
    _invalidations.clear();
    for (final callback in callbacks) {
      _notifyInvalidation(callback);
    }
  }

  static void _notifyInvalidation(void Function() callback) {
    try {
      callback();
    } catch (_) {} // Notification must not change a confirmed database outcome.
  }

  /// Mark this transaction as failed when a multi-statement operation stops
  /// between statements. Catching its exception cannot commit a partial batch.
  /// @nodoc
  @internal
  void markFailed() {
    if (inTransaction) _statementFailed = true;
  }

  /// Takes ownership of [driver]; close the root database to release it.
  SqlDatabase(this.driver, {this.onQuery, this.onAcquire})
    : _changeListeners = {},
      _connection = null,
      _transaction = false,
      _control = null;
  SqlDatabase._(
    this.driver,
    this._connection,
    this.onQuery, {
    this.onAcquire,
    this._transaction = true,
    this._control,
    required this._changeListeners,
  });

  /// Features and limits exposed by the actual driver and platform.
  Capabilities get capabilities => driver.capabilities;

  /// Connected engine used for SQL syntax and transaction validation.
  SqlDialect get dialect => capabilities.dialect;

  /// Whether this view belongs to a transaction or savepoint callback.
  bool get inTransaction => _transaction;

  /// Whether this view already holds a connection lease.
  bool get inSession => _connection != null;

  /// @nodoc
  @internal
  void checkActive() {
    if (!_active) {
      throw const OrmException(
        'SESSION.CLOSED',
        'SqlDatabase session has ended.',
      );
    }
    _control?.check();
    if (inTransaction && _connection?.transactionActive == false) {
      _statementFailed = true;
      throw const OrmException(
        'TRANSACTION.ENDED',
        'The database has ended this transaction.',
      );
    }
    if (_childActive) {
      throw const OrmException(
        'SESSION.SAVEPOINT',
        'Use the active nested session.',
      );
    }
  }

  /// Runs [action] with an acquired or already leased connection.
  ///
  /// This does not start a transaction. [acquire] limits only connection waiting;
  /// the connection must not escape [action]. Prefer [execute] for one command.
  Future<R> run<R>(
    Future<R> Function(SqlConnection) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
    OrmException? acquisitionTimeoutError,
  }) {
    checkActive();
    acquire.check();
    final connection = _connection == null
        ? null
        : _sessionConnection(_connection);
    final observer = onAcquire;
    final clock = observer == null || connection != null
        ? null
        : (Stopwatch()..start());
    var entered = false;
    void report(Object? error) {
      clock?.stop();
      try {
        observer?.call(
          AcquisitionEvent(
            elapsed: clock?.elapsed ?? Duration.zero,
            reusedConnection: connection != null,
            error: error,
          ),
        );
      } catch (_) {}
    }

    Future<R> enter(SqlConnection value) {
      entered = true;
      report(null);
      return action(value);
    }

    Future<R> observed(Future<R> result) => observer == null
        ? result
        : result.onError((Object error, StackTrace stack) {
            if (!entered) report(error);
            Error.throwWithStackTrace(error, stack);
          });
    final callback = observer == null ? action : enter;
    if (connection == null &&
        (acquire.timeout != null || acquire.cancellation != null)) {
      final wait = ConnectionWait(
        driver,
        callback,
        acquire,
        timeoutError: acquisitionTimeoutError,
      );
      _track(wait.drained);
      return observed(wait.result);
    }
    final result = connection != null
        ? Future.sync(() => callback(connection))
        : observer == null
        ? driver.run(action)
        : Future.sync(() => driver.run(callback));
    final done = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _track(done);
    return observed(result);
  }

  void _track(Future<void> done) {
    _pending.add(done);
    unawaited(done.then((_) => _pending.remove(done)));
  }

  SqlConnection _sessionConnection(SqlConnection connection) {
    if (!inSession) return connection;
    if (!identical(
          _physicalConnection(connection),
          _physicalConnection(_connection!),
        ) ||
        connection is _SessionConnection &&
            !identical(connection.owner, this)) {
      throw const OrmException(
        'SESSION.CONNECTION',
        'Use the connection owned by this session.',
      );
    }
    if (connection is _SessionConnection) return connection;
    return _SessionConnection(_connection, this);
  }

  /// @nodoc
  @internal
  Future<SqlResult> executeOn(
    SqlConnection connection,
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    checkActive();
    final result = _executeOn(
      _sessionConnection(connection),
      command,
      options: options,
    );
    _track(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return result;
  }

  Future<SqlResult> _executeOn(
    SqlConnection connection,
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    options.check();
    if (options.cancellation != null && !capabilities.cancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver cannot cancel a running statement.',
      );
    }
    if (options.timeout != null && !capabilities.statementTimeout) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver does not support statement timeouts.',
      );
    }
    if (command.parameters.length > capabilities.maxParameters) {
      throw const OrmException(
        'QUERY.PARAMETERS',
        'Query exceeds the driver parameter limit.',
      );
    }
    final watch = onQuery == null ? null : (Stopwatch()..start());
    SqlResult? result;
    Object? error;
    try {
      return result = await connection.execute(command, options: options);
    } catch (e) {
      error = e;
      if (inTransaction) _statementFailed = true;
      rethrow;
    } finally {
      watch?.stop();
      // Instrumentation cannot turn a successful commit into an apparent failure.
      try {
        onQuery?.call(
          QueryEvent(
            sql: command.sql,
            parameterCount: command.parameters.length,
            elapsed: watch!.elapsed,
            rowCount: result?.rows.length,
            error: error,
          ),
        );
      } catch (_) {}
    }
  }

  /// Executes bound SQL and returns raw rows and affected-row metadata.
  ///
  /// [changedTables] explicitly reports writes for query invalidation; SQL text
  /// is never parsed to infer write targets. A transaction publishes these changes
  /// after commit and discards them after a confirmed rollback.
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<String> changedTables = const [],
  }) {
    options.check();
    if (options.cancellation != null && !capabilities.cancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver cannot cancel a running statement.',
      );
    }
    if (options.timeout != null && !capabilities.statementTimeout) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver does not support statement timeouts.',
      );
    }
    final tables = List<String>.unmodifiable(changedTables);
    return run((connection) async {
      final result = await executeOn(connection, command, options: options);
      _notifyChanged(tables);
      return result;
    }, acquire: options.acquisition);
  }

  /// Retains one connection across transactions and session-scoped operations.
  /// The borrowed view expires when the callback returns.
  ///
  /// A session does not begin a transaction. Use its [transaction] method for
  /// atomic work; nested sessions are rejected. Returning with pending work or
  /// an active stream fails and drains the borrowed view before lease release.
  Future<R> session<R>(
    Future<R> Function(SqlDatabase<B> session) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) {
    if (_connection != null) {
      throw const OrmException(
        'SESSION.NESTED',
        'This session already owns a connection lease.',
      );
    }
    return run((connection) async {
      final session = SqlDatabase<B>._(
        driver,
        connection,
        onQuery,
        onAcquire: onAcquire,
        changeListeners: _changeListeners,
        transaction: false,
      );
      try {
        final result = await action(session);
        session._active = false;
        if (session._pending.isNotEmpty ||
            session._streams.isNotEmpty ||
            session._cursors.isNotEmpty) {
          throw const OrmException(
            'SESSION.UNAWAITED',
            'Await all work before releasing a session.',
          );
        }
        return result;
      } finally {
        final cleanup = await session._drain();
        if (cleanup != null) {
          await connection.invalidate();
          throw cleanup;
        }
      }
    }, acquire: acquire);
  }

  /// Discards a leased connection after its state can no longer be recovered.
  ///
  /// Only a borrowed session or transaction view can be discarded. The view
  /// becomes unusable immediately; this does not prove a submitted write rolled
  /// back and does not close an otherwise usable root driver or pool.
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

  /// Runs [action] atomically and returns its result after confirmed commit.
  ///
  /// A failed statement marks the transaction failed even if its exception is
  /// caught by application code. Use [savepoint] for recoverable work. Returning
  /// with pending operations fails; borrowed transaction views cannot be reused.
  ///
  /// [timeout] starts after connection acquisition. [retry] has its own total
  /// budget including acquisition and requires a safely repeatable callback.
  /// Deadlines, cancellation, and retries require actual driver cancellation.
  /// An uncertain COMMIT is reported and never replays the callback.
  Future<R> transaction<R>(
    Future<R> Function(SqlDatabase<B> tx) action, {
    TransactionOptions<B>? options,
    AcquisitionOptions acquire = const AcquisitionOptions(),
    Duration? timeout,
    CancellationToken? cancellation,
    TransactionRetry? retry,
  }) {
    checkActive();
    acquire.check();
    retry?.validate();
    if (options != null && options.dialect != dialect) {
      throw const OrmException(
        'TRANSACTION.OPTIONS',
        'Transaction options must match the connected database engine.',
      );
    }
    if (inTransaction) {
      throw const OrmException(
        'TRANSACTION.NESTED',
        'Use savepoint() inside a transaction.',
      );
    }
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const OrmException(
        'TRANSACTION.CANCELLED',
        'Transaction cancelled before acquisition.',
      );
    }
    if ((timeout != null || cancellation != null || retry != null) &&
        !capabilities.cancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'Transaction deadlines require actual statement cancellation.',
      );
    }
    final link = cancellation != null && acquire.cancellation != null
        ? CancellationLink([cancellation, acquire.cancellation!])
        : null;
    final budget = retry == null ? null : RetryBudget(retry);
    try {
      final acquireTimeout = budget?.limit(acquire.timeout) ?? acquire.timeout;
      final totalLimitsAcquisition =
          budget != null &&
          (acquire.timeout == null || acquireTimeout! < acquire.timeout!);
      return run(
        (connection) async {
          final executionTimeout = budget?.limit(timeout) ?? timeout;
          final control = executionTimeout == null && cancellation == null
              ? null
              : TransactionControl(executionTimeout, cancellation);
          if (_connection != null) _childActive = true;
          try {
            while (true) {
              try {
                return await _transactionAttempt(
                  connection is _SessionConnection
                      ? connection.inner
                      : connection,
                  control,
                  budget,
                  options,
                  action,
                );
              } on RetryAfterRollback catch (failure) {
                if (await budget!.next(control!)) continue;
                Error.throwWithStackTrace(failure.error, failure.stack);
              }
            }
          } finally {
            control?.dispose();
            if (_connection != null) _childActive = false;
          }
        },
        acquire: AcquisitionOptions(
          timeout: acquireTimeout,
          cancellation: link?.token ?? cancellation ?? acquire.cancellation,
        ),
        acquisitionTimeoutError: totalLimitsAcquisition
            ? const OrmException(
                'TRANSACTION.TIMEOUT',
                'Transaction retry time budget expired during acquisition.',
              )
            : null,
      ).whenComplete(() => link?.dispose());
    } catch (_) {
      link?.dispose();
      rethrow;
    }
  }

  Future<R> _transactionAttempt<R>(
    SqlConnection connection,
    TransactionControl? control,
    RetryBudget? budget,
    TransactionOptions<B>? options,
    Future<R> Function(SqlDatabase<B>) action,
  ) async {
    final scoped = control == null
        ? connection
        : TransactionConnection(connection, control);
    final tx = SqlDatabase<B>._(
      driver,
      scoped,
      onQuery,
      control: control,
      onAcquire: onAcquire,
      changeListeners: _changeListeners,
    );
    var committing = false, began = false;
    final begin =
        options?.beginCommands ??
        [
          dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb
              ? 'START TRANSACTION'
              : 'BEGIN',
        ];
    try {
      for (final statement in begin) {
        await _executeOn(scoped, SqlCommand(statement));
      }
      began = true;
      final result = control == null
          ? await action(tx)
          : await control.race(() => action(tx));
      tx._active = false;
      if (tx._pending.isNotEmpty ||
          tx._childActive ||
          tx._streams.isNotEmpty ||
          tx._cursors.isNotEmpty) {
        throw const OrmException(
          'TRANSACTION.UNAWAITED',
          'Await every operation before leaving the transaction.',
        );
      }
      control?.check();
      if (tx._statementFailed || connection.transactionActive == false) {
        throw const OrmException(
          'TRANSACTION.FAILED',
          'A statement failed or the transaction ended. Use a savepoint for recoverable errors.',
        );
      }
      Future<SqlResult> commit(ExecutionOptions execution) {
        committing = true;
        return _executeOn(connection, SqlCommand('COMMIT'), options: execution);
      }

      while (true) {
        try {
          if (control == null) {
            await commit(const ExecutionOptions());
          } else {
            await control.execute(commit, const ExecutionOptions());
          }
          break;
        } catch (error) {
          if (error is SqlFailure && error.commitRejected) {
            committing = false;
            if (budget != null &&
                error.retryCommit &&
                connection.transactionActive == true &&
                await budget.next(control!)) {
              continue;
            }
          }
          rethrow;
        }
      }
      // A confirmed COMMIT acknowledgement wins a cancellation race.
      tx._publishInvalidations();
      return result;
    } catch (error, stack) {
      // Classify an actual COMMIT response before applying a deadline error.
      final expired = control?.failure;
      var cleanup = await tx._drain();
      try {
        if (connection.transactionActive != false) {
          await _executeOn(connection, SqlCommand('ROLLBACK'));
        }
      } catch (e) {
        cleanup ??= e;
      }
      if (cleanup != null || !began && begin.length > 1) {
        // SET TRANSACTION can survive a failed START TRANSACTION. Discard this
        // lease so its next borrower never inherits partially set options.
        try {
          await connection.invalidate();
        } catch (_) {}
      }
      if (committing && !(error is SqlFailure && error.commitRejected)) {
        tx._publishInvalidations();
        throw OrmException(
          'TRANSACTION.COMMIT',
          'Commit outcome is unknown; do not replay the callback.',
          cause: error,
        );
      }
      if (cleanup != null) {
        throw OrmException(
          'TRANSACTION.ROLLBACK',
          'Rollback could not be confirmed; connection discarded.',
          cause: error,
        );
      }
      if ((began || begin.length == 1) &&
          expired == null &&
          error is SqlFailure &&
          error.retryTransaction &&
          budget != null) {
        throw RetryAfterRollback(error, stack);
      }
      Error.throwWithStackTrace(
        expired == null || identical(expired, error)
            ? error
            : OrmException(expired.code, expired.message, cause: error),
        stack,
      );
    } finally {
      tx._active = false;
    }
  }

  Future<Object?> _drain() async {
    _active = false;
    Object? error;
    try {
      await _stopStreams();
    } catch (e) {
      error = e;
    }
    await Future.wait(_pending.toList());
    try {
      await _closeCursors();
    } catch (e) {
      error ??= e;
    }
    return error;
  }

  /// Runs nested work inside the current transaction using a database savepoint.
  ///
  /// Use the child view exclusively until [action] finishes. Success releases the
  /// savepoint; failure rolls back the child work. A failed rollback invalidates
  /// the connection instead of allowing the parent to continue in uncertain state.
  Future<R> savepoint<R>(Future<R> Function(SqlDatabase<B> tx) action) {
    if (!inTransaction) {
      throw const OrmException(
        'TRANSACTION.REQUIRED',
        'Savepoints need a transaction.',
      );
    }
    return run((connection) async {
      _childActive = true;
      // This path owns SAVEPOINT/RELEASE. User SQL keeps the guarded lease.
      final scoped = connection is _SessionConnection
          ? connection.inner
          : connection;
      final name = 'orm_sp_${_savepointId++}';
      final child = SqlDatabase<B>._(
        driver,
        scoped,
        onQuery,
        onAcquire: onAcquire,
        changeListeners: _changeListeners,
        control: _control,
      );
      try {
        await _executeOn(scoped, SqlCommand('SAVEPOINT $name'));
        final result = _control == null
            ? await action(child)
            : await _control.race(() => action(child));
        child._active = false;
        if (child._pending.isNotEmpty ||
            child._childActive ||
            child._streams.isNotEmpty ||
            child._cursors.isNotEmpty) {
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
        await _executeOn(scoped, SqlCommand('RELEASE SAVEPOINT $name'));
        _invalidations.addAll(child._invalidations);
        child._invalidations.clear();
        return result;
      } catch (error, stack) {
        final cleanup = await child._drain();
        final raw = unscopedConnection(scoped);
        try {
          if (cleanup != null) throw cleanup;
          if (raw.transactionActive == false) {
            // SQLite may have rolled back the whole transaction, not this savepoint.
            _statementFailed = true;
          } else {
            await _executeOn(raw, SqlCommand('ROLLBACK TO SAVEPOINT $name'));
            await _executeOn(raw, SqlCommand('RELEASE SAVEPOINT $name'));
          }
        } catch (_) {
          _active = false;
          _statementFailed = true;
          await raw.invalidate();
        }
        Error.throwWithStackTrace(error, stack);
      } finally {
        child._active = false;
        _childActive = false;
      }
    });
  }

  /// Stops owned streams and watches, drains pending work, then closes the driver.
  ///
  /// Only the root database can close its driver. New operations are rejected
  /// once closing starts; concurrent close calls await the same cleanup.
  Future<void> close() async {
    if (_connection != null) {
      throw const OrmException(
        'SESSION.BORROWED',
        'A borrowed session cannot close its driver.',
      );
    }
    await (_closing ??= _close());
  }

  Future<void> _close() async {
    _active = false;
    try {
      try {
        await Future.wait(
          _closeListeners.toList().map(
            (listener) => Future<void>.sync(listener),
          ),
        );
      } finally {
        _closeListeners.clear();
        _changeListeners.clear();
        await _stopStreams();
      }
    } finally {
      await Future.wait(_pending.toList());
      await driver.close();
    }
  }
}

/// A session's public execution port. The underlying physical lease and its
/// transaction controls stay private to the runtime.
final class _SessionConnection(
  final SqlConnection inner,
  final SqlDatabase<Backend> owner,
) implements SqlConnection {
  @override
  bool? get transactionActive => inner.transactionActive;

  Future<T> _run<T>(Future<T> Function() action, {String? sql}) {
    final result = Future<T>.sync(() async {
      owner.checkActive();
      try {
        if (sql != null &&
            owner.inTransaction &&
            (owner.dialect == SqlDialect.mysql ||
                owner.dialect == SqlDialect.mariadb)) {
          checkMysqlTransactionSql(sql);
        }
        return await action();
      } catch (_) {
        owner.markFailed();
        rethrow;
      }
    });
    owner._track(
      result.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return result;
  }

  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => _run(() => inner.execute(command, options: options), sql: command.sql);

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => _run(() async {
    final cursor = _SessionCursor(
      await inner.openCursor(command, options: options),
      this,
    );
    owner._cursors.add(cursor.close);
    return cursor;
  }, sql: command.sql);

  @override
  Future<void> invalidate() {
    owner.checkActive();
    owner.markFailed();
    return inner.invalidate();
  }
}

final class _SessionCursor(
  final SqlCursor inner,
  final _SessionConnection connection,
) implements SqlCursor {
  Future<void>? _closing;
  @override
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => connection._run(() {
    if (_closing != null) {
      throw const OrmException('CURSOR.CLOSED', 'Cursor has ended.');
    }
    return inner.fetch(count, options: options);
  });
  // Cleanup is allowed after the callback/deadline ends and runs only once.
  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      await inner.close();
    } catch (_) {
      connection.owner.markFailed();
      rethrow;
    } finally {
      connection.owner._cursors.remove(close);
    }
  }
}

SqlConnection _physicalConnection(SqlConnection connection) =>
    switch (connection) {
      _SessionConnection() => _physicalConnection(connection.inner),
      TransactionConnection() => _physicalConnection(connection.inner),
      _ => connection,
    };

/// Demand-driven raw-row streaming with a bounded database cursor.
///
/// {@category Execution}
extension SqlDatabaseStreaming on SqlDatabase<Backend> {
  /// Streams raw rows, fetching at most [batchSize] rows per database request.
  ///
  /// Listening holds a connection until completion or subscription cancellation.
  /// Outside a transaction, the stream owns a read transaction and rolls it back
  /// on early exit. Pausing the subscription prevents the next batch fetch; an
  /// asynchronous `listen` callback must explicitly pause for demand control.
  Stream<List<Object?>> stream(
    SqlCommand command, {
    int batchSize = 128,
    ExecutionOptions options = const ExecutionOptions(),
  }) => streamRows(
    command,
    batchSize: batchSize,
    options: options,
    decode: (_, batch, _) async => batch.rows,
  );

  /// @nodoc
  @internal
  Stream<R> streamRows<R>(
    SqlCommand command, {
    required int batchSize,
    required ExecutionOptions options,
    required Future<List<R>> Function(
      SqlConnection,
      SqlResult,
      ExecutionOptions,
    )
    decode,
  }) {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    if (!capabilities.streaming) {
      throw const OrmException(
        'CAPABILITY.STREAM',
        'This driver does not support database cursors.',
      );
    }
    if ((options.cancellation != null || options.timeout != null) &&
        !capabilities.cancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver cannot cancel a running statement.',
      );
    }
    options.check();
    if (command.parameters.length > capabilities.maxParameters) {
      throw const OrmException(
        'QUERY.PARAMETERS',
        'Query exceeds the driver parameter limit.',
      );
    }
    final cancellation = CancellationToken();
    final execution = ExecutionOptions(
      cancellation: capabilities.cancellation ? cancellation : null,
      timeout: options.timeout,
    );
    final finished = Completer<void>();
    Completer<void>? demand;
    var stopped = false, started = false;
    Object? cleanupFailure, requestedError;
    late StreamController<R> controller;
    void requestStop() {
      stopped = true;
      cancellation.cancel();
      demand?.complete();
      demand = null;
    }

    Future<void> stop() async {
      requestStop();
      if (started) await finished.future;
      if (cleanupFailure != null) throw cleanupFailure!;
    }

    Future<void> waitForDemand() async {
      if (controller.isPaused && !stopped) {
        demand ??= Completer<void>();
        await demand!.future;
      }
    }

    Future<T> observe<T>(
      QueryOperation operation,
      Future<T> Function() action,
    ) async {
      final watch = onQuery == null ? null : (Stopwatch()..start());
      Object? error;
      T? result;
      try {
        return result = await action();
      } catch (e) {
        error = e;
        if (inTransaction) _statementFailed = true;
        rethrow;
      } finally {
        watch?.stop();
        try {
          onQuery?.call(
            QueryEvent(
              operation: operation,
              sql: command.sql,
              parameterCount: operation == .cursorOpen
                  ? command.parameters.length
                  : 0,
              elapsed: watch!.elapsed,
              rowCount: result is SqlResult ? result.rows.length : null,
              error: error,
            ),
          );
        } catch (_) {}
      }
    }

    Future<void> produce() async {
      started = true;
      _streams.add(stop);
      final unsubscribe = options.cancellation?.listen(() {
        requestedError = const OrmException(
          'OPERATION.CANCELLED',
          'Stream cancelled.',
        );
        requestStop();
      });
      try {
        await run(
          (connection) async {
            final ownsTransaction = !inTransaction;
            SqlCursor? cursor;
            var complete = false, began = false;
            try {
              if (stopped) return;
              if (ownsTransaction) {
                await _executeOn(
                  connection is _SessionConnection
                      ? connection.inner
                      : connection,
                  SqlCommand(switch (dialect) {
                    SqlDialect.postgres => 'BEGIN READ ONLY',
                    SqlDialect.mysql ||
                    SqlDialect.mariadb => 'START TRANSACTION READ ONLY',
                    SqlDialect.sqlite => 'BEGIN',
                  }),
                );
                began = true;
              }
              cursor = await observe(
                .cursorOpen,
                () => connection.openCursor(command, options: execution),
              );
              while (!stopped) {
                await waitForDemand();
                if (stopped) break;
                final batch = await observe(
                  .cursorFetch,
                  () => cursor!.fetch(batchSize, options: execution),
                );
                if (stopped) break;
                final rows = await decode(connection, batch, execution);
                for (final row in rows) {
                  await waitForDemand();
                  if (stopped) break;
                  controller.add(row);
                }
                if (batch.rows.length < batchSize) {
                  complete = !stopped;
                  break;
                }
              }
            } finally {
              try {
                if (cursor != null) await observe(.cursorClose, cursor.close);
                if (began) {
                  await _executeOn(
                    connection is _SessionConnection
                        ? connection.inner
                        : connection,
                    SqlCommand(complete ? 'COMMIT' : 'ROLLBACK'),
                  );
                }
              } catch (e) {
                cleanupFailure = e;
                if (inTransaction) _active = false;
                await connection.invalidate();
                rethrow;
              }
            }
          },
          acquire: AcquisitionOptions(
            timeout: options.acquireTimeout,
            cancellation: cancellation,
          ),
        );
      } catch (error, stack) {
        if (!stopped) controller.addError(error, stack);
      } finally {
        unsubscribe?.call();
        if (requestedError != null) controller.addError(requestedError!);
        _streams.remove(stop);
        finished.complete();
        // A cancellation cleanup error is already exposed by stop() or the
        // error event. Do not report it again through an unobserved close future.
        unawaited(controller.close().catchError((Object _) {}));
      }
    }

    controller = StreamController<R>(
      sync: true,
      onListen: () => unawaited(produce()),
      onPause: () {
        demand ??= Completer<void>();
      },
      onResume: () {
        demand?.complete();
        demand = null;
      },
      onCancel: stop,
    );
    return controller.stream;
  }
}
