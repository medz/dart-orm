/// MySQL connections for raw SQL and typed ORM sessions.
///
/// Each driver owns one physical connection and queues entire connection leases,
/// so another caller cannot enter an active transaction.
///
/// {@category Drivers}
/// {@canonicalFor driver.MysqlDriver}
/// {@canonicalFor failure.MysqlFailure}
/// {@canonicalFor options.MysqlOptions}
/// {@canonicalFor options.MysqlTls}
// Stable names distinguish raw drivers from ORM entrypoints in Dartdoc.
// ignore: unnecessary_library_name
library drivers_mysql;

export '../driver.dart';
export '../src/mysql/driver.dart' show MysqlDriver;
export '../src/mysql/failure.dart' show MysqlFailure;
export '../src/mysql/options.dart' show MysqlOptions, MysqlTls;
