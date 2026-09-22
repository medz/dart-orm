import '../../driver.dart';
import 'query.dart';
import 'relation.dart';
import 'table.dart';

/// Cursor-backed, demand-driven execution of a typed query.
extension QueryStreaming<R, F extends Fields> on Query<R, F> {
  /// One database cursor, fetched on demand. Related rows are loaded per root
  /// batch on the same connection. Pause/await-for consumption provides demand.
  ///
  /// SQL is compiled when this method is called; the single-subscription stream
  /// acquires a connection when listened to. [batchSize] must be positive and
  /// the driver must support streaming. Cancel or finish the subscription before
  /// leaving an explicit session or transaction callback.
  Stream<R> stream({
    int batchSize = 128,
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    final (plan, decode) = planQuery();
    final command = compileQuery(plan);
    return database.streamRows(
      command,
      batchSize: batchSize,
      options: options,
      decode: (connection, batch, execution) async {
        final expanded = await expandRelations(
          database,
          connection,
          plan,
          batch.rows,
          options: execution,
        );
        return database.observeDecode(
          command.sql,
          expanded.length,
          () => [for (final row in expanded) decode(row)],
        );
      },
    );
  }
}
