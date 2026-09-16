import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../orm.dart';
import 'failure.dart';
import 'opened.dart';
import 'options.dart';
import 'web_build.dart';
import 'web_wire.dart';

part 'web_client.dart';

Future<OpenedSqlite> connectSqlite(SqliteOptions options) async {
  final config = options.web;
  final memory =
      options.name == null && options.path == ':memory:' && !options.readOnly;
  if (!memory && options.name == null) {
    throw const OrmException(
      'CAPABILITY.STORAGE',
      'Browser SQLite uses persistent(name) or memory(), not native file paths.',
    );
  }
  if (config.openTimeout <= Duration.zero ||
      !RegExp(r'^sha256-[A-Za-z0-9+/]{43}=$').hasMatch(config.wasmIntegrity) ||
      options.name != null &&
          !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(options.name!)) {
    throw ArgumentError('Invalid SQLite browser configuration.');
  }
  final base = Uri.parse(web.document.baseURI);
  final assetBase = base.resolveUri(
    config.assetBase ??
        Uri.parse(
          const bool.fromEnvironment('dart.library.ui')
              ? 'assets/packages/orm/assets/sqlite/'
              : 'orm/',
        ),
  );
  if (!assetBase.path.endsWith('/')) {
    throw ArgumentError(
      'SQLite assetBase must be a directory URI ending in /.',
    );
  }
  final workerUri = config.worker == null
      ? assetBase.resolve(sqliteWorkerFile)
      : base.resolveUri(config.worker!);
  final wasmUri = config.wasm == null
      ? assetBase.resolve(sqliteWasmFile)
      : base.resolveUri(config.wasm!);
  final document = Uri.parse(web.window.location.href);
  if (!{'http', 'https'}.contains(workerUri.scheme) ||
      workerUri.origin != document.origin ||
      !{'http', 'https'}.contains(wasmUri.scheme) ||
      config.worker?.toString() == '' ||
      config.wasm?.toString() == '') {
    throw const OrmException(
      'DRIVER.ASSET',
      'SQLite worker must be same-origin HTTP(S); WASM must have an HTTP(S) URL.',
    );
  }
  final connection = _WebConnection(web.Worker(workerUri.toString().toJS));
  try {
    Future<JSArray<JSAny?>> initialize() async {
      final hello = await connection.request('hello');
      if (hello == null || !hello.isA<JSArray>()) {
        throw const OrmException(
          'DRIVER.PROTOCOL',
          'Invalid SQLite worker handshake.',
        );
      }
      final identity = hello as JSArray<JSAny?>;
      if (identity.length != 2 ||
          !identity[0].equals(sqliteWebProtocol.toJS).toDart ||
          !identity[1].equals(sqliteWorkerBuild.toJS).toDart) {
        throw const OrmException(
          'DRIVER.PROTOCOL',
          'SQLite worker and application builds differ. Deploy matching package assets.',
        );
      }
      return (await connection.request(
            'open',
            [
              wasmUri.toString().toJS,
              (memory ? 'memory' : 'opfs').toJS,
              options.name?.toJS,
              config.wasmIntegrity.toJS,
            ].toJS,
          ))!
          as JSArray<JSAny?>;
    }

    final info = await initialize().timeout(config.openTimeout);
    return (
      connection: connection,
      capabilities: Capabilities(
        dialect: SqlDialect.sqlite,
        maxParameters: (info[1]! as JSNumber).toDartInt,
        streaming: true,
        exactDecimal: true,
        temporal: true,
      ),
      version: (info[0]! as JSNumber).toDartInt,
      close: connection.close,
    );
  } catch (_) {
    await connection.invalidate();
    rethrow;
  }
}
