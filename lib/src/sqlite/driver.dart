import '../../driver.dart';
import 'options.dart';
import 'unsupported.dart'
    if (dart.library.io) 'native.dart'
    if (dart.library.js_interop) 'web.dart';

/// Owns one SQLite connection and serializes complete connection leases.
///
/// Native execution runs in an isolate; browser execution runs in a worker.
/// Closing drains accepted leases and then releases the database and worker.
final class SqliteDriver implements Driver<Sqlite> {
  final SqlConnection _connection;
  final Future<void> Function() _shutdown;
  @override
  final Capabilities capabilities;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  SqliteDriver._(this._connection, this.capabilities, this._shutdown);

  /// Opens the configured database and checks SQLite 3.35 or newer.
  ///
  /// Unsupported storage choices and platform capabilities fail before a usable
  /// driver is returned. Inspect [capabilities] for cancellation support.
  static Future<SqliteDriver> open(SqliteOptions options) async {
    final opened = await connectSqlite(options);
    if (opened.version < 3035000) {
      await opened.close();
      throw const OrmException(
        'CAPABILITY.VERSION',
        'SQLite 3.35 or newer is required.',
      );
    }
    return SqliteDriver._(opened.connection, opened.capabilities, opened.close);
  }

  /// Runs [action] exclusively; the next lease starts after its future settles.
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) {
    if (_closed) {
      throw const OrmException('DRIVER.CLOSED', 'SQLite driver is closed.');
    }
    // Queue the whole lease: no caller can enter another caller's transaction.
    final result = _tail.then((_) => action(_connection));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Rejects new leases, drains accepted work, and releases owned resources.
  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _tail.then((_) => _shutdown());
  }
}
