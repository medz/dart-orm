import 'package:meta/meta.dart';

import '../../driver.dart';
import '../../schema_model.dart';
import 'query.dart';
import 'table.dart';

/// Capabilities and an optional execution binding for typed query descriptions.
/// The SQL layer knows no connection pool, platform adapter or runtime session.
abstract class QueryContext {
  /// Creates a context for compiling or executing query descriptions.
  const QueryContext();

  /// The selected engine's limits and supported SQL features.
  Capabilities get capabilities;

  /// The SQL dialect selected by the context's capabilities.
  SqlDialect get dialect => capabilities.dialect;

  /// Whether this view borrows an active transaction.
  bool get inTransaction => false;

  /// Whether this view borrows one leased connection.
  bool get inSession => false;

  /// Binds a manual or generated table definition to this context.
  TableSet<R, F> table<R, F extends Fields>(Table<R, F> definition) =>
      TableSet(this, definition);

  /// Registers foreign-key effects for change subscriptions.
  ///
  /// Generated table getters call this hook. Compilation-only contexts need no
  /// subscription state, so the default implementation does nothing.
  void registerSchema(Iterable<TableSchema> tables) {}

  Never _unbound() => throw const OrmException(
    'QUERY.UNBOUND',
    'This query only describes SQL. Bind it to a Database to execute it.',
  );

  /// Executes work on a leased connection, or rejects an unbound context.
  Future<R> run<R>(
    Future<R> Function(SqlConnection) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) => _unbound();

  /// @nodoc
  @internal
  Future<SqlResult> executeOn(
    SqlConnection connection,
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => _unbound();

  /// Executes bound SQL and declares tables affected by raw writes.
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
  }) => _unbound();

  /// @nodoc
  @internal
  Future<SqlResult> executeCommand(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
    bool affectedOnly = false,
    bool cascade = true,
  }) => _unbound();

  /// @nodoc
  @internal
  Future<R> atomic<R>(
    Future<R> Function(QueryContext) action, {
    AcquisitionOptions acquire = const AcquisitionOptions(),
  }) => _unbound();

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
  }) => _unbound();

  /// @nodoc
  @internal
  T observeDecode<T>(String? sql, int inputRows, T Function() action) =>
      action();

  /// @nodoc
  @internal
  void markFailed() => _unbound();
}

/// Builds and inspects typed SQL without constructing a driver or a database.
final class SqlBuilder extends QueryContext {
  @override
  final Capabilities capabilities;

  /// Builds SQL using an explicitly supplied engine capability profile.
  const SqlBuilder.withCapabilities(this.capabilities);

  /// Builds SQL using the dialect's offline defaults.
  ///
  /// Use withCapabilities when an adapter exposes stricter live limits.
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
