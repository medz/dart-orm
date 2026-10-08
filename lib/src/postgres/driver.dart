import 'dart:async';
import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:postgres/postgres.dart' as pg;

export 'package:postgres/postgres.dart' show Endpoint, PoolSettings, SslMode;

/// Owns a native postgres pool; each callback pins one physical connection.
///
/// The connection opens lazily on acquisition. Configuration is independent of
/// SQLite. Use [pg.PoolSettings] for limits, TLS, timeouts and application name.
/// Every isolation level and read-only transaction mode is supported.
///
/// SQL uses PostgreSQL's native `$1`, `$2`, ... placeholders without rewriting.
/// Parameters support int, String, bool, double, DateTime, Uint8List and null.
/// Dates are bound as UTC timestamptz; byte arrays use bytea. Unsupported values
/// fail before SQL execution. Native PostgreSQL result types are preserved.
/// Application SQL follows PostgreSQL session-setting persistence rules. Use
/// `SET LOCAL` inside [Database.transaction] for scoped configuration.
final class PostgresDriver implements Driver {
  /// Creates an owned pool for [endpoint]; opening happens on first use.
  PostgresDriver(pg.Endpoint endpoint, {pg.PoolSettings? settings})
    : _pool = pg.Pool<void>.withEndpoints([endpoint], settings: settings);

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
  /// Failed callbacks cause the native pool to discard that connection.
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
      return await _pool.withConnection((native) async {
        final connection = _PostgresConnection(native);
        try {
          final value = await runZoned(
            () => action(connection),
            zoneValues: {_callbackZone: true},
          );
          await connection._finish();
          return value;
        } catch (error, stack) {
          try {
            await connection._finish(ignoreFailure: true);
          } catch (_) {
            // The pool discards this connection; keep the callback/SQL cause.
          }
          Error.throwWithStackTrace(error, stack);
        }
      });
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

final class _PostgresConnection implements Connection {
  _PostgresConnection(this.connection);
  final pg.Connection connection;
  bool _active = true;
  bool _transactionOpen = false;
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
    final List<pg.TypedValue<Object>> values;
    try {
      values = parameters.map(_parameter).toList(growable: false);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final result = _tail.then((_) async {
      final result = await connection.execute(pg.Sql(sql), parameters: values);
      final words = _transactionWords(sql);
      switch (words.firstOrNull) {
        case 'BEGIN' || 'START':
          _transactionOpen = true;
        case 'COMMIT' || 'END' || 'ABORT':
          _transactionOpen = words.contains('CHAIN') && !words.contains('NO');
        case 'ROLLBACK':
          if (!words.skip(1).contains('TO')) {
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

  Future<void> _finish({bool ignoreFailure = false}) async {
    _active = false;
    await _tail;
    if (_transactionOpen) {
      await connection.execute('ROLLBACK');
      _transactionOpen = false;
    }
    if (!ignoreFailure) {
      if (_failure case final failure?) {
        Error.throwWithStackTrace(failure.$1, failure.$2);
      }
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
  Uint8List() => pg.TypedValue(pg.Type.byteArray, value),
  _ => throw ArgumentError.value(
    value,
    'parameter',
    'Unsupported PostgreSQL value.',
  ),
};
