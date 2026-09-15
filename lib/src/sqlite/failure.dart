import '../../orm.dart';

final class SqliteFailure implements SqlFailure {
  @override
  bool get retryTransaction => code == 5;
  @override
  bool get retryCommit => code == 5;
  @override
  bool get commitRejected => code == 5 || code == 19;
  final int code;
  final int extendedCode;
  final String message;
  const SqliteFailure(this.code, this.extendedCode, this.message);
  @override
  String toString() => 'SqliteFailure($extendedCode): $message';
}
