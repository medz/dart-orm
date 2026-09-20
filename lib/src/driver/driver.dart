import '../../values.dart';

/// SQL engine used for quoting, parameter syntax, and capability validation.
enum SqlDialect {
  /// SQLite on native and browser platforms.
  sqlite,

  /// PostgreSQL with its own SQL and type semantics.
  postgres,

  /// MySQL, distinct from MariaDB for schema and capability checks.
  mysql,

  /// MariaDB, distinct from MySQL for schema and capability checks.
  mariadb,
}

/// SQL text and separately bound values. Values are never interpolated into SQL.
final class SqlCommand {
  /// SQL text using the target driver's parameter placeholder syntax.
  final String sql;

  /// Bound values in placeholder order; the constructor copies this list.
  final List<Object?> parameters;

  /// Creates a command without parsing SQL or opening a connection.
  SqlCommand(this.sql, [List<Object?> parameters = const []])
    : parameters = List.unmodifiable(parameters);
}

/// Static engine identity used to constrain driver and transaction APIs.
///
/// Values do not hold connections or configuration; use the corresponding
/// driver options when opening a database.
sealed class Backend {
  /// Creates an engine type marker.
  const Backend();
}

/// Type marker for PostgreSQL drivers and sessions.
final class Postgres extends Backend {
  /// Creates a PostgreSQL type marker without opening a connection.
  const Postgres();
}

/// Type marker for native and browser SQLite drivers and sessions.
final class Sqlite extends Backend {
  /// Creates a SQLite type marker without opening a database.
  const Sqlite();
}

/// Type marker for MySQL drivers and sessions.
final class Mysql extends Backend {
  /// Creates a MySQL type marker without opening a connection.
  const Mysql();
}

/// Type marker for MariaDB drivers and sessions.
final class Mariadb extends Backend {
  /// Creates a MariaDB type marker without opening a connection.
  const Mariadb();
}

/// Features a concrete driver can execute for its actual engine and platform.
///
/// Query and runtime layers check these limits before submitting unsupported
/// work. A database product may support more than its current adapter exposes.
///
/// {@category Drivers}
final class Capabilities {
  /// Engine syntax and semantics used by this connection.
  final SqlDialect dialect;

  /// Maximum bound parameter count for a single statement.
  final int maxParameters;

  /// Whether writes support returning selected rows directly.
  final bool returning;

  /// Whether the adapter supports SQL window expressions.
  final bool windowFunctions;

  /// Whether callers can fetch bounded batches through [SqlCursor].
  final bool streaming;

  /// Whether an active statement can receive a cancellation request.
  final bool cancellation;

  /// Honors statement deadlines, potentially by discarding the connection.
  /// A timeout does not prove that a submitted write was rolled back.
  final bool statementTimeout;

  /// Whether the adapter supplies the ORM's exact decimal SQL behavior.
  final bool exactDecimal;

  /// Whether exact calendar and UTC instant storage conversions are configured.
  final bool temporal;

  /// Declares adapter capabilities; deadlines default to cancellation support.
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

/// Raw row values and write metadata returned by a completed driver operation.
final class SqlResult {
  /// Rows in result order, with values in [columns] order when names are known.
  final List<List<Object?>> rows;

  /// Physical result column labels, or an empty list if unavailable.
  final List<String> columns;

  /// Number of affected rows reported by the engine; defaults to zero.
  final int affectedRows;

  /// Generated identity returned directly by the server, when available.
  final int? lastInsertId;

  /// Retains the supplied row lists without copying them.
  const SqlResult(
    this.rows, {
    this.columns = const [],
    this.affectedRows = 0,
    this.lastInsertId,
  });
}

/// Execution port for one physical connection during an active driver lease.
///
/// Await each operation before issuing another one on the same connection.
/// Connection ownership remains with the [Driver]; application code uses [Driver.run]
/// through that driver rather than retaining the connection beyond its callback.
///
/// {@category Drivers}
abstract interface class SqlConnection {
  /// Actual adapter state after the last completed request; null if unavailable.
  bool? get transactionActive;

  /// Executes SQL with separately bound parameters and per-statement controls.
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  });

  /// Opens a bounded-fetch cursor when the driver supports streaming.
  ///
  /// Engine-specific transaction requirements still apply. Close the cursor
  /// before returning its connection lease.
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  });

  /// Permanently discard a connection whose protocol or transaction is uncertain.
  Future<void> invalidate();
}

/// Owns or borrows connection resources for a specific engine [B].
///
/// Implementations lease one connection for each [run] callback and return it
/// after the callback settles. The driver contract does not imply that a callback
/// is a transaction: use a SQL runtime or explicitly issue transaction commands.
///
/// ```dart
/// Future<int> countUsers(Driver<Sqlite> driver) => driver.run((connection) async {
///   final result = await connection.execute(SqlCommand('SELECT COUNT(*) FROM users'));
///   return result.rows.single.single as int;
/// });
/// ```
///
/// {@category Drivers}
abstract interface class Driver<B extends Backend> {
  /// Features and limits exposed by this adapter and its actual backend.
  Capabilities get capabilities;

  /// Leases one connection until [action] completes or throws.
  ///
  /// Do not retain the connection or start unawaited work beyond the callback.
  Future<R> run<R>(Future<R> Function(SqlConnection) action);

  /// Rejects new work and releases resources owned by this driver.
  ///
  /// Borrowed external pools remain owned by the caller. Concrete adapters
  /// document how already accepted work is drained before completion.
  Future<void> close();
}

/// A cancellation request. Await the operation itself to observe its actual
/// database outcome; completion can win a race with cancellation.
final class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};

  /// Whether cancellation has been requested; it does not describe SQL outcome.
  bool get isCancelled => _cancelled;

  /// Requests cancellation once and notifies all currently registered listeners.
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

/// Per-operation connection acquisition and statement execution controls.
///
/// Acquisition and statement deadlines are independent. A deadline expiring after
/// submission does not establish whether a write committed or was rolled back.
final class ExecutionOptions {
  /// Optional cancellation request shared by acquisition and execution.
  final CancellationToken? cancellation;

  /// Time allowed to acquire a lease. Independent of statement [timeout].
  final Duration? acquireTimeout;

  /// Limit for each database statement/fetch, not time spent consuming rows.
  final Duration? timeout;

  /// Creates optional controls; omitted deadlines use runtime or driver defaults.
  const ExecutionOptions({
    this.cancellation,
    this.timeout,
    this.acquireTimeout,
  });

  /// Connection-wait controls derived without including the statement deadline.
  AcquisitionOptions get acquisition =>
      acquireTimeout == null && cancellation == null
      ? const AcquisitionOptions()
      : AcquisitionOptions(timeout: acquireTimeout, cancellation: cancellation);

  /// Rejects non-positive deadlines and cancellation requested before execution.
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
  /// Optional positive deadline for obtaining a usable connection lease.
  final Duration? timeout;

  /// Cancellation request observed only while waiting for acquisition.
  final CancellationToken? cancellation;

  /// Creates connection-wait controls independent of statement deadlines.
  const AcquisitionOptions({this.timeout, this.cancellation});

  /// Rejects an invalid deadline or cancellation already requested.
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

/// Bounded row retrieval tied to the connection lease that opened it.
abstract interface class SqlCursor {
  /// Fetches at most [count] rows; an empty batch marks the end of the result.
  ///
  /// [count] must be positive. Await a fetch before requesting the next batch.
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  });

  /// Releases the cursor; cleanup is safe to request more than once.
  Future<void> close();
}

/// Adapter classification. Retrying also requires a confirmed rollback and an
/// explicitly repeatable application callback; these flags alone are not enough.
abstract interface class SqlFailure implements Exception {
  /// Whether this failure can be considered for a complete transaction retry.
  bool get retryTransaction;

  /// Retry the same COMMIT only while the adapter confirms the transaction is active.
  bool get retryCommit;

  /// Whether the error establishes that this COMMIT was rejected by the server.
  bool get commitRejected;
}
