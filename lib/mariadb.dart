/// Mariadb connections for SQL execution and optional typed model views.
///
/// [mariadb] opens an owning SQL runtime. Import `package:orm/sql.dart` for
/// SQL operations, and `package:orm/orm.dart` to add a model view of that runtime.
/// [MariadbDriver] remains available for explicit driver ownership and leasing.
///
/// {@category Databases}
/// {@canonicalFor driver.MariadbDriver}
/// {@canonicalFor options.MariadbOptions}
/// {@canonicalFor driver.Mariadb}
/// {@canonicalFor mariadb.mariadb}
library;

export 'src/connect/mariadb.dart' show mariadb;
export 'src/driver/driver.dart' show Mariadb;
export 'src/mysql/driver.dart' show MariadbDriver;
export 'src/mysql/options.dart' show MariadbOptions;
