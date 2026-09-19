part of '../orm.dart';

/// Synchronous ORM decoding/mapping and associated row grouping. Excludes SQL,
/// acquisition, compilation, waiting for the consumer and other client work.
final class DecodeEvent {
  /// Null for a batch RETURNING result assembled from multiple commands.
  final String? sql;
  final int inputRows;
  final Duration elapsed;
  final Object? error;
  const DecodeEvent({
    required this.sql,
    required this.inputRows,
    required this.elapsed,
    this.error,
  });
}

extension _DatabaseObservation on Database<Backend> {
  T _observeDecode<T>(String? sql, int inputRows, T Function() action) {
    final observer = onDecode;
    if (observer == null) return action();
    final clock = Stopwatch()..start();
    Object? error;
    try {
      return action();
    } catch (e) {
      error = e;
      rethrow;
    } finally {
      clock.stop();
      try {
        observer(
          DecodeEvent(
            sql: sql,
            inputRows: inputRows,
            elapsed: clock.elapsed,
            error: error,
          ),
        );
      } catch (_) {} // Observers cannot change a result or its failure.
    }
  }
}
