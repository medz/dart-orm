import 'dart:async';

import 'package:orm/driver.dart';

/// Observes real driver submissions; all SQL, locks and errors reach [inner].
final class RecordingDriver<B extends Backend>(final Driver<B> inner)
    implements Driver<B> {
  final commands = <SqlCommand>[];
  void Function(SqlCommand)? onCommand;
  Future<void> Function(SqlCommand)? beforeCommand;

  @override
  Capabilities get capabilities => inner.capabilities;
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
