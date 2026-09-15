/// SQLite WASM in a dedicated browser worker, with explicit memory/OPFS storage.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'orm.dart';
import 'src/sqlite/failure.dart';
import 'src/sqlite/web_wire.dart';
export 'orm.dart';
export 'src/sqlite/failure.dart';

part 'src/sqlite/web_client.dart';

enum SqliteWebStorage { memory, opfs }

final class SqliteWebOptions {
  final Uri wasm;
  final Uri worker;
  final SqliteWebStorage storage;
  final String? name;
  final Duration openTimeout;
  const SqliteWebOptions.memory({
    required this.wasm,
    required this.worker,
    this.openTimeout = const Duration(seconds: 15),
  }) : storage = SqliteWebStorage.memory,
       name = null;
  const SqliteWebOptions.opfs({
    required String this.name,
    required this.wasm,
    required this.worker,
    this.openTimeout = const Duration(seconds: 15),
  }) : storage = SqliteWebStorage.opfs;
}

final class SqliteWebDriver implements Driver<Sqlite> {
  final _WebConnection _connection;
  @override
  final Capabilities capabilities;
  Future<void> _tail = Future.value();
  bool _closed = false;
  SqliteWebDriver._(this._connection, this.capabilities);

  static Future<SqliteWebDriver> open(SqliteWebOptions options) async {
    if (options.openTimeout <= Duration.zero ||
        options.wasm.toString().isEmpty ||
        options.worker.toString().isEmpty ||
        options.storage == SqliteWebStorage.opfs &&
            (options.name == null ||
                !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$')
                    .hasMatch(options.name!))) {
      throw ArgumentError('Invalid SQLite web options.');
    }
    final connection = _WebConnection(
      web.Worker(options.worker.toString().toJS),
    );
    try {
      final response = await connection
          .request(
            'open',
            [
              Uri.base.resolveUri(options.wasm).toString().toJS,
              options.storage.name.toJS,
              options.name?.toJS,
            ].toJS,
          )
          .timeout(options.openTimeout);
      final info = response! as JSArray<JSAny?>;
      final version = (info[0]! as JSNumber).toDartInt;
      if (version < 3035000) {
        throw const OrmException(
          'CAPABILITY.VERSION',
          'SQLite 3.35 or newer is required.',
        );
      }
      return SqliteWebDriver._(
        connection,
        Capabilities(
          dialect: SqlDialect.sqlite,
          maxParameters: (info[1]! as JSNumber).toDartInt,
          streaming: true,
          exactDecimal: true,
          temporal: true,
        ),
      );
    } catch (_) {
      await connection.invalidate();
      rethrow;
    }
  }

  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) {
    if (_closed) {
      throw const OrmException('DRIVER.CLOSED', 'SQLite web driver is closed.');
    }
    final result = _tail.then((_) => action(_connection));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _tail;
    await _connection.close();
  }
}

Future<Database<Sqlite>> sqliteWeb(
  SqliteWebOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
  void Function(DecodeEvent)? onDecode,
}) async => Database(
  await SqliteWebDriver.open(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
  onDecode: onDecode,
);
