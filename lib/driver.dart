/// Raw SQL driver contracts. Independent of query builders and ORM sessions.
library;

import 'values.dart';
export 'values.dart';

enum SqlDialect { sqlite, postgres, mysql, mariadb }

/// SQL text and separately bound values. Values are never interpolated into SQL.
final class SqlCommand {
  final String sql;
  final List<Object?> parameters;
  SqlCommand(this.sql, [List<Object?> parameters = const []])
    : parameters = List.unmodifiable(parameters);
}

sealed class Backend {
  const Backend();
}

final class Postgres extends Backend {
  const Postgres();
}

final class Sqlite extends Backend {
  const Sqlite();
}

final class Mysql extends Backend {
  const Mysql();
}

final class Mariadb extends Backend {
  const Mariadb();
}

final class Capabilities {
  final SqlDialect dialect;
  final int maxParameters;
  final bool returning;
  final bool windowFunctions;
  final bool streaming;
  final bool cancellation;

  /// Honors statement deadlines, potentially by discarding the connection.
  /// A timeout does not prove that a submitted write was rolled back.
  final bool statementTimeout;
  final bool exactDecimal;
  final bool temporal;
  const Capabilities({
    required this.dialect,
    required this.maxParameters,
    this.returning = true,
    this.windowFunctions = true,
    this.streaming = false,
    this.cancellation = false,
    bool? statementTimeout,
    this.exactDecimal = false,
    this.temporal = false,
  }) : statementTimeout = statementTimeout ?? cancellation;
}

final class SqlResult {
  final List<List<Object?>> rows;
  final List<String> columns;
  final int affectedRows;

  /// Generated identity returned directly by the server, when available.
  final int? lastInsertId;
  const SqlResult(
    this.rows, {
    this.columns = const [],
    this.affectedRows = 0,
    this.lastInsertId,
  });
}

abstract interface class SqlConnection {
  /// Actual adapter state after the last completed request; null if unavailable.
  bool? get transactionActive;
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

/// A cancellation request. Await the operation itself to observe its actual
/// database outcome; completion can win a race with cancellation.
final class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      _notify(listener);
    }
    _listeners.clear();
  }

  /// Adapter hook; returns a function that removes the listener.
  /// Listener errors are isolated so every pending operation receives cancellation.
  void Function() listen(void Function() listener) {
    if (_cancelled) {
      _notify(listener);
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify(void Function() listener) {
    try {
      listener();
    } catch (_) {}
  }
}

final class ExecutionOptions {
  final CancellationToken? cancellation;

  /// Time allowed to acquire a lease. Independent of statement [timeout].
  final Duration? acquireTimeout;

  /// Limit for each database statement/fetch, not time spent consuming rows.
  final Duration? timeout;
  const ExecutionOptions({
    this.cancellation,
    this.timeout,
    this.acquireTimeout,
  });
  AcquisitionOptions get acquisition =>
      acquireTimeout == null && cancellation == null
      ? const AcquisitionOptions()
      : AcquisitionOptions(timeout: acquireTimeout, cancellation: cancellation);
  void check() {
    if (acquireTimeout != null && acquireTimeout! <= Duration.zero) {
      throw ArgumentError.value(acquireTimeout, 'acquireTimeout');
    }
    if (timeout != null && timeout! <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const OrmException(
        'OPERATION.CANCELLED',
        'Cancelled before starting a database operation.',
      );
    }
  }
}

/// Limits waiting for a connection, including establishment and initialization.
/// Cancellation after acquisition does not cancel the session callback.
final class AcquisitionOptions {
  final Duration? timeout;
  final CancellationToken? cancellation;
  const AcquisitionOptions({this.timeout, this.cancellation});
  void check() {
    if (timeout != null && timeout! <= Duration.zero) {
      throw ArgumentError.value(timeout, 'acquireTimeout');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const OrmException(
        'OPERATION.CANCELLED',
        'Connection acquisition cancelled.',
      );
    }
  }
}

abstract interface class SqlCursor {
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  });
  Future<void> close();
}

/// Adapter classification. Retrying also requires a confirmed rollback and an
/// explicitly repeatable application callback; these flags alone are not enough.
abstract interface class SqlFailure implements Exception {
  bool get retryTransaction;

  /// Retry the same COMMIT only while the adapter confirms the transaction is active.
  bool get retryCommit;
  bool get commitRejected;
}
