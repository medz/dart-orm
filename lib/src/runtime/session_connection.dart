part of '../../runtime.dart';

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
          _checkMysqlTransactionSql(sql);
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
      _TransactionConnection() => _physicalConnection(connection.inner),
      _ => connection,
    };
