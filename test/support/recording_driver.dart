import 'dart:async';

import 'package:orm/driver.dart';

/// Observes real driver submissions; all SQL, locks and errors reach [inner].
final class RecordingDriver<B extends Backend>(
  final Driver<B> inner, {
  // Disable a feature to exercise fallback SQL on a real connection. This does
  // not establish support for a separate platform lacking that feature.
  final bool withoutReturning = false,
  final int? maxParameters,
}) implements Driver<B> {
  final commands = <SqlCommand>[];
  void Function(SqlCommand)? onCommand;
  Future<void> Function(SqlCommand)? beforeCommand;

  @override
  Capabilities get capabilities {
    final source = inner.capabilities;
    if (!withoutReturning && maxParameters == null) return source;
    return Capabilities(
      dialect: source.dialect,
      maxParameters: maxParameters ?? source.maxParameters,
      returning: !withoutReturning && source.returning,
      windowFunctions: source.windowFunctions,
      streaming: source.streaming,
      cancellation: source.cancellation,
      statementTimeout: source.statementTimeout,
      exactDecimal: source.exactDecimal,
      temporal: source.temporal,
    );
  }

  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      inner.run((connection) => action(_RecordingConnection(connection, this)));
  @override
  Future<void> close() => inner.close();
}

final class _RecordingConnection(
  final SqlConnection inner,
  final RecordingDriver<Backend> owner,
) implements SqlConnection {
  @override
  bool? get transactionActive => inner.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    if (owner.beforeCommand case final before?) await before(command);
    owner.commands.add(command);
    owner.onCommand?.call(command);
    return inner.execute(command, options: options);
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => inner.openCursor(command, options: options);
  @override
  Future<void> invalidate() => inner.invalidate();
}
