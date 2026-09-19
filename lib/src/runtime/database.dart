part of '../../runtime.dart';

/// SqlDatabase owns its driver. A transaction view borrows one connection and
/// becomes unusable as soon as its callback finishes.
class SqlDatabase<B extends Backend> {
  final Driver<B> driver;
  final void Function(QueryEvent)? onQuery;
  final void Function(AcquisitionEvent)? onAcquire;
  final SqlConnection? _connection;
  final bool _transaction;
  final _TransactionControl? _control;
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
  void deferInvalidation(void Function() action) {
    if (inTransaction) {
      _invalidations.add(action);
    } else {
      _notifyInvalidation(action);
    }
  }

  /// Register owned resources to stop before pending SQL is drained on close.
  /// Returns a function that removes this listener.
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
  void markFailed() {
    if (inTransaction) _statementFailed = true;
  }

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
  Capabilities get capabilities => driver.capabilities;
  SqlDialect get dialect => capabilities.dialect;
  bool get inTransaction => _transaction;
  bool get inSession => _connection != null;

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
      final wait = _ConnectionWait(
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
    Future<R> Function(SqlDatabase<B> tx) action, {
    TransactionOptions<B>? options,
    AcquisitionOptions acquire = const AcquisitionOptions(),
    Duration? timeout,
    CancellationToken? cancellation,
    TransactionRetry? retry,
  }) {
    checkActive();
    acquire.check();
    retry?._check();
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
        ? _CancellationLink([cancellation, acquire.cancellation!])
        : null;
    final budget = retry == null ? null : _RetryBudget(retry);
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
              : _TransactionControl(executionTimeout, cancellation);
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
              } on _RetryAfterRollback catch (failure) {
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
    _TransactionControl? control,
    _RetryBudget? budget,
    TransactionOptions<B>? options,
    Future<R> Function(SqlDatabase<B>) action,
  ) async {
    final scoped = control == null
        ? connection
        : _TransactionConnection(connection, control);
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
        throw _RetryAfterRollback(error, stack);
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
        final raw = _unscoped(scoped);
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
