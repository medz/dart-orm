import 'dart:async';

import '../../sql.dart';
import 'database.dart';
import 'changes.dart';

/// Re-executes a root database query after relevant committed changes.
///
/// {@category Observability}
extension WatchQuery<R, F extends Fields> on Query<R, F> {
  /// Initial snapshot followed by fresh snapshots after relevant committed writes.
  /// Add tables hidden inside raw SQL with [reads]. Read errors are emitted without
  /// closing the stream, allowing a later invalidation to retry the query.
  ///
  /// Watches require a root database outside leased sessions and transactions.
  /// ORM writes report their physical tables automatically; raw or external
  /// writes require explicit invalidation. Cancelling the subscription releases
  /// its listener, and closing the database stops its watches.
  Stream<List<R>> watch({
    Iterable<TableSchema> reads = const [],
    ExecutionOptions options = const ExecutionOptions(),
  }) => _QueryWatch(this, List.unmodifiable(reads), options).controller.stream;
}

final class _QueryWatch<R, F extends Fields> implements ChangeSubscription {
  final Query<R, F> query;
  final List<TableSchema> extraReads;
  final ExecutionOptions options;
  @override
  final Set<String> tables = {};
  late final controller = StreamController<List<R>>(
    onListen: _start,
    onPause: () => _paused = true,
    onResume: () {
      _paused = false;
      _schedule();
    },
    onCancel: stop,
  );
  bool _dirty = true, _paused = false, _scheduled = false, _stopped = false;
  Future<void>? _running, _stopping;
  CancellationToken? _readCancellation;
  void Function()? _removeCancellation;
  _QueryWatch(this.query, this.extraReads, this.options);

  void _start() {
    try {
      final context = query.database;
      if (context is! Database<Backend>) {
        throw const OrmException(
          'QUERY.UNBOUND',
          'Watch requires an ORM Database query.',
        );
      }
      final db = context;
      db.checkActive();
      options.check();
      if (db.inSession) {
        throw const OrmException(
          'WATCH.SESSION',
          'Watch a root database query outside leased sessions and transactions.',
        );
      }
      if (changesFor(db.driver).closed) {
        throw const OrmException('SESSION.CLOSED', 'Database is closed.');
      }
      final reads = query.dependencies;
      if (reads.opaque && extraReads.isEmpty) {
        throw const OrmException(
          'WATCH.READS',
          'Named SQL requires explicit physical tables in watch(reads: ...).',
        );
      }
      for (final table in [...reads.tables, ...extraReads]) {
        tables.add(table.identity);
        changesFor(db.driver).registerTable(table);
      }
      // Subscribe before the initial read so concurrent commits cannot be lost.
      changesFor(db.driver).watches.add(this);
      _removeCancellation = options.cancellation?.listen(() {
        unawaited(
          stop(
            error: const OrmException(
              'OPERATION.CANCELLED',
              'Query watch cancelled.',
            ),
          ),
        );
      });
      _schedule();
    } catch (error, stack) {
      unawaited(stop(error: error, stack: stack));
    }
  }

  @override
  void invalidate() {
    _dirty = true;
    _schedule();
  }

  void _schedule() {
    if (_stopped || _paused || !_dirty || _scheduled || _running != null) {
      return;
    }
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_stopped || _paused || !_dirty) return;
      final work = _pump();
      _running = work;
      unawaited(
        work.whenComplete(() {
          _running = null;
          _schedule();
        }),
      );
    });
  }

  Future<void> _pump() async {
    while (!_stopped && !_paused && _dirty) {
      _dirty = false;
      final cancellation = query.database.capabilities.cancellation
          ? CancellationToken()
          : null;
      _readCancellation = cancellation;
      try {
        final rows = await query.get(
          options: ExecutionOptions(
            timeout: options.timeout,
            acquireTimeout: options.acquireTimeout,
            cancellation: cancellation,
          ),
        );
        if (_paused) _dirty = true;
        if (!_stopped && !_paused && !_dirty) controller.add(rows);
      } catch (error, stack) {
        if (!_stopped) controller.addError(error, stack);
      } finally {
        _readCancellation = null;
      }
    }
  }

  @override
  Future<void> stop({Object? error, StackTrace? stack}) {
    if (_stopping case final stopping?) return stopping;
    final done = Completer<void>();
    _stopping = done.future;
    _stopped = true;
    if (query.database case final Database<Backend> db) {
      changesFor(db.driver).watches.remove(this);
    }
    _removeCancellation?.call();
    _readCancellation?.cancel();
    unawaited(() async {
      await _running;
      if (error != null) controller.addError(error, stack);
      // A paused listener must not hold database shutdown open.
      unawaited(controller.close());
      done.complete();
    }());
    return done.future;
  }
}
