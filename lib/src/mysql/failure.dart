import 'package:mysql_client_plus/exception.dart' as mysql;

import '../../driver.dart';

/// A server-reported error. Numeric codes are preserved; SQLSTATE is not
/// exposed by mysql_client_plus and is not guessed from the error message.
final class MysqlFailure implements SqlFailure {
  /// Original exception with the numeric code and server message.
  final mysql.MySQLServerException cause;

  /// Wraps a server error without inferring SQLSTATE from its message.
  const MysqlFailure(this.cause);

  /// Numeric MySQL or MariaDB server error code.
  int get code => cause.errorCode;
  @override
  bool get retryTransaction => code == 1213 || code == 1205;
  @override
  bool get retryCommit => false;
  @override
  bool get commitRejected => code == 1213;
  @override
  String toString() => 'MysqlFailure($code): ${cause.message}';
}
