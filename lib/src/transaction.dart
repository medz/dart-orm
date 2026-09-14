part of '../orm.dart';

/// Adapter classification. Retrying also requires a confirmed rollback and an
/// explicitly repeatable application callback; these flags alone are not enough.
abstract interface class SqlFailure implements Exception {
  bool get retryTransaction;

  /// Retry the same COMMIT only while the adapter confirms the transaction is active.
  bool get retryCommit;
  bool get commitRejected;
}

/// Explicit opt-in: callback logic must be safe to repeat after rollback.
/// The budget counts every scheduled retry, including commit-only retries.
final class TransactionRetry {
  /// Initial attempt plus callback replays and COMMIT-only retries combined.
  final int maxAttempts;

  /// Total budget including connection acquisition, callbacks, SQL and backoff.
  final Duration timeout;

  /// Initial backoff, randomized between approximately half and all this delay.
  final Duration delay;

  /// Upper bound as the backoff doubles after each retry.
  final Duration maxDelay;
  const TransactionRetry({
    this.maxAttempts = 3,
    this.timeout = const Duration(seconds: 30),
    this.delay = const Duration(milliseconds: 10),
    this.maxDelay = const Duration(milliseconds: 250),
  });
  void _check() {
    if (maxAttempts < 1 ||
        timeout <= Duration.zero ||
        delay.isNegative ||
        maxDelay < delay) {
      throw ArgumentError(
        'Retry attempts/time must be positive; delay must be nonnegative and no greater than maxDelay.',
      );
    }
  }
}

// Created only after the attempt has confirmed rollback; never for acquisition,
// uncertain COMMIT, failed cleanup or an application-caught statement failure.
final class _RetryAfterRollback(final SqlFailure error, final StackTrace stack)
    implements Exception {}

final class _RetryBudget {
  final TransactionRetry policy;
  final Stopwatch _clock = Stopwatch()..start();
  final math.Random _random = math.Random();
  int _attempts = 1;
  int _delay;
  _RetryBudget(this.policy) : _delay = policy.delay.inMicroseconds;
  Duration get remaining => policy.timeout - _clock.elapsed;
  Duration limit(Duration? other) {
    final left = remaining;
    if (left <= Duration.zero) {
      throw const OrmException(
        'TRANSACTION.TIMEOUT',
        'Transaction retry time budget expired.',
      );
    }
    return other == null || left < other ? left : other;
  }

  Future<bool> next(_TransactionControl control) async {
    control.check();
    limit(null);
    if (_attempts >= policy.maxAttempts) return false;
    _attempts++;
    // Equal jitter without multiplying a potentially large Duration by a double.
    final wait = _delay ~/ 2 + (_delay ~/ 2000) * _random.nextInt(1001);
    final max = policy.maxDelay.inMicroseconds;
    _delay = _delay >= max ~/ 2 ? max : _delay * 2;
    await control.pause(Duration(microseconds: wait));
    control.check();
    limit(null);
    return true;
  }
}

final class _CancellationLink {
  final token = CancellationToken();
  final List<void Function()> _remove = [];
  _CancellationLink(Iterable<CancellationToken> sources) {
    for (final source in sources) {
      _remove.add(source.listen(token.cancel));
    }
  }
  void dispose() {
    for (final remove in _remove) {
      remove();
    }
  }
}

final class _TransactionControl {
  final CancellationToken token = CancellationToken();
  final Duration? timeout;
  final Stopwatch _clock = Stopwatch()..start();
  final Completer<Never> _expired = Completer();
  Timer? _timer;
  void Function()? _unsubscribe;
  OrmException? failure;

  _TransactionControl(this.timeout, CancellationToken? cancellation) {
    _expired.future.ignore();
    _unsubscribe = cancellation?.listen(() => _expire(false));
    if (timeout != null) _timer = Timer(timeout!, () => _expire(true));
  }
  void _expire(bool timedOut) {
    if (failure != null) return;
    failure = OrmException(
      timedOut ? 'TRANSACTION.TIMEOUT' : 'TRANSACTION.CANCELLED',
      timedOut ? 'Transaction deadline expired.' : 'Transaction cancelled.',
    );
    token.cancel();
    _expired.completeError(failure!);
  }

  void check() {
    if (timeout != null && _clock.elapsed >= timeout!) _expire(true);
    if (failure != null) throw failure!;
  }

  Future<R> race<R>(Future<R> Function() action) {
    check();
    return Future.any([Future.sync(action), _expired.future]);
  }

  Future<R> execute<R>(
    Future<R> Function(ExecutionOptions) action,
    ExecutionOptions options,
  ) async {
    check();
    options.check();
    final link =
        options.cancellation == null || identical(options.cancellation, token)
        ? null
        : _CancellationLink([token, options.cancellation!]);
    try {
      return await action(
        ExecutionOptions(
          timeout: options.timeout,
          cancellation: link?.token ?? token,
        ),
      );
    } finally {
      link?.dispose();
    }
  }

  Future<void> pause(Duration delay) async {
    check();
    if (delay == Duration.zero) return;
    final done = Completer<void>();
    final timer = Timer(delay, done.complete);
    final remove = token.listen(() {
      if (!done.isCompleted) {
        done.completeError(
          failure ??
              const OrmException(
                'TRANSACTION.CANCELLED',
                'Transaction cancelled.',
              ),
        );
      }
    });
    try {
      await done.future;
    } finally {
      timer.cancel();
      remove();
    }
    check();
  }

  void dispose() {
    _clock.stop();
    _timer?.cancel();
    _unsubscribe?.call();
  }
}

final class _TransactionConnection(
  final SqlConnection inner,
  final _TransactionControl control,
) implements SqlConnection {
  @override
  bool? get transactionActive => inner.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => control.execute((o) => inner.execute(command, options: o), options);
  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async => _TransactionCursor(
    await control.execute(
      (o) => inner.openCursor(command, options: o),
      options,
    ),
    control,
  );
  @override
  Future<void> invalidate() => inner.invalidate();
}

final class _TransactionCursor(
  final SqlCursor inner,
  final _TransactionControl control,
) implements SqlCursor {
  @override
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => control.execute((o) => inner.fetch(count, options: o), options);
  // Cleanup must still run after the deadline/cancellation token expires.
  @override
  Future<void> close() => inner.close();
}

SqlConnection _unscoped(SqlConnection connection) =>
    connection is _TransactionConnection ? connection.inner : connection;
