part of '../sql.dart';

extension QueryStreaming<R, F extends Fields> on Query<R, F> {
  /// One database cursor, fetched on demand. Related rows are loaded per root
  /// batch on the same connection. Pause/await-for consumption provides demand.
  Stream<R> stream({
    int batchSize = 128,
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    final (plan, decode) = _plan();
    final command = _compile(plan);
    return database.streamRows(
      command,
      batchSize: batchSize,
      options: options,
      decode: (connection, rows, execution) async {
        final expanded = await _expandRelations(
          database,
          connection,
          plan,
          rows,
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
