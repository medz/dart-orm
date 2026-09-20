/// MariaDB connections without ORM or generated model dependencies.
///
/// {@category Drivers}
/// {@canonicalFor driver.MariadbDriver}
/// {@canonicalFor options.MariadbOptions}
// Stable names distinguish raw drivers from ORM entrypoints in Dartdoc.
// ignore: unnecessary_library_name
library drivers_mariadb;

export '../driver.dart';
export '../src/mysql/driver.dart' show MariadbDriver;
export '../src/mysql/options.dart' show MariadbOptions, MysqlTls;
export '../src/mysql/failure.dart' show MysqlFailure;
