import '../driver/driver.dart';
import '../runtime/database.dart';
import 'raw_sql.dart';

/// Parameterized SQL on the owning runtime or its borrowed session.
///
/// No models, schema registration, or generator are required. The same runtime
/// can subsequently be passed to an ORM view without acquiring another pool.
extension RuntimeSqlExecution on SqlDatabase<Backend> {
  /// Executes one statement. Values are bound by [Sql.compile].
  ///
  /// [changedTables] uses schema-qualified table identities for watch
  /// invalidation. SQL text is never parsed to discover write targets.
  Future<SqlResult> raw(
    Sql sql, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<String> changedTables = const [],
  }) async => execute(
    sql.compile(capabilities),
    options: options,
    changedTables: changedTables,
  );

  /// Executes and decodes one statement using its actual result labels.
  ///
  /// A decode failure poisons the current transaction even if caught. Outside
  /// a transaction a write may already be committed; decoding is never retried.
  Future<List<R>> query<R>(
    SqlQuery<R> query, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<String> changedTables = const [],
  }) async {
    final result = await execute(
      query.sql.compile(capabilities),
      options: options,
      changedTables: changedTables,
    );
    return _guardSqlResult(this, () {
      final decode = query.result.bind(result.columns);
      return [for (final row in result.rows) decode(row)];
    });
  }

  /// Streams typed rows through the runtime's bounded cursor.
  ///
  /// Finish or cancel before the borrowed session callback returns. Metadata
  /// is checked even for an empty result and decoder failures poison the active
  /// transaction through the same result guard as ordinary queries.
  Stream<R> streamSql<R>(
    SqlQuery<R> query, {
    int batchSize = 128,
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    final command = query.sql.compile(capabilities);
    R Function(List<Object?>)? decode;
    return streamRows(
      command,
      batchSize: batchSize,
      options: options,
      decode: (_, batch, _) async => _guardSqlResult(this, () {
        decode ??= query.result.bind(batch.columns);
        return [for (final row in batch.rows) decode!(row)];
      }),
    );
  }
}

// Preserve the existing typed raw-SQL decode contract. Ordinary Query mapping
// and cardinality checks do not use this guard.
T _guardSqlResult<T>(SqlDatabase<Backend> database, T Function() action) {
  try {
    return action();
  } catch (_) {
    if (database.inTransaction) database.markFailed();
    rethrow;
  }
}
