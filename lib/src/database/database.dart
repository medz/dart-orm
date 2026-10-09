import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'contracts.dart';

/// Takes ownership of [driver] and creates an explicit database scope.
///
/// Call [Database.close] to release its resources. The root session may execute
/// independent statements; inside a transaction callback use its supplied
/// session. Nested transactions and manually issued transaction boundaries are
/// rejected. SQLite supports only serializable transactions, including read-only
/// transactions enforced by a scoped `query_only` setting.
/// PostgreSQL supports every [Isolation] and read-only transactions.
/// The driver's schema is captured once; typed queries use that fixed schema
/// regardless of temporary objects or later PostgreSQL search_path changes.
/// Invalid driver schemas throw before acquisition; the caller retains ownership
/// of a driver when opening fails.
///
/// Every completed SQL operation emits a `statement`, `begin`, `commit` or
/// `rollback` event. Failed operations append `Error` to that kind. Observer
/// exceptions are ignored so instrumentation cannot change database outcomes.
/// Events expose SQL text, never bound parameters. Avoid literal secrets in SQL.
Database openDatabase(Driver driver, {DatabaseObserver? observer}) =>
    _Database(driver, observer);

final class _Database implements Database {
  _Database(this.driver, this.observer) : schema = driver.schema {
    if (schema.isEmpty ||
        schema.contains('\u0000') ||
        (driver.engine == Engine.sqlite && schema != 'main') ||
        (driver.engine == Engine.postgresql &&
            (utf8.encode(schema).length > 63 || schema.startsWith('pg_')))) {
      throw ArgumentError.value(schema, 'schema', 'Invalid managed schema.');
    }
    session = _RootSession(this);
  }

  final Driver driver;
  final DatabaseObserver? observer;
  final String schema;
  final Object _transactionZone = Object();
  @override
  late final Session session;
  bool _closing = false;
  int _active = 0;
  int _nextTransactionId = 0;
  Completer<void>? _idle;
  Future<void>? _closeFuture;

  void _admit() {
    if (_closing) throw StateError('The database is closing or closed.');
    _active++;
  }

  void _release() {
    _active--;
    if (_active == 0) {
      _idle?.complete();
      _idle = null;
    }
  }

  void _outsideTransaction() {
    if (Zone.current[_transactionZone] != null) {
      throw StateError('Use the transaction callback session in this scope.');
    }
  }

  Future<QueryResult> _run(
    Connection connection,
    String sql,
    List<Object?> parameters, {
    String kind = 'statement',
    int? transactionId,
  }) async {
    final watch = Stopwatch()..start();
    QueryResult? result;
    var eventKind = kind;
    try {
      result = await connection.run(sql, parameters);
      return result;
    } catch (_) {
      eventKind = '${kind}Error';
      rethrow;
    } finally {
      watch.stop();
      try {
        observer?.call(
          DatabaseEvent(
            kind: eventKind,
            sql: sql,
            elapsed: watch.elapsed,
            rows: result == null
                ? 0
                : result.rows.isEmpty
                ? result.affectedRows
                : result.rows.length,
            transactionId: transactionId,
          ),
        );
      } catch (_) {
        // A notification cannot undo SQL or make a successful write retryable.
      }
    }
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Session session) action, {
    Isolation isolation = Isolation.serializable,
    bool readOnly = false,
  }) async {
    _outsideTransaction();
    if (driver.engine == Engine.sqlite) {
      if (isolation != Isolation.serializable) {
        throw UnsupportedError('SQLite supports serializable isolation only.');
      }
    }
    _admit();
    try {
      return await driver.withConnection((connection) async {
        final id = ++_nextTransactionId;
        var restoreQueryOnly = false;
        if (driver.engine == Engine.sqlite && readOnly) {
          final state = await _run(connection, 'PRAGMA query_only', const []);
          restoreQueryOnly = state.rows.single.single == 0;
          if (restoreQueryOnly) {
            await _run(connection, 'PRAGMA query_only = ON', const []);
          }
        }
        try {
          final begin = switch (driver.engine) {
            Engine.sqlite => readOnly ? 'BEGIN' : 'BEGIN IMMEDIATE',
            Engine.postgresql =>
              'BEGIN ISOLATION LEVEL ${switch (isolation) {
                Isolation.readCommitted => 'READ COMMITTED',
                Isolation.repeatableRead => 'REPEATABLE READ',
                Isolation.serializable => 'SERIALIZABLE',
              }} ${readOnly ? 'READ ONLY' : 'READ WRITE'}',
          };
          await _run(
            connection,
            begin,
            const [],
            kind: 'begin',
            transactionId: id,
          );
          final scope = _TransactionSession(this, connection, id);
          try {
            final value = await runZoned(
              () => action(scope),
              zoneValues: {_transactionZone: scope},
            );
            await scope._finish();
            await _run(
              connection,
              'COMMIT',
              const [],
              kind: 'commit',
              transactionId: id,
            );
            return value;
          } catch (error, stack) {
            await scope._finish(ignoreFailure: true);
            try {
              await _run(
                connection,
                'ROLLBACK',
                const [],
                kind: 'rollback',
                transactionId: id,
              );
            } catch (_) {
              // Preserve the cause; the driver disposes failed pooled connections.
            }
            Error.throwWithStackTrace(error, stack);
          }
        } finally {
          if (restoreQueryOnly) {
            await _run(connection, 'PRAGMA query_only = OFF', const []);
          }
        }
      });
    } finally {
      _release();
    }
  }

  @override
  Future<void> close() {
    _outsideTransaction();
    if (_closeFuture case final future?) return future;
    _closing = true;
    return _closeFuture = _close();
  }

  Future<void> _close() async {
    if (_active != 0) {
      _idle = Completer<void>();
      await _idle!.future;
    }
    await driver.close();
  }
}

final class _RootSession implements Session {
  _RootSession(this.database);
  final _Database database;
  @override
  Engine get engine => database.driver.engine;
  @override
  String get schema => database.schema;
  @override
  Capabilities get capabilities => database.driver.capabilities;
  @override
  bool get inTransaction => false;

  @override
  Future<QueryResult> run(
    String sql, {
    List<Object?> parameters = const [],
  }) async {
    database._outsideTransaction();
    _validateStatement(sql, parameters, capabilities, engine);
    final values = _snapshotParameters(parameters);
    database._admit();
    try {
      return await database.driver.withConnection(
        (connection) => database._run(connection, sql, values),
      );
    } finally {
      database._release();
    }
  }
}

final class _TransactionSession implements Session {
  _TransactionSession(this.database, this.connection, this.id);
  final _Database database;
  final Connection connection;
  final int id;
  bool _active = true;
  Future<void> _tail = Future.value();
  (Object, StackTrace)? _failure;
  @override
  Engine get engine => database.driver.engine;
  @override
  String get schema => database.schema;
  @override
  Capabilities get capabilities => database.driver.capabilities;
  @override
  bool get inTransaction => true;

  @override
  Future<QueryResult> run(String sql, {List<Object?> parameters = const []}) {
    if (!_active) {
      return Future.error(StateError('The transaction session has expired.'));
    }
    try {
      _validateStatement(sql, parameters, capabilities, engine);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final values = _snapshotParameters(parameters);
    final result = _tail.then(
      (_) => database._run(connection, sql, values, transactionId: id),
    );
    // Observe every error before exposing the future, including unawaited work.
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
    if (!ignoreFailure) {
      if (_failure case final failure?) {
        Error.throwWithStackTrace(failure.$1, failure.$2);
      }
    }
  }
}

List<Object?> _snapshotParameters(List<Object?> parameters) => [
  for (final value in parameters)
    value is Uint8List ? Uint8List.fromList(value) : value,
];

void _validateStatement(
  String sql,
  List<Object?> parameters,
  Capabilities capabilities,
  Engine engine,
) {
  if (parameters.length > capabilities.maxParameters) {
    throw ArgumentError('The statement exceeds the driver parameter limit.');
  }
  final words = _statementWords(sql);
  final command = words.firstOrNull;
  if (command == null) throw ArgumentError.value(sql, 'sql', 'Expected SQL.');
  if (engine == Engine.sqlite &&
      command == 'PRAGMA' &&
      RegExp(r'\bquery_only\b', caseSensitive: false).hasMatch(sql)) {
    throw ArgumentError('The runtime owns SQLite query_only configuration.');
  }
  if (engine == Engine.postgresql && (command == 'SET' || command == 'RESET')) {
    final options = words.skip(1).toList();
    if (command == 'SET' &&
        (options.firstOrNull == 'LOCAL' || options.firstOrNull == 'SESSION')) {
      options.removeAt(0);
    }
    if (const {
          'TRANSACTION',
          'TRANSACTION_ISOLATION',
          'TRANSACTION_READ_ONLY',
          'DEFAULT_TRANSACTION_ISOLATION',
          'DEFAULT_TRANSACTION_READ_ONLY',
        }.contains(options.firstOrNull) ||
        (command == 'RESET' && options.firstOrNull == 'ALL') ||
        (command == 'SET' &&
            options.firstOrNull == 'CHARACTERISTICS' &&
            options.contains('TRANSACTION'))) {
      throw ArgumentError('Use Database.transaction for transaction options.');
    }
  }
  if (const {
        'BEGIN',
        'START',
        'COMMIT',
        'END',
        'ROLLBACK',
        'SAVEPOINT',
        'RELEASE',
        'ABORT',
      }.contains(command) ||
      (engine == Engine.postgresql &&
          command == 'PREPARE' &&
          words.elementAtOrNull(1) == 'TRANSACTION')) {
    throw ArgumentError('Use Database.transaction for transaction boundaries.');
  }
}

// Read only the command prefix; comments and quoted identifiers cannot conceal
// a SET/RESET transaction option. String values end the prefix.
List<String> _statementWords(String sql) {
  final words = <String>[];
  var offset = 0;
  while (offset < sql.length && words.length < 7) {
    final character = sql[offset];
    if (RegExp(r'\s').hasMatch(character)) {
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
    } else if (character == '"') {
      final end = sql.indexOf('"', offset + 1);
      if (end < 0) break;
      words.add(sql.substring(offset + 1, end).toUpperCase());
      offset = end + 1;
    } else if (RegExp(r'[A-Za-z_]').hasMatch(character)) {
      final match = RegExp(r'[A-Za-z_]+').matchAsPrefix(sql, offset)!;
      words.add(match.group(0)!.toUpperCase());
      offset = match.end;
    } else {
      break;
    }
  }
  return words;
}
