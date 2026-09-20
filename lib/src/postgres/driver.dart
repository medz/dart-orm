import 'dart:async';

import 'package:postgres/postgres.dart' as pg;

import '../../driver.dart';
import 'connection.dart';
import 'options.dart';
import 'temporal.dart';

/// Owns or borrows a PostgreSQL pool and leases one connection per callback.
///
/// Owned pools configure exact temporal codecs and cancellation connections.
/// A borrowed pool enables these capabilities only when explicitly configured.
final class PostgresDriver implements Driver<Postgres> {
  final pg.Pool<void> _pool;
  final bool _ownsPool;
  final bool _temporal;
  final Future<pg.Connection> Function()? _cancelConnection;
  final Expando<int> _backendIds = Expando();
  final Duration? _queryTimeout;
  final Duration? _connectTimeout;
  bool _closed = false;

  /// Creates an owned pool; physical connections open as leases are acquired.
  PostgresDriver(PostgresOptions options)
    : _pool = _createPool(options),
      _ownsPool = true,
      _temporal = true,
      _queryTimeout = options.queryTimeout,
      _connectTimeout = options.connectTimeout,
      _cancelConnection = (() => _openControl(options));

  /// Uses a caller-owned pool, which remains open when this driver closes.
  ///
  /// Supply [cancellationConnection] to support statement cancellation. Enable
  /// `temporal` only if the pool was created with [postgresTypeRegistry].
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

  /// Leases a pooled connection for the lifetime of the callback future.
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
            PostgresConnection(
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

  /// Rejects new leases and closes the pool only when this driver owns it.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsPool) await _pool.close();
  }
}
