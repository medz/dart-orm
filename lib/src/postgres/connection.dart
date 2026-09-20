import 'dart:async';

import 'package:postgres/postgres.dart' as pg;

import '../../driver.dart';
import 'failure.dart';

final class PostgresConnection implements SqlConnection {
  // package:postgres does not expose ReadyForQuery transaction status publicly.
  @override
  bool? get transactionActive => null;
  final pg.Connection connection;
  final Future<pg.Connection> Function()? _control;
  final Expando<int> _backendIds;
  final Duration? _queryTimeout;
  bool _busy = false;
  int _cursorId = 0;
  PostgresConnection(
    this.connection,
    this._control,
    this._backendIds,
    this._queryTimeout,
  );

  // ResultStream is buffered only for this bounded statement. Its subscription
  // has no hidden timeout task that could cancel a later statement. We own and
  // await cancellation below, including connection-control cleanup.
  Future<SqlResult> _query(SqlCommand command) async {
    final statement = await connection.prepare(
      pg.Sql(
        command.sql,
        types: List.filled(command.parameters.length, pg.Type.unspecified),
      ),
    );
    try {
      final rows = <pg.ResultRow>[];
      final subscription = statement
          .bind([
            for (final p in command.parameters) p is SqlReal ? p.value : p,
          ])
          .listen(rows.add);
      try {
        await subscription.asFuture<void>();
        final schema = await subscription.schema;
        final jsonColumns = {
          for (final (index, column) in schema.columns.indexed)
            if (column.typeOid == pg.Type.json.oid ||
                column.typeOid == pg.Type.jsonb.oid)
              index,
        };
        // The driver parses JSON strings and JSON null into ordinary Dart values.
        // Retain their distinction from SQL text and SQL NULL without reserializing.
        final List<List<Object?>> values = jsonColumns.isEmpty
            ? rows
            : [
                for (final row in rows)
                  [
                    for (var i = 0; i < row.length; i++)
                      jsonColumns.contains(i) && !row.isSqlNull(i)
                          ? SqlJson(row[i])
                          : row[i],
                  ],
              ];
        return SqlResult(
          values,
          columns: [for (final c in schema.columns) c.columnName ?? ''],
          affectedRows: await subscription.affectedRows,
        );
      } finally {
        await subscription.cancel();
      }
    } finally {
      await statement.dispose();
    }
  }

  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    options.check();
    if (_busy) {
      throw const OrmException(
        'SESSION.BUSY',
        'Await the active statement before using this connection again.',
      );
    }
    final timeout = options.timeout ?? _queryTimeout;
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout');
    }
    if ((options.cancellation != null || timeout != null) && _control == null) {
      throw const OrmException(
        'CAPABILITY.CANCEL',
        'A borrowed PostgreSQL pool needs a cancellation connection factory.',
      );
    }
    _busy = true;
    Future<void>? cancelling;
    var completed = false, timedOut = false, statementStarted = false;
    Timer? deadline;
    void Function()? unsubscribe;
    try {
      if (options.cancellation != null || timeout != null) {
        var backendId = _backendIds[connection.info];
        void cancel() {
          if (completed || cancelling != null) return;
          final pid = backendId;
          cancelling = () async {
            // PID discovery is part of the same deadline. Until it completes,
            // discard this connection; the application SQL has not been sent.
            if (pid == null) {
              await connection.close(force: true);
              return;
            }
            try {
              final control = await _control!();
              try {
                if (!completed) {
                  final result = await control.execute(
                    pg.Sql(
                      r'SELECT pg_cancel_backend($1)',
                      types: [pg.Type.integer],
                    ),
                    parameters: [pid],
                  );
                  if (result.single.single != true && !completed) {
                    await connection.close(force: true);
                  }
                }
              } finally {
                await control.close(force: true);
              }
            } catch (_) {
              await connection.close(force: true);
              rethrow;
            }
          }();
          // Observe failures immediately; the operation awaits cleanup below.
          unawaited(cancelling!.catchError((Object _) {}));
        }

        unsubscribe = options.cancellation?.listen(cancel);
        if (timeout != null) {
          deadline = Timer(timeout, () {
            timedOut = true;
            cancel();
          });
        }
        options.check();
        backendId ??= _backendIds[connection.info] =
            (await _query(SqlCommand('SELECT pg_backend_pid()')))
                    .rows
                    .single
                    .single
                as int;
        options.check();
        if (timedOut) {
          throw const OrmException(
            'OPERATION.TIMEOUT',
            'PostgreSQL PID discovery exceeded the statement deadline.',
          );
        }
      }
      statementStarted = true;
      return await _query(command);
    } catch (error) {
      if ((timedOut || options.cancellation?.isCancelled == true) &&
          (!statementStarted ||
              error is pg.ServerException && error.code == '57014')) {
        throw OrmException(
          timedOut ? 'OPERATION.TIMEOUT' : 'OPERATION.CANCELLED',
          statementStarted ? 'PostgreSQL stopped the statement.' : 'PostgreSQL PID discovery was interrupted before the statement.',
          cause: error,
        );
      }
      if (error is pg.ServerException) throw PostgresFailure(error);
      rethrow;
    } finally {
      completed = true;
      deadline?.cancel();
      unsubscribe?.call();
      try {
        await cancelling;
      } finally {
        _busy = false;
      }
    }
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final name = 'orm_cursor_${_cursorId++}';
    await execute(
      SqlCommand(
        'DECLARE "$name" NO SCROLL CURSOR FOR ${command.sql}',
        command.parameters,
      ),
      options: options,
    );
    return _PostgresCursor(this, name);
  }

  @override
  Future<void> invalidate() => connection.close(force: true);
}

final class _PostgresCursor(
  final PostgresConnection connection,
  final String name,
) implements SqlCursor {
  bool _closed = false;
  @override
  Future<SqlResult> fetch(
    int count, {
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    if (_closed) throw const OrmException('CURSOR.CLOSED', 'Cursor has ended.');
    if (count < 1) throw ArgumentError.value(count, 'count');
    return connection.execute(
      SqlCommand('FETCH FORWARD $count FROM "$name"'),
      options: options,
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await connection.execute(SqlCommand('CLOSE "$name"'));
    } on PostgresFailure catch (e) {
      if (e.code != '25P02' && e.code != '34000') rethrow;
    }
  }
}
