import '../../driver.dart';
import '../../schema_model.dart';
import 'context.dart';
import 'raw_sql.dart';

/// Executes reusable SQL on the current database, session or transaction.
extension SqlExecution on QueryContext {
  /// Executes exactly the supplied statement and returns positional rows,
  /// labels and write metadata. Raw writes declare [changedTables] for watches.
  Future<SqlResult> raw(
    Sql sql, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
  }) => execute(
    sql.compile(capabilities),
    options: options,
    changedTables: changedTables,
  );

  /// Executes once and decodes the actual metadata and rows. No wrapper or LIMIT
  /// is added. Use this for SELECT or native DML RETURNING.
  ///
  /// Decode/mapper failures poison an explicit transaction even if caught.
  /// Outside a transaction, a write may already have committed before decoding
  /// fails; the ORM never automatically retries it.
  Future<List<R>> query<R>(
    SqlQuery<R> query, {
    ExecutionOptions options = const ExecutionOptions(),
    Iterable<TableSchema> changedTables = const [],
  }) async {
    final command = query.sql.compile(capabilities);
    final result = await execute(
      command,
      options: options,
      changedTables: changedTables,
    );
    try {
      return observeDecode<List<R>>(command.sql, result.rows.length, () {
        final decode = query.result.bind(result.columns);
        return [for (final row in result.rows) decode(row)];
      });
    } catch (_) {
      if (inTransaction) markFailed();
      rethrow;
    }
  }

  /// Streams typed rows through one cursor with bounded batch fetching.
  /// Compilation is immediate; a connection is acquired on listen. Result
  /// labels are bound on the first batch, even when empty, without a second query.
  /// Cancel or finish before leaving a session/transaction callback.
  Stream<R> streamSql<R>(
    SqlQuery<R> query, {
    int batchSize = 128,
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    final command = query.sql.compile(capabilities);
    R Function(List<Object?>)? decode;
    return streamRows(
      command,
      batchSize: batchSize,
      options: options,
      decode: (_, batch, _) async {
        try {
          return observeDecode<List<R>>(command.sql, batch.rows.length, () {
            decode ??= query.result.bind(batch.columns);
            return [for (final row in batch.rows) decode!(row)];
          });
        } catch (_) {
          if (inTransaction) markFailed();
          rethrow;
        }
      },
    );
  }
}
