/// Typed MySQL access. Use drivers/mysql.dart for the independent raw driver.
library;

import 'drivers/mysql.dart';
import 'orm.dart';
export 'drivers/mysql.dart';
export 'orm.dart';

Future<Database<Mysql>> mysql(
  MysqlOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
  void Function(DecodeEvent)? onDecode,
}) async => Database(
  await MysqlDriver.open(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
  onDecode: onDecode,
);
