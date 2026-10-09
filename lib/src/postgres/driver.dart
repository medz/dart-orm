import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:postgres/postgres.dart' as pg;

export 'package:postgres/postgres.dart'
    show
        Endpoint,
        PoolSettings,
        SslMode,
        PgException,
        ServerException,
        UniqueViolationException,
        ForeignKeyViolationException,
        Severity;

/// Owns a native postgres pool; each callback pins one physical connection.
///
/// The connection opens lazily on acquisition. Configuration is independent of
/// SQLite. Use [pg.PoolSettings] for limits, TLS, timeouts and application name.
/// Every isolation level and read-only transaction mode is supported.
///
/// SQL uses PostgreSQL's native `$1`, `$2`, ... placeholders without rewriting.
/// Each call executes one statement using the extended protocol, regardless of
/// the pool's queryMode. Prepared transactions are unsupported and rejected.
/// Parameters support int, String, bool, double, DateTime, Uint8List and null.
/// Dates are bound as UTC timestamptz; byte arrays use bytea. Unsupported values
/// fail before SQL execution. Native PostgreSQL result types are preserved.
/// Native exceptions propagate unchanged. PostgreSQL server errors retain
/// [pg.ServerException] codes and constraint metadata. SQLSTATE 23505 and 23503
/// retain their native unique and foreign-key exception subclasses.
/// Application SQL follows PostgreSQL session-setting persistence rules. Use
/// `SET LOCAL` inside [Database.transaction] for scoped configuration.
final class PostgresDriver implements Driver {
  /// Creates an owned pool for [endpoint]; opening happens on first use.
  PostgresDriver(
    pg.Endpoint endpoint, {
    String schema = 'public',
    pg.PoolSettings? settings,
  }) : schema = _validatedSchema(schema),
       _pool = pg.Pool<void>.withEndpoints([endpoint], settings: settings);

  /// Fixed application schema used by typed queries and migration histories.
  ///
  /// The schema must already exist. Raw SQL retains PostgreSQL's native
  /// search_path behavior; changing it does not redirect typed table queries.
  @override
  final String schema;

  final pg.Pool<void> _pool;
  final Object _callbackZone = Object();
  bool _closing = false;
  int _active = 0;
  Completer<void>? _idle;
  Future<void>? _closeFuture;

  @override
  Engine get engine => Engine.postgresql;
  @override
  Capabilities get capabilities =>
      const Capabilities(returning: true, maxParameters: 65535);

  /// Pins a pooled connection until [action] and its issued statements finish.
  ///
  /// The callback connection expires immediately when [action] settles.
  /// Callback errors preserve their cause and stack. After failure, reuse
  /// requires all issued SQL to be inside transactions that only rolled back.
  /// SQL/cleanup failures, commits and work outside a transaction discard it.
  /// The first SQL failure stays primary if automatic rollback also fails.
  /// Normal callbacks retain PostgreSQL session state. Use SET LOCAL inside a
  /// transaction for scoped settings; manage session advisory locks explicitly.
  /// Unfinished direct BEGIN/START transactions roll back before reuse. Nested
  /// acquisition is rejected so a callback cannot wait on its own pool slot.
  @override
  Future<T> withConnection<T>(
    Future<T> Function(Connection connection) action,
  ) async {
    if (_closing) {
      throw StateError('The PostgreSQL driver is closing or closed.');
    }
    if (Zone.current[_callbackZone] != null) {
      throw StateError('Nested PostgreSQL acquisition is not supported.');
    }
    _active++;
    try {
      final outcome = await _pool.withConnection((native) async {
        final connection = _PostgresConnection(native);
        T? value;
        (Object, StackTrace)? failure;
        try {
          value = await runZoned(
            () => action(connection),
            zoneValues: {_callbackZone: true},
          );
        } catch (error, stack) {
          failure = (error, stack);
        }
        try {
          await connection._finish();
        } catch (error, stack) {
          final cause = failure ?? (error, stack);
          await connection._discard();
          Error.throwWithStackTrace(cause.$1, cause.$2);
        }
        if (failure != null && !connection._canReuseAfterFailure) {
          await connection._discard();
          Error.throwWithStackTrace(failure.$1, failure.$2);
        }
        return (value: value, failure: failure);
      });
      if (outcome.failure case final failure?) {
        Error.throwWithStackTrace(failure.$1, failure.$2);
      }
      return outcome.value as T;
    } finally {
      _active--;
      if (_active == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Drains admitted callbacks and then releases every pooled connection.
  @override
  Future<void> close() {
    if (Zone.current[_callbackZone] != null) {
      return Future.error(
        StateError('Cannot close the driver in its callback.'),
      );
    }
    if (_closeFuture case final future?) return future;
    _closing = true;
    return _closeFuture = _close();
  }

  Future<void> _close() async {
    if (_active != 0) {
      _idle = Completer<void>();
      await _idle!.future;
    }
    await _pool.close();
  }
}

String _validatedSchema(String schema) {
  if (schema.isEmpty ||
      schema.contains('\u0000') ||
      schema.startsWith('pg_') ||
      utf8.encode(schema).length > 63) {
    throw ArgumentError.value(schema, 'schema', 'Invalid managed schema.');
  }
  return schema;
}

final class _PostgresConnection implements Connection {
  _PostgresConnection(this.connection);
  final pg.Connection connection;
  bool _active = true;
  bool _transactionOpen = false;
  bool _outsideTransactionWork = false;
  bool _rolledBack = false;
  Future<void> _tail = Future.value();
  (Object, StackTrace)? _failure;

  @override
  Future<QueryResult> run(String sql, List<Object?> parameters) {
    if (!_active) {
      return Future.error(StateError('The connection callback has expired.'));
    }
    if (parameters.length > 65535) {
      return Future.error(
        ArgumentError('The statement exceeds PostgreSQL limits.'),
      );
    }
    final words = _transactionWords(sql);
    if (words.firstOrNull == 'PREPARE' &&
        words.elementAtOrNull(1) == 'TRANSACTION') {
      return Future.error(
        UnsupportedError('Prepared transactions are not supported.'),
      );
    }
    final List<pg.TypedValue<Object>> values;
    try {
      values = parameters.map(_parameter).toList(growable: false);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final result = _tail.then((_) async {
      final result = await connection.execute(
        pg.Sql(sql),
        parameters: values,
        queryMode: pg.QueryMode.extended,
      );
      if (!_transactionOpen &&
          words.firstOrNull != 'BEGIN' &&
          words.firstOrNull != 'START') {
        _outsideTransactionWork = true;
      }
      switch (words.firstOrNull) {
        case 'BEGIN' || 'START':
          _transactionOpen = true;
        case 'COMMIT' || 'END':
          _outsideTransactionWork = true;
          _transactionOpen = words.contains('CHAIN') && !words.contains('NO');
        case 'ROLLBACK' || 'ABORT':
          if (!words.skip(1).contains('TO')) {
            _rolledBack = true;
            _transactionOpen = words.contains('CHAIN') && !words.contains('NO');
          }
      }
      return QueryResult(
        columns: List.unmodifiable(
          result.schema.columns.indexed.map(
            (column) => column.$2.columnName ?? '[${column.$1}]',
          ),
        ),
        rows: List.unmodifiable(result.map(List<Object?>.unmodifiable)),
        affectedRows: result.affectedRows,
      );
    });
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        _failure ??= (error, stack);
      },
    );
    return result;
  }

  Future<void> _finish() async {
    _active = false;
    await _tail;
    if (_transactionOpen) {
      try {
        await connection.execute('ROLLBACK', queryMode: pg.QueryMode.extended);
      } catch (error, stack) {
        final cause = _failure ?? (error, stack);
        Error.throwWithStackTrace(cause.$1, cause.$2);
      }
      _transactionOpen = false;
      _rolledBack = true;
    }
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
  }

  bool get _canReuseAfterFailure => _rolledBack && !_outsideTransactionWork;

  Future<void> _discard() async {
    try {
      await connection.close(force: true);
    } catch (_) {
      // The native handle is closing; preserve the original callback/SQL cause.
    }
  }
}

List<String> _transactionWords(String sql) {
  final words = <String>[];
  var offset = 0;
  while (offset < sql.length && words.length < 5) {
    if (RegExp(r'\s').hasMatch(sql[offset])) {
      offset++;
    } else if (sql.startsWith('--', offset)) {
      final end = sql.indexOf('\n', offset + 2);
      offset = end < 0 ? sql.length : end + 1;
    } else if (sql.startsWith('/*', offset)) {
      var depth = 1;
      offset += 2;
      while (offset < sql.length && depth != 0) {
        if (sql.startsWith('/*', offset)) {
          depth++;
          offset += 2;
        } else if (sql.startsWith('*/', offset)) {
          depth--;
          offset += 2;
        } else {
          offset++;
        }
      }
    } else {
      final match = RegExp(r'[A-Za-z]+').matchAsPrefix(sql, offset);
      if (match == null) break;
      words.add(match.group(0)!.toUpperCase());
      offset = match.end;
    }
  }
  return words;
}

pg.TypedValue<Object> _parameter(Object? value) => switch (value) {
  null => pg.TypedValue(pg.Type.unspecified, null),
  int() => pg.TypedValue(pg.Type.bigInteger, value),
  String() => pg.TypedValue(pg.Type.text, value),
  bool() => pg.TypedValue(pg.Type.boolean, value),
  double() => pg.TypedValue(pg.Type.double, value),
  DateTime() => pg.TypedValue(pg.Type.timestampTz, value.toUtc()),
  Uint8List() => pg.TypedValue(pg.Type.byteArray, Uint8List.fromList(value)),
  _ => throw ArgumentError.value(
    value,
    'parameter',
    'Unsupported PostgreSQL value.',
  ),
};
