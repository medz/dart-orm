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
      _notify(listener);
    }
    _listeners.clear();
  }

  /// Adapter hook; returns a function that removes the listener.
  /// Listener errors are isolated so every pending operation receives cancellation.
  void Function() listen(void Function() listener) {
    if (_cancelled) {
      _notify(listener);
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify(void Function() listener) {
    try {
      listener();
    } catch (_) {}
  }
}

final class ExecutionOptions {
  final CancellationToken? cancellation;

  /// Time allowed to acquire a lease. Independent of statement [timeout].
  final Duration? acquireTimeout;

  /// Limit for each database statement/fetch, not time spent consuming rows.
  final Duration? timeout;
  const ExecutionOptions({
    this.cancellation,
    this.timeout,
    this.acquireTimeout,
  });
  AcquisitionOptions get _acquisition =>
      acquireTimeout == null && cancellation == null
      ? const AcquisitionOptions()
      : AcquisitionOptions(timeout: acquireTimeout, cancellation: cancellation);
  void check() {
    if (acquireTimeout != null && acquireTimeout! <= Duration.zero) {
      throw ArgumentError.value(acquireTimeout, 'acquireTimeout');
    }
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

/// Limits waiting for a connection, including establishment and initialization.
/// Cancellation after acquisition does not cancel the session callback.
final class AcquisitionOptions {
  final Duration? timeout;
  final CancellationToken? cancellation;
  const AcquisitionOptions({this.timeout, this.cancellation});
  void check() {
    if (timeout != null && timeout! <= Duration.zero) {
      throw ArgumentError.value(timeout, 'acquireTimeout');
    }
    if (cancellation?.isCancelled ?? false) {
      throw const OrmException(
        'OPERATION.CANCELLED',
        'Connection acquisition cancelled.',
      );
    }
  }
}

/// The driver may not expose a cancellable queue. Abandon the request, never
/// enter its SQL callback, and release a late lease normally. The separately
/// tracked drain future keeps Database.close() aware of outstanding resources.
final class _ConnectionWait<R> {
  final Completer<R> _result = Completer();
  Timer? _timer;
  final Stopwatch? _clock;
  final Duration? _timeout;
  final OrmException _timeoutError;
  void Function()? _unsubscribe;
  Future<R> Function(SqlConnection)? _action;
  late final Future<void> drained;
  Future<R> get result => _result.future;

  _ConnectionWait(
    Driver<Backend> driver,
    Future<R> Function(SqlConnection) action,
    AcquisitionOptions options, {
    OrmException? timeoutError,
  }) : _action = action,
       _timeoutError =
           timeoutError ??
           const OrmException(
             'CONNECTION.TIMEOUT',
             'Connection acquisition timed out.',
           ),
       _timeout = options.timeout,
       _clock = options.timeout == null ? null : (Stopwatch()..start()) {
    _unsubscribe = options.cancellation?.listen(
      () => _abandon(
        const OrmException(
          'OPERATION.CANCELLED',
          'Connection acquisition cancelled.',
        ),
      ),
    );
    if (options.timeout case final timeout?) {
      _timer = Timer(timeout, () => _abandon(_timeoutError));
    }
    drained =
        Future.sync(
          () => driver.run<R?>((connection) async {
            final action = _action;
            if (action == null) return null;
            // Timers can run late while the isolate drains queued microtasks.
            if (_clock != null && _clock.elapsed >= _timeout!) {
              _abandon(_timeoutError);
              return null;
            }
            _action = null;
            _dispose();
            return await action(connection);
          }),
        ).then<void>(
          (value) {
            _dispose();
            if (!_result.isCompleted) _result.complete(value as R);
          },
          onError: (Object error, StackTrace stack) {
            _action = null;
            _dispose();
            if (!_result.isCompleted) _result.completeError(error, stack);
          },
        );
  }

  void _abandon(OrmException error) {
    if (_action == null) return;
    _action = null;
    _dispose();
    _result.completeError(error);
  }

  void _dispose() {
    _clock?.stop();
    _timer?.cancel();
    _unsubscribe?.call();
  }
}

abstract interface class SqlCursor {
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  });
  Future<void> close();
}
