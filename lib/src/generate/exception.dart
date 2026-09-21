/// A declaration, generated file or migration source that cannot be processed.
final class GenerationException implements Exception {
  /// The validation failure, including source location when available.
  final String message;

  /// Stable diagnostic category for source-level schema errors.
  final String? code;

  /// Source library, when the failure has a declaration.
  final Uri? source;

  /// One-based source line, or null for a failure without a source location.
  final int? line;

  /// One-based source column, or null for a failure without a source location.
  final int? column;

  /// Creates a source-generation failure with an actionable [message].
  const GenerationException(
    this.message, {
    this.code,
    this.source,
    this.line,
    this.column,
  });

  @override
  String toString() =>
      '${source == null ? 'GenerationException' : '$source:$line:$column'}: ${code == null ? '' : '[$code] '}$message';
}
