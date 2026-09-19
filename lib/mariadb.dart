/// Typed MariaDB access with its own capabilities and migration target.
library;

import 'drivers/mariadb.dart';
import 'orm.dart';
export 'drivers/mariadb.dart';
export 'orm.dart';

Future<Database<Mariadb>> mariadb(
  MariadbOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
  void Function(DecodeEvent)? onDecode,
}) async => Database(
  await MariadbDriver.open(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
  onDecode: onDecode,
);
