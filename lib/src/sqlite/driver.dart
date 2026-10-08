import 'dart:async';
import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Owns one native SQLite connection and serializes callback acquisition FIFO.
///
/// All statements and complete transactions share this queue, so independent
/// sessions cannot accidentally execute inside another callback's transaction.
/// The handle is isolate-local. Queries execute synchronously on that isolate;
/// use a worker isolate for workloads that must not block a UI event loop.
///
/// Parameters use `?` placeholders. Boolean values bind as 0/1; DateTime values
/// bind as exact integer microseconds since the Unix epoch. Result values keep
/// SQLite's native storage types.
/// Unsupported parameter objects are rejected before executing SQL.
final class SqliteDriver implements Driver {
  SqliteDriver._(this._database) {
    // PRAGMA avoids sqlite3 3.6.0's non-advancing compileOptions iterator.
    final options = _database.select('PRAGMA compile_options');
    var maxParameters = 999;
    for (final row in options) {
      final option = row.columnAt(0) as String;
      if (option.startsWith('MAX_VARIABLE_NUMBER=')) {
        maxParameters = int.parse(
          option.substring('MAX_VARIABLE_NUMBER='.length),
        );
      }
    }
    capabilities = Capabilities(
      returning: sqlite.sqlite3.version.versionNumber >= 3035000,
      maxParameters: maxParameters,
    );
    try {
      _database.execute('PRAGMA foreign_keys = ON');
    } catch (_) {
      _database.close();
      rethrow;
    }
  }

  /// Opens [path], creating it if absent. Owns the handle until [close].
  factory SqliteDriver.open(String path) =>
      SqliteDriver._(sqlite.sqlite3.open(path));

  /// Opens an isolated in-memory database, deleted when [close] completes.
  factory SqliteDriver.memory() =>
      SqliteDriver._(sqlite.sqlite3.openInMemory());

  /// Opens an existing database file using SQLite's native read-only mode.
  ///
  /// Reads and ordinary serializable transactions are supported; persistent
  /// writes fail at the database engine. Temporary tables follow SQLite rules.
  factory SqliteDriver.openReadOnly(String path) =>
      SqliteDriver._(sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly));

  final sqlite.Database _database;
  final Object _callbackZone = Object();
  Future<void> _tail = Future.value();
  bool _closing = false;
  Future<void>? _closeFuture;

  @override
  Engine get engine => Engine.sqlite;
  @override
  late final Capabilities capabilities;

  /// Acquires the exclusive handle and invalidates it after [action] completes.
  ///
  /// Callback errors release the queue. Nested acquisition and closing from
  /// this callback are rejected to prevent waiting on one's own handle.
  @override
  Future<T> withConnection<T>(
    Future<T> Function(Connection connection) action,
  ) {
    if (_closing) {
      return Future.error(
        StateError('The SQLite driver is closing or closed.'),
      );
    }
    if (Zone.current[_callbackZone] != null) {
      return Future.error(
        StateError('Nested SQLite acquisition is not supported.'),
      );
    }
    final result = _tail.then((_) async {
      final connection = _SqliteConnection(
        _database,
        capabilities.maxParameters,
      );
      try {
        return await runZoned(
          () => action(connection),
          zoneValues: {_callbackZone: true},
        );
      } finally {
        connection._active = false;
        // Direct driver users must not leak an unfinished transaction to a
        // later acquisition. Runtime transactions normally finish explicitly.
        if (!_database.autocommit) _database.execute('ROLLBACK');
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Stops accepting callbacks, drains admitted work, then closes the handle.
  @override
  Future<void> close() {
    if (Zone.current[_callbackZone] != null) {
      return Future.error(
        StateError('Cannot close the driver in its callback.'),
      );
    }
    if (_closeFuture case final future?) return future;
    _closing = true;
    return _closeFuture = _tail.then((_) => _database.close());
  }
}

final class _SqliteConnection implements Connection {
  _SqliteConnection(this.database, this.maxParameters);
  final sqlite.Database database;
  final int maxParameters;
  bool _active = true;

  @override
  Future<QueryResult> run(String sql, List<Object?> parameters) async {
    if (!_active) throw StateError('The connection callback has expired.');
    if (parameters.length > maxParameters) {
      throw ArgumentError('The statement exceeds the SQLite parameter limit.');
    }
    final values = parameters.map(_parameter).toList(growable: false);
    final statement = database.prepare(sql, checkNoTail: true);
    try {
      final result = statement.select(values);
      return QueryResult(
        columns: List.unmodifiable(result.columnNames),
        rows: List.unmodifiable(result.rows.map(List<Object?>.unmodifiable)),
        // sqlite3_changes() retains the previous DML count after DDL and
        // transaction controls. Only row-writing statements own that count.
        affectedRows: statement.isReadOnly || !_writesRows(sql)
            ? 0
            : database.updatedRows,
      );
    } finally {
      statement.close();
    }
  }
}

bool _writesRows(String sql) {
  var offset = 0;
  while (offset < sql.length) {
    if (RegExp(r'\s').hasMatch(sql[offset])) {
      offset++;
    } else if (sql.startsWith('--', offset)) {
      final end = sql.indexOf('\n', offset + 2);
      offset = end < 0 ? sql.length : end + 1;
    } else if (sql.startsWith('/*', offset)) {
      final end = sql.indexOf('*/', offset + 2);
      offset = end < 0 ? sql.length : end + 2;
    } else {
      break;
    }
  }
  final command = RegExp(r'[A-Za-z]+').matchAsPrefix(sql, offset)?.group(0);
  // SQLite WITH SELECT is read-only. A writable WITH is INSERT/UPDATE/DELETE.
  return const {
    'INSERT',
    'UPDATE',
    'DELETE',
    'REPLACE',
    'WITH',
  }.contains(command?.toUpperCase());
}

Object? _parameter(Object? value) => switch (value) {
  null || int() || String() || double() || Uint8List() => value,
  bool() => value ? 1 : 0,
  DateTime() => value.microsecondsSinceEpoch,
  _ => throw ArgumentError.value(
    value,
    'parameter',
    'Unsupported SQLite value.',
  ),
};
