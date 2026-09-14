/// PostgreSQL connection pooling with backend-specific configuration.
library;

import 'package:postgres/postgres.dart' as pg;

import 'orm.dart';
export 'orm.dart';

enum PostgresTls { verifyFull, require, disable }

final class PostgresOptions {
  final Uri url;
  final PostgresTls tls;
  final int maxConnections;
  final Duration connectTimeout;
  final Duration queryTimeout;
  final String applicationName;
  const PostgresOptions({
    required this.url,
    this.tls = PostgresTls.verifyFull,
    this.maxConnections = 8,
    this.connectTimeout = const Duration(seconds: 10),
    this.queryTimeout = const Duration(seconds: 30),
    this.applicationName = 'dart-orm',
  });
}

final class PostgresDriver implements Driver<Postgres> {
  final pg.Pool<void> _pool;
  final bool _ownsPool;
  bool _closed = false;

  PostgresDriver(PostgresOptions options)
    : _pool = _createPool(options),
      _ownsPool = true;
  PostgresDriver.borrow(pg.Pool<void> pool) : _pool = pool, _ownsPool = false;

  static pg.Pool<void> _createPool(PostgresOptions options) {
    final url = options.url;
    if (!{'postgres', 'postgresql'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.pathSegments.length != 1 ||
        options.maxConnections < 1) {
      throw ArgumentError('Provide a PostgreSQL URL and a positive pool size.');
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
        connectTimeout: options.connectTimeout,
        queryTimeout: options.queryTimeout,
        applicationName: options.applicationName,
        timeZone: 'UTC',
        sslMode: switch (options.tls) {
          PostgresTls.verifyFull => pg.SslMode.verifyFull,
          PostgresTls.require => pg.SslMode.require,
          PostgresTls.disable => pg.SslMode.disable,
        },
      ),
    );
  }

  @override
  Capabilities get capabilities =>
      const Capabilities(dialect: SqlDialect.postgres, maxParameters: 65535);
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) {
    if (_closed)
      throw const OrmException('DRIVER.CLOSED', 'PostgreSQL driver is closed.');
    return _pool.withConnection(
      (connection) => action(_PostgresConnection(connection)),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_ownsPool) await _pool.close();
  }
}

final class _PostgresConnection(final pg.Connection connection)
    implements SqlConnection {
  @override
  Future<SqlResult> execute(SqlCommand command) async {
    final result = await connection.execute(
      pg.Sql(
        command.sql,
        types: List.filled(command.parameters.length, pg.Type.unspecified),
      ),
      parameters: command.parameters,
    );
    return SqlResult(
      result,
      columns: [for (final c in result.schema.columns) c.columnName ?? ''],
      affectedRows: result.affectedRows,
    );
  }

  @override
  Future<void> invalidate() => connection.close(force: true);
}

Database<Postgres> postgres(
  PostgresOptions options, {
  void Function(QueryEvent)? onQuery,
}) => Database(PostgresDriver(options), onQuery: onQuery);
