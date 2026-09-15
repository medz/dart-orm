/// Compile a worker entry point whose main calls [runSqliteWebWorker].
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:sqlite3/wasm.dart' as sqlite;
import 'package:web/web.dart' as web;

import 'orm.dart';
import 'src/sqlite/functions.dart';
import 'src/sqlite/web_wire.dart';

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
  final Map<int, _WorkerCursor> cursors = {};
  int serial = 0;
  bool? get active => db == null ? null : !db!.autocommit;

  Future<JSAny?> handle(String operation, JSAny? payload) async {
    if (operation == 'open') {
      if (engine != null) {
        throw const OrmException('DRIVER.OPEN', 'Worker is already open.');
      }
      final options = payload! as JSArray<JSAny?>;
      final wasm = (options[0]! as JSString).toDart;
      final storage = (options[1]! as JSString).toDart;
      try {
        final sqlite3 = engine = await sqlite.WasmSqlite3.loadFromUrlString(
          wasm,
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
        registerSqliteFunctions(opened);
        opened.execute('PRAGMA foreign_keys = ON');
        if (opened.select('PRAGMA foreign_keys').single.values.single != 1) {
          throw const OrmException(
            'DRIVER.FOREIGN_KEYS',
            'SQLite foreign keys were not enabled.',
          );
        }
        final journal = storage == 'memory' ? 'memory' : 'delete';
        if (opened
                .select('PRAGMA journal_mode = $journal')
                .single
                .values
                .single !=
            journal) {
          throw const OrmException(
            'DRIVER.JOURNAL',
            'SQLite journal mode differs.',
          );
        }
        // OPFS sync handles exclusively own this database. Busy waits cannot
        // coordinate another owner and would only block the worker.
        opened.execute('PRAGMA busy_timeout = 0');
        opened.execute('PRAGMA synchronous = FULL');
        var maxParameters = 999;
        for (final row in opened.select('PRAGMA compile_options')) {
          final option = row.values.single as String;
          if (option.startsWith('MAX_VARIABLE_NUMBER=')) {
            maxParameters = int.parse(option.split('=').last);
          }
        }
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
        final command = sqliteWebDartCommand(payload);
        final statement = opened.prepare(command.sql, checkNoTail: true);
        try {
          final rows = statement.select(sqliteParameters(command.parameters));
          return sqliteWebResult(
            SqlResult(
              [for (final row in rows) row.values.toList()],
              columns: rows.columnNames,
              affectedRows: statement.isReadOnly ? 0 : opened.updatedRows,
            ),
          );
        } finally {
          statement.close();
        }
      case 'cursor':
        final command = sqliteWebDartCommand(payload);
        final statement = opened.prepare(command.sql, checkNoTail: true);
        try {
          if (!statement.isReadOnly) {
            throw const OrmException(
              'CURSOR.READ_ONLY',
              'Streaming requires a read-only query.',
            );
          }
          final id = ++serial;
          cursors[id] = _WorkerCursor(
            statement,
            statement.selectCursor(sqliteParameters(command.parameters)),
          );
          return id.toJS;
        } catch (_) {
          statement.close();
          rethrow;
        }
      case 'fetch':
        final parts = payload! as JSArray<JSAny?>;
        final cursor = cursors[(parts[0]! as JSNumber).toDartInt]!;
        return sqliteWebResult(cursor.fetch((parts[1]! as JSNumber).toDartInt));
      case 'release':
        cursors.remove((payload! as JSNumber).toDartInt)?.close();
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
    for (final cursor in cursors.values) {
      cursor.close();
    }
    cursors.clear();
    db?.close();
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

final class _WorkerCursor(
  final sqlite.CommonPreparedStatement statement,
  final sqlite.IteratingCursor cursor,
) {
  bool closed = false;
  SqlResult fetch(int count) {
    final rows = <List<Object?>>[];
    while (!closed && rows.length < count) {
      if (!cursor.moveNext()) {
        close();
        break;
      }
      rows.add(cursor.current.values.toList());
    }
    return SqlResult(rows, columns: cursor.columnNames);
  }

  void close() {
    if (closed) return;
    closed = true;
    statement.close();
  }
}
