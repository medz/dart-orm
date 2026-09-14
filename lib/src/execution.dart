part of '../orm.dart';

/// A cancellation request. Await the operation itself to observe its actual
/// database outcome; completion can win a race with cancellation.
final class CancellationToken {
  bool _cancelled = false;
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled;
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  /// Adapter hook; returns a function that removes the listener.
  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

final class ExecutionOptions {
  final CancellationToken? cancellation;

  /// Limit for each database statement/fetch, not time spent consuming rows.
  final Duration? timeout;
  const ExecutionOptions({this.cancellation, this.timeout});
  void check() {
    if (timeout != null && timeout! <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const OrmException(
        'OPERATION.CANCELLED',
        'Cancelled before starting a database operation.',
      );
    }
  }
}

abstract interface class SqlCursor {
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  });
  Future<void> close();
}
