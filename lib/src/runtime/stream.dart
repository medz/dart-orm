part of '../../runtime.dart';

extension SqlDatabaseStreaming on SqlDatabase<Backend> {
  /// Stream raw rows from a database cursor with demand-driven batch fetches.
  Stream<List<Object?>> stream(
    SqlCommand command, {
    int batchSize = 128,
    ExecutionOptions options = const ExecutionOptions(),
  }) => streamRows(
    command,
    batchSize: batchSize,
    options: options,
    decode: (_, rows, _) async => rows,
  );

  Stream<R> streamRows<R>(
    SqlCommand command, {
    required int batchSize,
    required ExecutionOptions options,
    required Future<List<R>> Function(
      SqlConnection,
      List<List<Object?>>,
      ExecutionOptions,
    )
    decode,
  }) {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
    if (!capabilities.streaming) {
      throw const OrmException(
        'CAPABILITY.STREAM',
        'This driver does not support database cursors.',
      );
    }
    if ((options.cancellation != null || options.timeout != null) &&
        !capabilities.cancellation) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'This driver cannot cancel a running statement.',
      );
    }
    options.check();
    if (command.parameters.length > capabilities.maxParameters) {
      throw const OrmException(
        'QUERY.PARAMETERS',
        'Query exceeds the driver parameter limit.',
      );
    }
    final cancellation = CancellationToken();
    final execution = ExecutionOptions(
      cancellation: capabilities.cancellation ? cancellation : null,
      timeout: options.timeout,
    );
    final finished = Completer<void>();
    Completer<void>? demand;
    var stopped = false, started = false;
    Object? cleanupFailure, requestedError;
    late StreamController<R> controller;
    void requestStop() {
      stopped = true;
      cancellation.cancel();
      demand?.complete();
      demand = null;
    }

    Future<void> stop() async {
      requestStop();
      if (started) await finished.future;
      if (cleanupFailure != null) throw cleanupFailure!;
    }

    Future<void> waitForDemand() async {
      if (controller.isPaused && !stopped) {
        demand ??= Completer<void>();
        await demand!.future;
      }
    }

    Future<T> observe<T>(
      QueryOperation operation,
      Future<T> Function() action,
    ) async {
      final watch = onQuery == null ? null : (Stopwatch()..start());
      Object? error;
      T? result;
      try {
        return result = await action();
      } catch (e) {
        error = e;
        if (inTransaction) _statementFailed = true;
        rethrow;
      } finally {
        watch?.stop();
        try {
          onQuery?.call(
            QueryEvent(
              operation: operation,
              sql: command.sql,
              parameterCount: operation == .cursorOpen
                  ? command.parameters.length
                  : 0,
              elapsed: watch!.elapsed,
              rowCount: result is SqlResult ? result.rows.length : null,
              error: error,
            ),
          );
        } catch (_) {}
      }
    }

    Future<void> produce() async {
      started = true;
      _streams.add(stop);
      final unsubscribe = options.cancellation?.listen(() {
        requestedError = const OrmException(
          'OPERATION.CANCELLED',
          'Stream cancelled.',
        );
        requestStop();
      });
      try {
        await run(
          (connection) async {
            final ownsTransaction = !inTransaction;
            SqlCursor? cursor;
            var complete = false, began = false;
            try {
              if (stopped) return;
              if (ownsTransaction) {
                await _executeOn(
                  connection is _SessionConnection
                      ? connection.inner
                      : connection,
                  SqlCommand(switch (dialect) {
                    SqlDialect.postgres => 'BEGIN READ ONLY',
                    SqlDialect.mysql ||
                    SqlDialect.mariadb => 'START TRANSACTION READ ONLY',
                    SqlDialect.sqlite => 'BEGIN',
                  }),
                );
                began = true;
              }
              cursor = await observe(
                .cursorOpen,
                () => connection.openCursor(command, options: execution),
              );
              while (!stopped) {
                await waitForDemand();
                if (stopped) break;
                final batch = await observe(
                  .cursorFetch,
                  () => cursor!.fetch(batchSize, options: execution),
                );
                if (stopped) break;
                final rows = await decode(connection, batch.rows, execution);
                for (final row in rows) {
                  await waitForDemand();
                  if (stopped) break;
                  controller.add(row);
                }
                if (batch.rows.length < batchSize) {
                  complete = !stopped;
                  break;
                }
              }
            } finally {
              try {
                if (cursor != null) await observe(.cursorClose, cursor.close);
                if (began) {
                  await _executeOn(
                    connection is _SessionConnection
                        ? connection.inner
                        : connection,
                    SqlCommand(complete ? 'COMMIT' : 'ROLLBACK'),
                  );
                }
              } catch (e) {
                cleanupFailure = e;
                if (inTransaction) _active = false;
                await connection.invalidate();
                rethrow;
              }
            }
          },
          acquire: AcquisitionOptions(
            timeout: options.acquireTimeout,
            cancellation: cancellation,
          ),
        );
      } catch (error, stack) {
        if (!stopped) controller.addError(error, stack);
      } finally {
        unsubscribe?.call();
        if (requestedError != null) controller.addError(requestedError!);
        _streams.remove(stop);
        finished.complete();
        // A cancellation cleanup error is already exposed by stop() or the
        // error event. Do not report it again through an unobserved close future.
        unawaited(controller.close().catchError((Object _) {}));
      }
    }

    controller = StreamController<R>(
      sync: true,
      onListen: () => unawaited(produce()),
      onPause: () {
        demand ??= Completer<void>();
      },
      onResume: () {
        demand?.complete();
        demand = null;
      },
      onCancel: stop,
    );
    return controller.stream;
  }
}
