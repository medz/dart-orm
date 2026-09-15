/// PostgreSQL connection pooling with backend-specific configuration.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;

import 'orm.dart';
export 'orm.dart';

part 'src/postgres/temporal.dart';

enum PostgresTls { verifyFull, require, disable }

final class PostgresOptions {
  final Uri url;
  final PostgresTls tls;
  final int maxConnections;
  final Duration connectTimeout;

  /// Driver pool queue limit; separate from opening a new connection.
  final Duration poolTimeout;
  final Duration queryTimeout;
  final String applicationName;
  final String? schema;
  const PostgresOptions({
    required this.url,
    this.tls = PostgresTls.verifyFull,
    this.maxConnections = 8,
    this.connectTimeout = const Duration(seconds: 10),
    this.poolTimeout = const Duration(seconds: 30),
    this.queryTimeout = const Duration(seconds: 30),
    this.applicationName = 'dart-orm',
    this.schema,
  });
}

/// A server-reported error, preserving SQLSTATE and the original exception.
final class PostgresFailure implements SqlFailure {
  final pg.ServerException cause;
  const PostgresFailure(this.cause);
  String? get code => cause.code;
  @override
  bool get retryTransaction => code == '40001' || code == '40P01';
  @override
  bool get retryCommit => false;
  @override
  bool get commitRejected => code?.startsWith('23') == true || retryTransaction;
  @override
  String toString() => cause.toString();
}

final class PostgresDriver implements Driver<Postgres> {
  final pg.Pool<void> _pool;
  final bool _ownsPool;
  final bool _temporal;
  final Future<pg.Connection> Function()? _cancelConnection;
  final Expando<int> _backendIds = Expando();
  final Duration? _queryTimeout;
  final Duration? _connectTimeout;
  bool _closed = false;

  PostgresDriver(PostgresOptions options)
    : _pool = _createPool(options),
      _ownsPool = true,
      _temporal = true,
      _queryTimeout = options.queryTimeout,
      _connectTimeout = options.connectTimeout,
      _cancelConnection = (() => _openControl(options));
  PostgresDriver.borrow(
    pg.Pool<void> pool, {
    Future<pg.Connection> Function()? cancellationConnection,
    this._queryTimeout,
    // Enable only when the pool uses postgresTypeRegistry().
    this._temporal = false,
  }) : _pool = pool,
       _ownsPool = false,
       _connectTimeout = null,
       _cancelConnection = cancellationConnection;

  static Future<pg.Connection> _openControl(PostgresOptions options) {
    final url = options.url, colon = options.url.userInfo.indexOf(':');
    return pg.Connection.open(
      pg.Endpoint(
        host: url.host,
        port: url.hasPort ? url.port : 5432,
        database: url.pathSegments.single,
        username: url.userInfo.isEmpty
            ? null
            : Uri.decodeComponent(
                colon < 0 ? url.userInfo : url.userInfo.substring(0, colon),
              ),
        password: colon < 0
            ? null
            : Uri.decodeComponent(url.userInfo.substring(colon + 1)),
      ),
      settings: pg.ConnectionSettings(
        connectTimeout: options.connectTimeout,
        queryTimeout: const Duration(seconds: 5),
        sslMode: switch (options.tls) {
          PostgresTls.verifyFull => pg.SslMode.verifyFull,
          PostgresTls.require => pg.SslMode.require,
          PostgresTls.disable => pg.SslMode.disable,
        },
        applicationName: '${options.applicationName}/cancel',
      ),
    );
  }

  static pg.Pool<void> _createPool(PostgresOptions options) {
    final url = options.url;
    if (!{'postgres', 'postgresql'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.pathSegments.length != 1 ||
        options.maxConnections < 1) {
      throw ArgumentError('Provide a PostgreSQL URL and a positive pool size.');
    }
    if (options.queryTimeout <= Duration.zero ||
        options.poolTimeout <= Duration.zero ||
        options.connectTimeout <= Duration.zero) {
      throw ArgumentError('PostgreSQL timeouts must be positive.');
    }
    if (url.hasQuery || url.hasFragment) {
      throw ArgumentError(
        'Use typed PostgresOptions instead of URL query options.',
      );
    }
    final colon = url.userInfo.indexOf(':');
    final user = colon < 0 ? url.userInfo : url.userInfo.substring(0, colon);
    final password = colon < 0
        ? null
        : Uri.decodeComponent(url.userInfo.substring(colon + 1));
    return pg.Pool<void>.withEndpoints(
      [
        pg.Endpoint(
          host: url.host,
          port: url.hasPort ? url.port : 5432,
          database: url.pathSegments.single,
          username: user.isEmpty ? null : Uri.decodeComponent(user),
          password: password,
        ),
      ],
      settings: pg.PoolSettings(
        maxConnectionCount: options.maxConnections,
        connectTimeout: options.poolTimeout,
        queryTimeout: null,
        applicationName: options.applicationName,
        timeZone: 'UTC',
        typeRegistry: postgresTypeRegistry(),
        onOpen: options.schema == null
            ? null
            : (connection) async {
                final schema = '"${options.schema!.replaceAll('"', '""')}"';
                await connection.execute(
                  pg.Sql(
                    r"SELECT pg_catalog.set_config('search_path', $1, false)",
                    types: [pg.Type.text],
                  ),
                  parameters: [schema],
                );
              },
        sslMode: switch (options.tls) {
          PostgresTls.verifyFull => pg.SslMode.verifyFull,
          PostgresTls.require => pg.SslMode.require,
          PostgresTls.disable => pg.SslMode.disable,
        },
      ),
    );
  }

  @override
  Capabilities get capabilities => Capabilities(
    dialect: SqlDialect.postgres,
    maxParameters: 65535,
    streaming: true,
    cancellation: _cancelConnection != null,
    exactDecimal: true,
    temporal: _temporal,
  );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) async {
    if (_closed) {
      throw const OrmException('DRIVER.CLOSED', 'PostgreSQL driver is closed.');
    }
    var acquired = false;
    try {
      return await _pool.withConnection(
        (connection) {
          acquired = true;
          return action(
            _PostgresConnection(
              connection,
              _cancelConnection,
              _backendIds,
              _queryTimeout,
            ),
          );
        },
        settings: _connectTimeout == null
            ? null
            : pg.ConnectionSettings(connectTimeout: _connectTimeout),
      );
    } on TimeoutException catch (error) {
      if (acquired) rethrow;
      throw OrmException(
        'CONNECTION.TIMEOUT',
        'PostgreSQL connection acquisition timed out.',
        cause: error,
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsPool) await _pool.close();
  }
}

final class _PostgresConnection implements SqlConnection {
  // package:postgres does not expose ReadyForQuery transaction status publicly.
  @override
  bool? get transactionActive => null;
  final pg.Connection connection;
  final Future<pg.Connection> Function()? _control;
  final Expando<int> _backendIds;
  final Duration? _queryTimeout;
  bool _busy = false;
  int _cursorId = 0;
  _PostgresConnection(
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
    var completed = false, timedOut = false;
    Timer? deadline;
    void Function()? unsubscribe;
    try {
      if (options.cancellation != null || timeout != null) {
        final pid = _backendIds[connection.info] ??=
            (await _query(SqlCommand('SELECT pg_backend_pid()')))
                    .rows
                    .single
                    .single
                as int;
        options.check();
        void cancel() {
          if (completed || cancelling != null) return;
          cancelling = () async {
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
      }
      return await _query(command);
    } on pg.ServerException catch (error) {
      if (error.code == '57014' &&
          (timedOut || options.cancellation?.isCancelled == true)) {
        throw OrmException(
          timedOut ? 'OPERATION.TIMEOUT' : 'OPERATION.CANCELLED',
          'PostgreSQL stopped the statement.',
          cause: error,
        );
      }
      throw PostgresFailure(error);
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
  final _PostgresConnection connection,
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

Database<Postgres> postgres(
  PostgresOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
  void Function(DecodeEvent)? onDecode,
}) => Database(
  PostgresDriver(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
  onDecode: onDecode,
);
