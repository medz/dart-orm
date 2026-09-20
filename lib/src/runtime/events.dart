/// The driver operation measured by a [QueryEvent].
enum QueryOperation {
  /// A complete non-streaming statement, including transaction control SQL.
  execute,

  /// Opening a database cursor before rows are fetched.
  cursorOpen,

  /// Fetching the next bounded batch from an open cursor.
  cursorFetch,

  /// Releasing a cursor and its database resources.
  cursorClose,
}

/// Timing and outcome of one SQL statement or cursor operation.
///
/// Parameter values are deliberately absent. Observer exceptions are isolated
/// from the operation and cannot turn a successful commit into a failed result.
///
/// {@category Observability}
final class QueryEvent {
  /// Kind of statement or cursor operation measured.
  final QueryOperation operation;

  /// Parameterized command text; cursor events retain their source query SQL.
  final String sql;

  /// Bound value count; cursor fetch and close operations report zero.
  final int parameterCount;

  /// Elapsed driver execution time, excluding connection acquisition.
  final Duration elapsed;

  /// Number of returned rows, or null if no result was produced.
  final int? rowCount;

  /// Failure raised by the operation, or null on success.
  final Object? error;

  /// Records a measured operation without retaining bound parameter values.
  const QueryEvent({
    this.operation = QueryOperation.execute,
    required this.sql,
    required this.parameterCount,
    required this.elapsed,
    this.rowCount,
    this.error,
  });
}

/// Time until a driver lease is granted or acquisition fails. Includes native
/// pool wait/connection setup; it does not separate those driver internals.
///
/// {@category Observability}
final class AcquisitionEvent {
  /// Time to obtain a driver lease; zero for an already leased connection.
  final Duration elapsed;

  /// Whether execution reused a connection belonging to the current session.
  final bool reusedConnection;

  /// Acquisition failure, or null when the callback receives its connection.
  final Object? error;

  /// Records connection-wait timing independently of SQL execution timing.
  const AcquisitionEvent({
    required this.elapsed,
    required this.reusedConnection,
    this.error,
  });
}
