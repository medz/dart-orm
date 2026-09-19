part of 'web.dart';

final class _WebConnection implements SqlConnection {
  final web.Worker worker;
  final Map<int, Completer<JSAny?>> _pending = {};
  int _serial = 0;
  bool _closed = false, _busy = false;
  bool? _active = false;
  _WebConnection(this.worker) {
    worker.onmessage = ((web.MessageEvent event) {
      try {
        final message = event.data! as JSArray<JSAny?>;
        final id = (message[0]! as JSNumber).toDartInt;
        final response = _pending[id];
        if (response == null) return;
        _active = (message[2] as JSBoolean?)?.toDart;
        if ((message[1]! as JSBoolean).toDart) {
          _pending.remove(id);
          response.complete(message[3]);
        } else {
          final error = message[3]! as JSArray<JSAny?>;
          final code = (error[0]! as JSString).toDart;
          final description = (error[1]! as JSString).toDart;
          final failure = code == 'sqlite'
              ? SqliteFailure(
                  (error[2]! as JSNumber).toDartInt,
                  (error[3]! as JSNumber).toDartInt,
                  description,
                )
              : OrmException(code, description);
          _pending.remove(id);
          response.completeError(failure);
        }
      } catch (error) {
        _fail(error);
      }
    }).toJS;
    worker.onerror = ((web.Event event) {
      _fail(
        const OrmException(
          'DRIVER.WORKER',
          'SQLite web worker failed to load or exited with an error.',
        ),
      );
    }).toJS;
    worker.onmessageerror = ((web.MessageEvent event) {
      _fail(
        const OrmException(
          'DRIVER.PROTOCOL',
          'SQLite worker message could not be cloned.',
        ),
      );
    }).toJS;
  }

  @override
  bool? get transactionActive => _closed || _busy ? null : _active;

  void _fail(Object error) {
    if (_closed) return;
    _closed = true;
    _active = null;
    worker.terminate();
    for (final response in _pending.values) {
      response.completeError(error);
    }
    _pending.clear();
  }

  Future<JSAny?> request(String operation, [JSAny? payload]) {
    if (_closed) {
      throw const OrmException('DRIVER.CLOSED', 'SQLite web worker is closed.');
    }
    final id = ++_serial, response = Completer<JSAny?>();
    _pending[id] = response;
    try {
      worker.postMessage([id.toJS, operation.toJS, payload].toJS);
    } catch (error, stack) {
      _pending.remove(id);
      response.completeError(error, stack);
    }
    return response.future;
  }

  Future<JSAny?> _operate(
    String operation,
    JSAny? payload,
    ExecutionOptions options,
  ) async {
    options.check();
    if (options.timeout != null || options.cancellation != null) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This WASM worker cannot interrupt a running SQLite statement.',
      );
    }
    if (_busy) {
      throw const OrmException(
        'SESSION.BUSY',
        'Await the active SQLite request.',
      );
    }
    _busy = true;
    try {
      return await request(operation, payload);
    } finally {
      _busy = false;
    }
  }

  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async => sqliteWebDartResult(
    await _operate('execute', sqliteWebCommand(command), options),
  );

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final id = await _operate('cursor', sqliteWebCommand(command), options);
    return _WebCursor(this, (id! as JSNumber).toDartInt);
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      await request('close');
    } finally {
      await invalidate();
    }
  }

  @override
  Future<void> invalidate() async => _fail(
    const OrmException('DRIVER.CLOSED', 'SQLite web worker was discarded.'),
  );
}

final class _WebCursor(final _WebConnection connection, final int id)
    implements SqlCursor {
  bool _closed = false;
  @override
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    if (_closed) throw const OrmException('CURSOR.CLOSED', 'Cursor has ended.');
    if (count < 1) throw ArgumentError.value(count, 'count');
    return sqliteWebDartResult(
      await connection._operate('fetch', [id.toJS, count.toJS].toJS, options),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await connection._operate('release', id.toJS, const ExecutionOptions());
  }
}
