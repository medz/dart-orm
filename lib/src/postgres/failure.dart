import 'package:postgres/postgres.dart' as pg;

import '../../driver.dart';

/// A server-reported error, preserving SQLSTATE and the original exception.
final class PostgresFailure implements SqlFailure {
  /// The original driver exception, including server diagnostics.
  final pg.ServerException cause;

  /// Wraps a PostgreSQL server failure without losing its SQLSTATE.
  const PostgresFailure(this.cause);

  /// Five-character SQLSTATE reported by the server, when available.
  String? get code => cause.code;
  @override
  bool get retryTransaction => code == '40001' || code == '40P01';
  @override
  bool get retryCommit => false;
  @override
  bool get commitRejected => code?.startsWith('23') == true || retryTransaction;
  @override
  String toString() => cause.toString();
}
