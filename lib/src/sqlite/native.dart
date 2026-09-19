import 'dart:async';
import 'dart:isolate';
import 'dart:ffi' as ffi;

import 'package:sqlite3/sqlite3.dart' as native;

import '../../driver.dart';
import 'execution.dart';
import 'failure.dart';
import 'opened.dart';
import 'options.dart';

part 'native_client.dart';
part 'native_server.dart';

Future<OpenedSqlite> connectSqlite(SqliteOptions options) async {
  if (options.path.isEmpty ||
      options.busyTimeout.isNegative ||
      options.name != null && options.path == ':memory:') {
    throw ArgumentError(
      'A native SQLite file requires a non-empty path. '
      'Set nativePath for SqliteOptions.persistent, and use memory() for memory storage.',
    );
  }
  final worker = _SqliteWorker();
  final (port, maxParameters, version) = await worker.open(options);
  worker.port = port;
  return (
    connection: worker,
    capabilities: Capabilities(
      dialect: SqlDialect.sqlite,
      maxParameters: maxParameters,
      streaming: true,
      cancellation: worker.supportsCancellation,
      exactDecimal: true,
      temporal: true,
    ),
    version: version,
    close: worker.stop,
  );
}
