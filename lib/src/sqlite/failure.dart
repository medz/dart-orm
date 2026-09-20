import '../../driver.dart';

/// A SQLite error preserving both the primary and extended result codes.
final class SqliteFailure implements SqlFailure {
  @override
  bool get retryTransaction => code == 5;
  @override
  bool get retryCommit => code == 5;
  @override
  bool get commitRejected => code == 5 || code == 19;

  /// Primary SQLite result code, such as BUSY (5) or CONSTRAINT (19).
  final int code;

  /// Extended result code identifying the specific SQLite failure.
  final int extendedCode;

  /// Error text returned by the SQLite engine.
  final String message;

  /// Preserves the engine failure without interpreting its message.
  const SqliteFailure(this.code, this.extendedCode, this.message);
  @override
  String toString() => 'SqliteFailure($extendedCode): $message';
}
