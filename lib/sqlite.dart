/// SQLite with background execution on native platforms and the web.
library;

import 'orm.dart';
import 'src/sqlite/options.dart';
import 'src/sqlite/unsupported.dart'
    if (dart.library.io) 'src/sqlite/native.dart'
    if (dart.library.js_interop) 'src/sqlite/web.dart';

export 'orm.dart';
export 'src/sqlite/failure.dart';
export 'src/sqlite/options.dart';

final class SqliteDriver implements Driver<Sqlite> {
  final SqlConnection _connection;
  final Future<void> Function() _shutdown;
  @override
  final Capabilities capabilities;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool _closed = false;
  SqliteDriver._(this._connection, this.capabilities, this._shutdown);

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

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _tail.then((_) => _shutdown());
  }
}

Future<Database<Sqlite>> sqlite(
  SqliteOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
  void Function(DecodeEvent)? onDecode,
}) async => Database(
  await SqliteDriver.open(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
  onDecode: onDecode,
);
