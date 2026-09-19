/// SQLite ORM convenience entrypoint. Raw SQL drivers are in drivers/sqlite.dart.
library;

import 'orm.dart';
import 'drivers/sqlite.dart';
export 'orm.dart';
export 'drivers/sqlite.dart';

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
