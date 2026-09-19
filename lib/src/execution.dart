part of '../runtime.dart';

/// The driver may not expose a cancellable queue. Abandon the request, never
/// enter its SQL callback, and release a late lease normally. The separately
/// tracked drain future keeps SqlDatabase.close() aware of outstanding resources.
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
