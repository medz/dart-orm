/// Typed SQLite queries on native Dart, Flutter and the web.
///
/// Open a temporary database with [SqliteOptions.memory], a native file with
/// [SqliteOptions.file], or native/browser persistence with
/// [SqliteOptions.persistent]. The returned database owns its background worker.
/// Import a generated client to access model-specific table getters.
///
/// Use `package:orm/drivers/sqlite.dart` when only a raw driver is needed.
///
/// {@category Databases}
library;

import 'orm.dart';
import 'drivers/sqlite.dart';
export 'orm.dart';
export 'drivers/sqlite.dart';

/// Opens SQLite and returns a typed database that owns its driver and worker.
///
/// Completes after SQLite and the requested storage have initialized. Native
/// applications supply their own file path; persistent browser databases use an
/// OPFS name. Memory databases are discarded when the database closes.
///
/// [onQuery], [onAcquire] and [onDecode] observe runtime execution and result
/// decoding. Opening the database does not generate or apply a schema. Apply the
/// reviewed migration history before querying, and await [Database.close] when
/// the application owner no longer needs the connection.
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
