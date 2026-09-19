part of '../../drivers/mysql.dart';

final class _MysqlConnection implements SqlConnection {
  final mysql.MySQLConnection _connection;
  final Duration _queryTimeout;
  bool _active = true;
  bool _invalid = false;
  Future<SqlResult>? _pending;
  Future<void>? _releasing;

  _MysqlConnection(this._connection, this._queryTimeout);

  // The upstream client discards OK/EOF status flags. Do not infer server
  // transaction state from the last SQL string or from a client-side bool.
  @override
  bool? get transactionActive => null;

  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    if (!_active || _invalid || !_connection.connected) {
      return Future.error(
        const OrmException(
          'SESSION.CLOSED',
          'MySQL connection lease has ended.',
        ),
      );
    }
    options.check();
    if (options.cancellation != null) {
      return Future.error(
        const OrmException(
          'CAPABILITY.CANCELLATION',
          'The MySQL driver does not support statement cancellation.',
        ),
      );
    }
    if (_pending != null) {
      return Future.error(
        const OrmException(
          'CONNECTION.BUSY',
          'Await the active statement before using the MySQL connection again.',
        ),
      );
    }
    final parameters = command.parameters.map(_mysqlParameter).toList();
    late final Future<SqlResult> operation;
    operation = _execute(command.sql, parameters)
        .timeout(
          options.timeout ?? _queryTimeout,
          onTimeout: () {
            _discard();
            throw const OrmException(
              'OPERATION.TIMEOUT',
              'MySQL statement timed out; the connection was discarded.',
            );
          },
        )
        .whenComplete(() {
          if (identical(_pending, operation)) _pending = null;
        });
    _pending = operation;
    return operation;
  }

  Future<SqlResult> _execute(String sql, List<Object?> parameters) async {
    sql = _mysqlWithoutTerminator(sql);
    mysql.PreparedStmt? statement;
    try {
      final mysql.IResultSet result;
      if (parameters.isEmpty) {
        // Upstream prepare() waits for an EOF that the protocol does not send
        // for statements with no parameters and no result columns (e.g. DDL
        // and ROLLBACK). Text protocol needs no value interpolation here.
        result = await _connection.execute(sql);
      } else {
        // Never use execute(sql, namedParams): that substitutes values into
        // SQL text. Parameterized statements use the binary protocol.
        statement = await _connection.prepare(sql);
        if (_invalid) {
          throw const OrmException(
            'SESSION.CLOSED',
            'Connection was discarded.',
          );
        }
        result = await statement.execute(parameters);
      }
      final columns = result.cols.toList();
      final lastId = result.lastInsertID;
      return SqlResult(
        [
          for (final row in result.rows)
            [
              for (var i = 0; i < columns.length; i++)
                _mysqlValue(
                  row.colAt(i),
                  columns[i].type.intVal,
                  binary: parameters.isNotEmpty,
                ),
            ],
        ],
        columns: [for (final column in columns) column.name],
        affectedRows: _checkedMysqlInt(result.affectedRows),
        lastInsertId: lastId == BigInt.zero ? null : _checkedMysqlInt(lastId),
      );
    } on mysql.MySQLServerException catch (error) {
      throw MysqlFailure(error);
    } on mysql.MySQLClientException catch (error) {
      _discard();
      throw OrmException(
        'DRIVER.PROTOCOL',
        'MySQL client could not complete the statement; connection discarded.',
        cause: error,
      );
    } on SocketException catch (error) {
      _discard();
      throw OrmException(
        'DRIVER.CONNECTION',
        'MySQL connection was lost; the statement outcome may be unknown.',
        cause: error,
      );
    } finally {
      if (statement != null && !_invalid && _connection.connected) {
        try {
          await statement.deallocate();
        } catch (_) {
          _discard();
          rethrow;
        }
      }
    }
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    options.check();
    throw const OrmException(
      'CAPABILITY.STREAMING',
      'MySQL streaming is not supported by this adapter. Use a bounded query.',
    );
  }

  void _discard() {
    _invalid = true;
    _connection.getSocket().destroy();
  }

  @override
  Future<void> invalidate() async {
    if (_active || _invalid) _discard();
  }

  Future<void> _release() => _releasing ??= (() async {
    _active = false;
    try {
      await _pending;
    } catch (_) {
      // execute() has already classified and surfaced this failure.
    }
    if (_invalid || !_connection.connected) return;
    try {
      // A raw caller may leave a transaction open, and server status flags are
      // unavailable. ROLLBACK is harmless when no transaction is active.
      await _execute('ROLLBACK', const []).timeout(_queryTimeout);
    } catch (error) {
      _discard();
      throw OrmException(
        'CONNECTION.CLEANUP',
        'MySQL lease cleanup failed; the connection was discarded.',
        cause: error,
      );
    }
  })();
}

// The upstream text client can replace a SELECT result with an empty trailing
// statement's OK packet when a delimiter is followed by comments. Remove only
// the final SQL delimiter, retaining quoted values and routine-body delimiters.
// Our session explicitly enables NO_BACKSLASH_ESCAPES and ANSI_QUOTES.
String _mysqlWithoutTerminator(String sql) {
  var i = 0, terminator = -1;
  while (i < sql.length) {
    final c = sql[i];
    if (c.trim().isEmpty) {
      i++;
      continue;
    }
    if (c == '#' ||
        sql.startsWith('--', i) &&
            (i + 2 == sql.length || sql.codeUnitAt(i + 2) <= 32)) {
      final end = sql.indexOf('\n', i);
      i = end < 0 ? sql.length : end + 1;
      continue;
    }
    if (sql.startsWith('/*', i)) {
      final end = sql.indexOf('*/', i + 2);
      if (end < 0) return sql;
      // Version comments contain executable SQL, so a preceding semicolon
      // cannot be assumed to be the statement's final effective token.
      if (sql.startsWith('/*!', i) || sql.startsWith('/*M!', i)) {
        terminator = -1;
      }
      i = end + 2;
      continue;
    }
    terminator = c == ';' ? i : -1;
    if (c == "'" || c == '"' || c == '`') {
      final quote = c;
      i++;
      var closed = false;
      while (i < sql.length) {
        if (sql[i++] != quote) continue;
        if (i < sql.length && sql[i] == quote) {
          i++;
        } else {
          closed = true;
          break;
        }
      }
      if (!closed) return sql;
    } else {
      i++;
    }
  }
  return terminator < 0
      ? sql
      : sql.replaceRange(terminator, terminator + 1, '');
}
