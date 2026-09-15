part of '../orm.dart';

final _changeHubs = Expando<_ChangeHub>();

void _mergeChanges(Map<String, bool> target, Map<String, bool> source) {
  for (final entry in source.entries) {
    target[entry.key] = (target[entry.key] ?? false) || entry.value;
  }
}

/// Shared by views of the same driver, without global result caching.
final class _ChangeHub {
  final _schemas = Expando<bool>();
  final Map<String, TableSchema> _tables = {};
  final Map<String, Map<String, bool>> _deleteEffects = {};
  final Set<_QueryWatch<Object?, Fields>> watches = {};
  bool closed = false;

  void register(Iterable<TableSchema> schema) {
    if (!closed && _schemas[schema] != true) {
      _schemas[schema] = true;
      for (final table in schema) {
        registerTable(table);
      }
    }
  }

  void registerTable(TableSchema table) {
    if (closed || identical(_tables[table.name], table)) return;
    final previous = _tables[table.name];
    if (previous != null) {
      for (final fk in previous.foreignKeys) {
        final effects = _deleteEffects[fk.target];
        effects?.remove(table.name);
        if (effects?.isEmpty ?? false) _deleteEffects.remove(fk.target);
      }
    }
    _tables[table.name] = table;
    for (final fk in table.foreignKeys) {
      if (!{'CASCADE', 'SET NULL', 'SET DEFAULT'}.contains(fk.onDelete)) {
        continue;
      }
      final effects = _deleteEffects.putIfAbsent(fk.target, () => {});
      effects[table.name] =
          (effects[table.name] ?? false) || fk.onDelete == 'CASCADE';
    }
  }

  void publish(Map<String, bool> changes) {
    if (closed || changes.isEmpty || watches.isEmpty) return;
    final affected = changes.keys.toSet();
    final deletes = [
      for (final e in changes.entries)
        if (e.value) e.key,
    ];
    final visited = <String>{};
    while (deletes.isNotEmpty) {
      final table = deletes.removeLast();
      if (!visited.add(table)) continue;
      for (final effect
          in (_deleteEffects[table] ?? const <String, bool>{}).entries) {
        affected.add(effect.key);
        if (effect.value) deletes.add(effect.key);
      }
    }
    for (final watch in watches.toList()) {
      if (watch.tables.any(affected.contains)) watch.invalidate();
    }
  }

  Future<void> stop() async {
    closed = true;
    await Future.wait(watches.toList().map((watch) => watch.stop()));
    _tables.clear();
    _deleteEffects.clear();
  }
}

/// SQL compilation visits subqueries and CTE definitions with the same writer.
/// Batch relationships are additional queries and must be visited separately.
final class _ReadTables {
  final Set<TableSchema> tables = Set.identity();
  void query(Query<Object?, Fields> query) {
    final (plan, _) = query._plan();
    query._write(
      _Writer(
        query.database.dialect,
        {},
        reads: this,
        exactDecimal: query.database.capabilities.exactDecimal,
        temporal: query.database.capabilities.temporal,
      ),
      plan,
    );
    for (final binding in plan.relations) {
      binding.collectReads(query.database, this);
    }
  }
}

extension WatchQuery<R, F extends Fields> on Query<R, F> {
  /// Initial snapshot followed by fresh snapshots after relevant committed writes.
  /// Add tables hidden inside raw SQL with [reads]. Read errors are emitted without
  /// closing the stream, allowing a later invalidation to retry the query.
  Stream<List<R>> watch({
    Iterable<TableSchema> reads = const [],
    ExecutionOptions options = const ExecutionOptions(),
  }) => _QueryWatch(this, List.unmodifiable(reads), options).controller.stream;
}

final class _QueryWatch<R, F extends Fields> {
  final Query<R, F> query;
  final List<TableSchema> extraReads;
  final ExecutionOptions options;
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
      final db = query.database;
      db._checkActive();
      options.check();
      if (db.inSession) {
        throw const OrmException(
          'WATCH.SESSION',
          'Watch a root database query outside leased sessions and transactions.',
        );
      }
      if (db._changes.closed) {
        throw const OrmException('SESSION.CLOSED', 'Database is closed.');
      }
      final reads = _ReadTables()..query(query);
      for (final table in [...reads.tables, ...extraReads]) {
        tables.add(table.name);
        db._changes.registerTable(table);
      }
      // Subscribe before the initial read so concurrent commits cannot be lost.
      db._changes.watches.add(this);
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

  Future<void> stop({Object? error, StackTrace? stack}) {
    if (_stopping case final stopping?) return stopping;
    final done = Completer<void>();
    _stopping = done.future;
    _stopped = true;
    query.database._changes.watches.remove(this);
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
