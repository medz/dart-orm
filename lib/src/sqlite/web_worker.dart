import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:web/web.dart' as web;

import '../../driver.dart';
import 'execution.dart';
import 'web_build.dart';
import 'web_wire.dart';

/// Serves SQLite requests inside a dedicated Web worker.
///
/// Call once from a custom worker entrypoint. Normal applications use the
/// verified worker bundled by the package instead of starting this directly.
void runSqliteWebWorker() {
  final self = globalContext as web.DedicatedWorkerGlobalScope;
  final server = _WorkerDatabase();
  Future<void> tail = Future.value();
  self.onmessage = ((web.MessageEvent event) {
    tail = tail.then((_) async {
      final message = event.data! as JSArray<JSAny?>;
      final id = message[0];
      try {
        final result = await server.handle(
          (message[1]! as JSString).toDart,
          message[2],
        );
        self.postMessage([id, true.toJS, server.active?.toJS, result].toJS);
      } catch (error) {
        final JSArray<JSAny?> details;
        if (error is sqlite.SqliteException) {
          details = [
            'sqlite'.toJS,
            error.message.toJS,
            error.resultCode.toJS,
            error.extendedResultCode.toJS,
          ].toJS;
        } else {
          details = [
            (error is OrmException ? error.code : 'DRIVER.SQLITE').toJS,
            error.toString().toJS,
          ].toJS;
        }
        self.postMessage([id, false.toJS, server.active?.toJS, details].toJS);
      }
    });
  }).toJS;
}

final class _WorkerDatabase {
  sqlite.WasmSqlite3? engine;
  sqlite.CommonDatabase? db;
  sqlite.SimpleOpfsFileSystem? opfs;
  sqlite.InMemoryFileSystem? memory;
  SqliteExecutor? executor;
  bool? get active => db == null ? null : !db!.autocommit;

  Future<JSAny?> handle(String operation, JSAny? payload) async {
    if (operation == 'hello') {
      return [sqliteWebProtocol.toJS, sqliteWorkerBuild.toJS].toJS;
    }
    if (operation == 'open') {
      if (engine != null) {
        throw const OrmException('DRIVER.OPEN', 'Worker is already open.');
      }
      final options = payload! as JSArray<JSAny?>;
      final wasm = (options[0]! as JSString).toDart;
      final storage = (options[1]! as JSString).toDart;
      try {
        final web.Response response;
        try {
          response = await (globalContext as web.DedicatedWorkerGlobalScope)
              .fetch(
                wasm.toJS,
                web.RequestInit(integrity: (options[3]! as JSString).toDart),
              )
              .toDart;
          if (!response.ok) throw StateError('HTTP ${response.status}');
        } catch (e) {
          throw OrmException(
            'DRIVER.ASSET',
            'SQLite WASM fetch or integrity check failed.',
            cause: e,
          );
        }
        final bytes = (await response.arrayBuffer().toDart).toDart;
        final sqlite3 = engine = await sqlite.WasmSqlite3.load(
          Uint8List.view(bytes),
        );
        if (storage == 'opfs') {
          opfs = await sqlite.SimpleOpfsFileSystem.loadFromStorage(
            'dart-orm/${(options[2]! as JSString).toDart}',
          );
          sqlite3.registerVirtualFileSystem(opfs!, makeDefault: true);
        } else if (storage == 'memory') {
          memory = sqlite.InMemoryFileSystem();
          sqlite3.registerVirtualFileSystem(memory!, makeDefault: true);
        } else {
          throw const OrmException(
            'DRIVER.STORAGE',
            'Unknown browser storage.',
          );
        }
        final opened = db = sqlite3.open(
          storage == 'memory' ? ':memory:' : '/database',
        );
        executor = SqliteExecutor(opened);
        // Sync OPFS handles own the database exclusively; a busy wait cannot
        // coordinate another owner. Keep durable rollback-journal storage.
        final maxParameters = configureSqlite(
          opened,
          journal: storage == 'memory' ? 'memory' : 'delete',
          busyTimeout: Duration.zero,
          fullSync: true,
        );
        return [sqlite3.version.versionNumber.toJS, maxParameters.toJS].toJS;
      } catch (_) {
        close();
        rethrow;
      }
    }
    final opened = db;
    if (opened == null) {
      throw const OrmException('DRIVER.CLOSED', 'SQLite worker is not open.');
    }
    switch (operation) {
      case 'execute':
        return sqliteWebResult(
          executor!.execute(sqliteWebDartCommand(payload)),
        );
      case 'cursor':
        return executor!.openCursor(sqliteWebDartCommand(payload)).toJS;
      case 'fetch':
        final parts = payload! as JSArray<JSAny?>;
        return sqliteWebResult(
          executor!.fetch(
            (parts[0]! as JSNumber).toDartInt,
            (parts[1]! as JSNumber).toDartInt,
          ),
        );
      case 'release':
        executor!.release((payload! as JSNumber).toDartInt);
        return null;
      case 'close':
        close();
        return null;
      default:
        throw const OrmException(
          'DRIVER.PROTOCOL',
          'Unknown SQLite worker command.',
        );
    }
  }

  void close() {
    if (executor != null) {
      executor!.close();
    } else {
      db?.close();
    }
    executor = null;
    db = null;
    if (opfs case final fs?) {
      engine?.unregisterVirtualFileSystem(fs);
      fs.close();
    }
    if (memory case final fs?) engine?.unregisterVirtualFileSystem(fs);
    opfs = null;
    memory = null;
  }
}
