/// A declaration, generated file or migration source that cannot be processed.
final class GenerationException implements Exception {
  /// The validation failure, including source location when available.
  final String message;

  /// Creates a source-generation failure with an actionable [message].
  const GenerationException(this.message);

  @override
  String toString() => 'GenerationException: $message';
}
