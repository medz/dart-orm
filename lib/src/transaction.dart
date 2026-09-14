part of '../orm.dart';

/// Adapter classification. Retrying also requires a confirmed rollback and an
/// explicitly repeatable application callback; these flags alone are not enough.
abstract interface class SqlFailure implements Exception {
  bool get retryTransaction;
  bool get commitRejected;
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
