/// The fixed database engine used by a connection and migration history.
enum Engine { sqlite, postgresql }

/// Transaction isolation. Drivers reject levels their engine cannot provide.
enum Isolation { readCommitted, repeatableRead, serializable }

/// Driver capabilities are checked before executing dependent operations.
final class Capabilities {
  const Capabilities({required this.returning, required this.maxParameters});
  final bool returning;
  final int maxParameters;
}

/// A complete result from one database statement.
final class QueryResult {
  const QueryResult({
    this.columns = const [],
    this.rows = const [],
    this.affectedRows = 0,
  });
  final List<String> columns;
  final List<List<Object?>> rows;
  final int affectedRows;
}

/// One acquired physical connection. Ownership belongs to the driver callback.
abstract interface class Connection {
  /// Executes with the parameter values supplied at invocation, including bytes.
  /// The caller may reuse its parameter list and byte buffers after calling.
  Future<QueryResult> run(String sql, List<Object?> parameters);
}

/// Engines own connection acquisition and release; runtime owns transactions.
abstract interface class Driver {
  Engine get engine;

  /// Fixed schema for managed tables: `main` on SQLite, an application schema
  /// on PostgreSQL. Typed queries qualify names instead of using search_path.
  String get schema;

  Capabilities get capabilities;
  Future<T> withConnection<T>(Future<T> Function(Connection connection) action);
  Future<void> close();
}

/// Observable statement and transaction boundaries. Values are not exposed.
final class DatabaseEvent {
  const DatabaseEvent({
    required this.kind,
    required this.sql,
    required this.elapsed,
    required this.rows,
    this.transactionId,
  });
  final String kind;
  final String sql;
  final Duration elapsed;
  final int rows;
  final int? transactionId;
}

typedef DatabaseObserver = void Function(DatabaseEvent event);

/// An explicit execution scope. Transaction scopes expire after their callback.
abstract interface class Session {
  Engine get engine;

  /// The fixed schema captured when the database took ownership of its driver.
  String get schema;

  Capabilities get capabilities;
  bool get inTransaction;

  /// Executes one trusted SQL statement with driver-native placeholders.
  ///
  /// Use [Database.transaction] for transaction boundaries and options. Raw
  /// SQL remains application-owned code, including functions it invokes; such
  /// functions can intentionally change engine configuration. This API does
  /// not sandbox raw SQL.
  /// Generated table queries validate fields and bind application values.
  /// The parameter list and byte contents are captured at invocation, before
  /// acquisition or queuing. Later caller mutations do not change this work.
  Future<QueryResult> run(String sql, {List<Object?> parameters = const []});
}

/// Owns a driver. Closing waits for active work and invalidates all scopes.
abstract interface class Database {
  Session get session;
  Future<T> transaction<T>(
    Future<T> Function(Session session) action, {
    Isolation isolation = Isolation.serializable,
    bool readOnly = false,
  });
  Future<void> close();
}
