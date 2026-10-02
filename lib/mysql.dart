/// Mysql connections for SQL execution and optional typed model views.
///
/// [mysql] opens an owning SQL runtime. Import `package:orm/sql.dart` for
/// SQL operations, and `package:orm/orm.dart` to add a model view of that runtime.
/// [MysqlDriver] remains available for explicit driver ownership and leasing.
///
/// {@category Databases}
/// {@canonicalFor driver.MysqlDriver}
/// {@canonicalFor failure.MysqlFailure}
/// {@canonicalFor options.MysqlOptions}
/// {@canonicalFor options.MysqlTls}
/// {@canonicalFor driver.Mysql}
/// {@canonicalFor mysql.mysql}
library;

export 'src/connect/mysql.dart' show mysql;
export 'src/driver/driver.dart' show Mysql;
export 'src/mysql/driver.dart' show MysqlDriver;
export 'src/mysql/failure.dart' show MysqlFailure;
export 'src/mysql/options.dart' show MysqlOptions, MysqlTls;
