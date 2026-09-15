/// Native SQLite on one long-lived background isolate.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:ffi' as ffi;

import 'package:sqlite3/sqlite3.dart' as native;

import 'orm.dart';
import 'src/sqlite/failure.dart';
import 'src/sqlite/functions.dart';
export 'src/sqlite/failure.dart';
export 'orm.dart';

part 'src/sqlite/worker.dart';
part 'src/sqlite/native.dart';

enum SqliteJournal { wal, delete, memory }

final class SqliteOptions {
  final String path;
  final SqliteJournal? journal;
  final bool readOnly;
  final Duration busyTimeout;
  const SqliteOptions.file(
    this.path, {
    this.journal = SqliteJournal.wal,
    this.busyTimeout = const Duration(seconds: 5),
  }) : readOnly = false;
  const SqliteOptions.readOnly(
    this.path, {
    this.busyTimeout = const Duration(seconds: 5),
  }) : journal = null,
       readOnly = true;
  const SqliteOptions.memory({this.busyTimeout = const Duration(seconds: 5)})
    : path = ':memory:',
      journal = SqliteJournal.memory,
      readOnly = false;
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
      Capabilities(
        dialect: SqlDialect.sqlite,
        maxParameters: maxParameters,
        streaming: true,
        cancellation: worker.supportsCancellation,
        exactDecimal: true,
        temporal: true,
      ),
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
