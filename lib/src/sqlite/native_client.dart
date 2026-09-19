part of 'native.dart';

// Resolve against the exact native asset used by package:sqlite3. Never call
// an unrelated system SQLite library with this library's database pointer.
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Void>)>(
  symbol: 'sqlite3_interrupt',
  assetId: 'package:sqlite3/src/ffi/libsqlite3.g.dart',
)
external void _sqliteInterrupt(ffi.Pointer<ffi.Void> db);

final class _OpenCursor(final SqlCommand command) {}

final class _FetchCursor(final int cursor, final int count) {}

final class _CloseCursor(final int cursor) {}

final class _SqliteWorker implements SqlConnection {
  final ReceivePort _responses = ReceivePort();
  final Completer<(SendPort, int, int)> _ready = Completer();
  final Map<int, Completer<SqlResult>> _pending = {};
  late SendPort port;
  Isolate? _isolate;
  var _id = 0, _handle = 0;
  bool _stopped = false, _busy = false;
  bool _transactionActive = false;
  @override
  bool? get transactionActive => _stopped || _busy ? null : _transactionActive;
  late final bool supportsCancellation = _resolveInterrupt();
  bool _resolveInterrupt() {
    try {
      return ffi.Native.addressOf<
                ffi.NativeFunction<ffi.Void Function(ffi.Pointer<ffi.Void>)>
              >(_sqliteInterrupt)
              .address !=
          0;
    } catch (_) {
      return false;
    }
  }

  void _fail(Object error) {
    _handle = 0;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      pending.completeError(error);
    }
    _pending.clear();
  }

  Future<(SendPort, int, int)> open(SqliteOptions options) async {
    _responses.listen((Object? message) {
      if (message case [
        0,
        SendPort port,
        int maxParameters,
        int version,
        int handle,
      ]) {
        _handle = handle;
        _ready.complete((port, maxParameters, version));
      } else if (message case [-1, Object error, SendPort acknowledge]) {
        // The worker keeps its native connection alive until this acknowledgement.
        _fail(error);
        _stopped = true;
        acknowledge.send(null);
        _responses.close();
      } else if (message case [int id, SqlResult result, bool active]) {
        _transactionActive = active;
        _pending.remove(id)?.complete(result);
      } else if (message case [int id, Object error, bool active]) {
        _transactionActive = active;
        _pending.remove(id)?.completeError(error);
      } else if (message case [int id, Object error]) {
        if (id == 0) {
          _fail(error);
        } else {
          _pending.remove(id)?.completeError(error);
        }
      } else {
        _fail(
          const OrmException(
            'DRIVER.WORKER',
            'SQLite worker exited unexpectedly.',
          ),
        );
      }
    });
    try {
      _isolate = await Isolate.spawn(
        _sqliteMain,
        (_responses.sendPort, options),
        onError: _responses.sendPort,
        onExit: _responses.sendPort,
      );
      return await _ready.future;
    } catch (_) {
      _responses.close();
      _isolate?.kill();
      rethrow;
    }
  }

  Future<SqlResult> _request(Object? command) {
    final id = ++_id, result = Completer<SqlResult>();
    _pending[id] = result;
    port.send((id, command));
    return result.future;
  }

  Future<SqlResult> _operate(Object command, ExecutionOptions options) async {
    options.check();
    if (_stopped) {
      throw const OrmException('DRIVER.CLOSED', 'SQLite worker is closed.');
    }
    if (_busy) {
      throw const OrmException(
        'SESSION.BUSY',
        'Await the active statement before using this connection again.',
      );
    }
    if ((options.cancellation != null || options.timeout != null) &&
        !supportsCancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This SQLite build does not export its interrupt API.',
      );
    }
    _busy = true;
    Timer? deadline, repeat;
    var timedOut = false;
    void interrupt() {
      if (_handle != 0 && !_stopped) {
        _sqliteInterrupt(ffi.Pointer.fromAddress(_handle));
      }
    }

    void cancel() {
      interrupt();
      // An interrupt just before sqlite3_step is a no-op. Repeat until the one
      // active request finishes, without permitting another request to start.
      repeat ??= Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => interrupt(),
      );
    }

    final unsubscribe = options.cancellation?.listen(cancel);
    if (options.timeout != null) {
      deadline = Timer(options.timeout!, () {
        timedOut = true;
        cancel();
      });
    }
    try {
      return await _request(command);
    } on SqliteFailure catch (error) {
      if (error.code == 9) {
        throw OrmException(
          timedOut ? 'OPERATION.TIMEOUT' : 'OPERATION.CANCELLED',
          'SQLite stopped the statement.',
          cause: error,
        );
      }
      rethrow;
    } finally {
      deadline?.cancel();
      repeat?.cancel();
      unsubscribe?.call();
      _busy = false;
    }
  }

  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => _operate(command, options);
  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final result = await _operate(_OpenCursor(command), options);
    return _SqliteCursor(this, result.rows.single.single as int);
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _handle = 0;
    try {
      await _request(null);
    } finally {
      _responses.close();
      _isolate?.kill();
    }
  }

  @override
  Future<void> invalidate() => stop();
}

final class _SqliteCursor(final _SqliteWorker worker, final int id)
    implements SqlCursor {
  bool _closed = false;
  @override
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    if (_closed) throw const OrmException('CURSOR.CLOSED', 'Cursor has ended.');
    if (count < 1) throw ArgumentError.value(count, 'count');
    return worker._operate(_FetchCursor(id, count), options);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await worker._operate(_CloseCursor(id), const ExecutionOptions());
  }
}
