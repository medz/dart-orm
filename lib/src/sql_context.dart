part of '../sql.dart';

/// Capabilities and an optional execution binding for typed query descriptions.
/// The SQL layer knows no connection pool, platform adapter or runtime session.
abstract class QueryContext {
  const QueryContext();
  Capabilities get capabilities;
  SqlDialect get dialect => capabilities.dialect;
  bool get inTransaction => false;
  bool get inSession => false;

  TableSet<R, F> table<R, F extends Fields>(Table<R, F> definition) =>
      TableSet(this, definition);
  void registerSchema(Iterable<TableSchema> tables) {}

  Never _unbound() => throw const OrmException(
    'QUERY.UNBOUND',
    'This query only describes SQL. Bind it to a Database to execute it.',
  );

  Future<R> run<R>(
    Future<R> Function(SqlConnection) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) => _unbound();
  Future<SqlResult> executeOn(
    SqlConnection connection,
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => _unbound();
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
  }) => _unbound();
  Future<SqlResult> executeCommand(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
    bool affectedOnly = false,
    bool cascade = true,
  }) => _unbound();
  Future<R> atomic<R>(
    Future<R> Function(QueryContext) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) => _unbound();
  Stream<R> streamRows<R>(
    SqlCommand command, {
    required int batchSize,
    required ExecutionOptions options,
    required Future<List<R>> Function(
      SqlConnection,
      List<List<Object?>>,
      ExecutionOptions,
    )
    decode,
  }) => _unbound();
  T observeDecode<T>(String? sql, int inputRows, T Function() action) =>
      action();
  void markFailed() => _unbound();
}

/// Builds and inspects typed SQL without constructing a driver or a database.
final class SqlBuilder extends QueryContext {
  @override
  final Capabilities capabilities;
  const SqlBuilder.withCapabilities(this.capabilities);
  SqlBuilder(SqlDialect dialect)
    : capabilities = Capabilities(
        dialect: dialect,
        maxParameters: dialect == SqlDialect.sqlite ? 999 : 65535,
        returning:
            dialect == SqlDialect.sqlite || dialect == SqlDialect.postgres,
        exactDecimal: true,
        temporal: true,
      );
}
