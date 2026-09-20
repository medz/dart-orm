import 'package:meta/meta.dart' show internal;

/// Synchronous ORM decoding/mapping and associated row grouping. Excludes SQL,
/// acquisition, compilation, waiting for the consumer and other client work.
///
/// {@category Observability}
final class DecodeEvent {
  /// Null for a batch RETURNING result assembled from multiple commands.
  final String? sql;

  /// Number of raw rows passed into the measured decoding operation.
  final int inputRows;

  /// Synchronous decode, mapping, and grouping time.
  final Duration elapsed;

  /// Decoder or mapper failure, or null when decoding completed.
  final Object? error;

  /// Captures decode cost without retaining decoded rows or bound parameters.
  const DecodeEvent({
    required this.sql,
    required this.inputRows,
    required this.elapsed,
    this.error,
  });
}

/// @nodoc
@internal
T observeDecode<T>(
  void Function(DecodeEvent)? observer,
  String? sql,
  int inputRows,
  T Function() action,
) {
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
