/// Native SQLite on one long-lived background isolate.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as native;

import 'orm.dart';
export 'orm.dart';

enum SqliteJournal { wal, delete, memory }

final class SqliteOptions {
  final String path;
  final SqliteJournal journal;
  final Duration busyTimeout;
  const SqliteOptions.file(
    this.path, {
    this.journal = SqliteJournal.wal,
    this.busyTimeout = const Duration(seconds: 5),
  });
  const SqliteOptions.memory({this.busyTimeout = const Duration(seconds: 5)})
    : path = ':memory:',
      journal = SqliteJournal.memory;
}

final class SqliteFailure implements Exception {
  final int code;
  final int extendedCode;
  final String message;
  const SqliteFailure(this.code, this.extendedCode, this.message);
  @override
  String toString() => 'SqliteFailure($extendedCode): $message';
}

final class SqliteDriver implements Driver<Sqlite> {
  final _SqliteWorker _worker;
  @override
  final Capabilities capabilities;
  Future<void> _tail = Future.value();
  bool _closed = false;
  SqliteDriver._(this._worker, this.capabilities);

  static Future<SqliteDriver> open(SqliteOptions options) async {
    if (options.path.isEmpty || options.busyTimeout.isNegative) {
      throw ArgumentError('Invalid SQLite options.');
    }
    final worker = _SqliteWorker();
    final (port, maxParameters, version) = await worker.open(options);
    worker.port = port;
    if (version < 3035000) {
      await worker.stop();
      throw const OrmException(
        'CAPABILITY.VERSION',
        'SQLite 3.35 or newer is required.',
      );
    }
    return SqliteDriver._(
      worker,
      Capabilities(dialect: SqlDialect.sqlite, maxParameters: maxParameters),
    );
  }

  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) {
    if (_closed) {
      throw const OrmException('DRIVER.CLOSED', 'SQLite driver is closed.');
    }
    // Queue the whole lease so another caller cannot enter an active transaction.
    final result = _tail.then((_) => action(_worker));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _tail;
    await _worker.stop();
  }
}

final class _SqliteWorker implements SqlConnection {
  final ReceivePort _responses = ReceivePort();
  final Completer<(SendPort, int, int)> _ready = Completer();
  final Map<int, Completer<SqlResult>> _pending = {};
  late SendPort port;
  Isolate? _isolate;
  var _id = 0;
  bool _stopped = false;

  Future<(SendPort, int, int)> open(SqliteOptions options) async {
    _responses.listen((Object? message) {
      if (message case [0, SendPort port, int maxParameters, int version]) {
        _ready.complete((port, maxParameters, version));
      } else if (message case [int id, SqlResult result]) {
        _pending.remove(id)?.complete(result);
      } else if (message case [int id, Object error]) {
        if (id == 0 && !_ready.isCompleted) {
          _ready.completeError(error);
        } else {
          _pending.remove(id)?.completeError(error);
        }
      } else {
        const error = OrmException(
          'DRIVER.WORKER',
          'SQLite worker exited unexpectedly.',
        );
        if (!_ready.isCompleted) _ready.completeError(error);
        for (final pending in _pending.values) {
          pending.completeError(error);
        }
        _pending.clear();
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

  @override
  Future<SqlResult> execute(SqlCommand command) {
    if (_stopped) {
      throw const OrmException('DRIVER.CLOSED', 'SQLite worker is closed.');
    }
    final id = ++_id;
    final result = Completer<SqlResult>();
    _pending[id] = result;
    port.send((id, command));
    return result.future;
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final id = ++_id;
    final result = Completer<SqlResult>();
    _pending[id] = result;
    port.send((id, null));
    try {
      await result.future;
    } finally {
      _responses.close();
      _isolate?.kill();
    }
  }

  @override
  Future<void> invalidate() => stop();
}

void _sqliteMain((SendPort, SqliteOptions) init) async {
  final (response, options) = init;
  native.Database? db;
  final commands = ReceivePort();
  try {
    db = native.sqlite3.open(options.path);
    db.execute('PRAGMA foreign_keys = ON');
    if (db.select('PRAGMA foreign_keys').single.values.single != 1) {
      throw const OrmException(
        'DRIVER.FOREIGN_KEYS',
        'SQLite foreign key enforcement could not be enabled.',
      );
    }
    db.execute('PRAGMA busy_timeout = ${options.busyTimeout.inMilliseconds}');
    final journal = db
        .select('PRAGMA journal_mode = ${options.journal.name}')
        .single
        .values
        .single;
    if (journal != options.journal.name) {
      throw OrmException(
        'DRIVER.JOURNAL',
        'Requested ${options.journal.name}, received $journal.',
      );
    }
    var maxParameters = 999;
    for (final row in db.select('PRAGMA compile_options')) {
      final option = row.values.single as String;
      if (option.startsWith('MAX_VARIABLE_NUMBER=')) {
        maxParameters = int.parse(option.split('=').last);
      }
    }
    response.send([
      0,
      commands.sendPort,
      maxParameters,
      native.sqlite3.version.versionNumber,
    ]);
    await for (final message in commands) {
      final (id, command) = message as (int, SqlCommand?);
      if (command == null) {
        db!.close();
        db = null;
        response.send([id, const SqlResult([])]);
        break;
      }
      try {
        final statement = db!.prepare(command.sql, checkNoTail: true);
        try {
          final result = statement.select(command.parameters);
          response.send([
            id,
            SqlResult(
              [for (final row in result) row.values.toList()],
              columns: result.columnNames,
              affectedRows: statement.isReadOnly ? 0 : db.updatedRows,
            ),
          ]);
        } finally {
          statement.close();
        }
      } on native.SqliteException catch (e) {
        response.send([
          id,
          SqliteFailure(e.resultCode, e.extendedResultCode, e.message),
        ]);
      } catch (e) {
        response.send([id, OrmException('DRIVER.SQLITE', e.toString())]);
      }
    }
  } catch (e) {
    response.send([0, OrmException('DRIVER.OPEN', e.toString())]);
  } finally {
    db?.close();
    commands.close();
  }
}

Future<Database<Sqlite>> sqlite(
  SqliteOptions options, {
  void Function(QueryEvent)? onQuery,
}) async => Database(await SqliteDriver.open(options), onQuery: onQuery);
