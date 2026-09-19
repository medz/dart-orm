/// MySQL and MariaDB connections without ORM or generated model dependencies.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mysql_client_plus/exception.dart' as mysql;
import 'package:mysql_client_plus/mysql_client_plus.dart' as mysql;
import 'package:mysql_client_plus/mysql_protocol.dart' as protocol;

import '../driver.dart';
export '../driver.dart';

part '../src/mysql/connection.dart';
part '../src/mysql/values.dart';

enum MysqlTls {
  /// TLS with certificate and hostname verification.
  verifyFull,

  /// TLS without certificate verification. Use only on a trusted network.
  require,

  /// Unencrypted transport. The client requires TLS for SHA-2 authentication.
  disable,
}

class MysqlOptions {
  final Uri url;
  final MysqlTls tls;
  final Duration connectTimeout;
  final Duration queryTimeout;
  final SecurityContext? securityContext;

  const MysqlOptions({
    required this.url,
    this.tls = MysqlTls.verifyFull,
    this.connectTimeout = const Duration(seconds: 10),
    this.queryTimeout = const Duration(seconds: 30),
    this.securityContext,
  });
}

final class MariadbOptions extends MysqlOptions {
  const MariadbOptions({
    required super.url,
    super.tls,
    super.connectTimeout,
    super.queryTimeout,
    super.securityContext,
  });
}

/// A server-reported error. Numeric codes are preserved; SQLSTATE is not
/// exposed by mysql_client_plus and is not guessed from the error message.
final class MysqlFailure implements SqlFailure {
  final mysql.MySQLServerException cause;
  const MysqlFailure(this.cause);

  int get code => cause.errorCode;
  @override
  bool get retryTransaction => code == 1213 || code == 1205;
  @override
  bool get retryCommit => false;
  @override
  bool get commitRejected => code == 1213;
  @override
  String toString() => 'MysqlFailure($code): ${cause.message}';
}

/// One physical connection. Whole leases are queued, including transactions.
/// Create additional drivers explicitly when independent concurrent leases are
/// required. Closing drains all leases accepted before close was called.
final class MysqlDriver extends _MysqlDriver<Mysql> {
  MysqlDriver._(
    mysql.MySQLConnection connection,
    MysqlOptions options,
    String serverVersion,
  ) : super(connection, options, serverVersion, SqlDialect.mysql);

  static Future<MysqlDriver> open(MysqlOptions options) async {
    final opened = await _openMysql(options, SqlDialect.mysql);
    return MysqlDriver._(opened.connection, options, opened.version);
  }
}

final class MariadbDriver extends _MysqlDriver<Mariadb> {
  MariadbDriver._(
    mysql.MySQLConnection connection,
    MariadbOptions options,
    String serverVersion,
  ) : super(connection, options, serverVersion, SqlDialect.mariadb);

  static Future<MariadbDriver> open(MariadbOptions options) async {
    final opened = await _openMysql(options, SqlDialect.mariadb);
    return MariadbDriver._(opened.connection, options, opened.version);
  }
}

abstract class _MysqlDriver<B extends Backend> implements Driver<B> {
  final mysql.MySQLConnection _connection;
  final MysqlOptions _options;
  final SqlDialect _dialect;
  final String serverVersion;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool _discarded = false;

  _MysqlDriver(
    this._connection,
    this._options,
    this.serverVersion,
    this._dialect,
  );

  @override
  Capabilities get capabilities => Capabilities(
    dialect: _dialect,
    maxParameters: 65535,
    returning: false,
    streaming: false,
    cancellation: false,
    statementTimeout: true,
    exactDecimal: true,
    temporal: true,
  );

  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) {
    if (_closing != null) {
      return Future.error(
        const OrmException(
          'DRIVER.CLOSED',
          'MySQL driver is closing or closed.',
        ),
      );
    }
    final result = _tail.then((_) async {
      if (_discarded || !_connection.connected) {
        throw const OrmException(
          'DRIVER.CLOSED',
          'MySQL connection has been discarded. Open a new driver.',
        );
      }
      final lease = _MysqlConnection(_connection, _options.queryTimeout);
      try {
        final result = await action(lease);
        await lease._release();
        return result;
      } catch (error, stack) {
        try {
          await lease._release();
        } catch (_) {
          await lease.invalidate();
        }
        Error.throwWithStackTrace(error, stack);
      } finally {
        if (lease._invalid) _discarded = true;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> close() => _closing ??= _tail.then((_) async {
    if (!_discarded && _connection.connected) {
      try {
        await _connection.close().timeout(_options.queryTimeout);
      } catch (_) {
        _connection.getSocket().destroy();
        rethrow;
      }
    } else {
      _connection.getSocket().destroy();
    }
  });
}

Future<({mysql.MySQLConnection connection, String version})> _openMysql(
  MysqlOptions options,
  SqlDialect dialect,
) async {
  final url = options.url;
  final schemes = dialect == SqlDialect.mysql
      ? const {'mysql'}
      : const {'mariadb', 'mysql'};
  if (!schemes.contains(url.scheme) ||
      url.host.isEmpty ||
      url.pathSegments.length != 1 ||
      url.pathSegments.single.isEmpty ||
      url.hasPort && (url.port < 1 || url.port > 65535) ||
      url.hasQuery ||
      url.hasFragment ||
      url.userInfo.isEmpty ||
      options.connectTimeout <= Duration.zero ||
      options.queryTimeout <= Duration.zero) {
    throw ArgumentError(
      'Provide a ${dialect.name} URL with user and database, positive timeouts, '
      'and typed options instead of URL query parameters.',
    );
  }
  final colon = url.userInfo.indexOf(':');
  final username = Uri.decodeComponent(
    colon < 0 ? url.userInfo : url.userInfo.substring(0, colon),
  );
  final password = colon < 0
      ? ''
      : Uri.decodeComponent(url.userInfo.substring(colon + 1));
  if (username.isEmpty) throw ArgumentError('MySQL user must not be empty.');
  mysql.MySQLConnection? connection;
  var expired = false;
  try {
    return await (() async {
      final opened = await mysql.MySQLConnection.createConnection(
        host: url.host,
        port: url.hasPort ? url.port : 3306,
        userName: username,
        password: password,
        databaseName: url.pathSegments.single,
        secure: options.tls != MysqlTls.disable,
        securityContext: options.securityContext,
        // The upstream client's default accepts invalid certificates.
        onBadCertificate: (_) => options.tls == MysqlTls.require,
      );
      connection = opened;
      if (expired) {
        opened.getSocket().destroy();
        throw const OrmException('CONNECTION.TIMEOUT', 'Connection timed out.');
      }
      await opened.connect(
        timeoutMs: options.connectTimeout.inMilliseconds
            .clamp(1, 2147483647)
            .toInt(),
      );
      final result = await opened.execute('SELECT VERSION()');
      final version = result.rows.single.colAt(0) as String;
      final maria = version.toLowerCase().contains('mariadb');
      if (maria != (dialect == SqlDialect.mariadb)) {
        throw OrmException(
          'DRIVER.ENGINE',
          'Expected ${dialect.name}, but the server reports $version.',
        );
      }
      final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(version);
      final major = match == null ? 0 : int.parse(match[1]!);
      final minor = match == null ? 0 : int.parse(match[2]!);
      if (maria
          ? major < 10 || major == 10 && minor < 6
          : major < 8 || major == 8 && minor < 4) {
        throw const OrmException(
          'DRIVER.VERSION',
          'MySQL 8.4+ or MariaDB 10.6+ is required.',
        );
      }
      // Do not silently coerce invalid dates, truncate values, or convert
      // instants through the deployment host's time zone.
      await opened.execute("SET SESSION time_zone = '+00:00'");
      await opened.execute(
        "SET SESSION sql_mode = CONCAT_WS(',', NULLIF(@@SESSION.sql_mode, ''), "
        "'ANSI_QUOTES', 'NO_BACKSLASH_ESCAPES', 'STRICT_ALL_TABLES', "
        "'NO_ZERO_DATE', 'NO_ZERO_IN_DATE', 'ERROR_FOR_DIVISION_BY_ZERO', "
        "'NO_ENGINE_SUBSTITUTION')",
      );
      await opened.execute('SET SESSION autocommit = 1');
      return (connection: opened, version: version);
    })().timeout(options.connectTimeout);
  } on TimeoutException catch (error) {
    expired = true;
    connection?.getSocket().destroy();
    throw OrmException(
      'CONNECTION.TIMEOUT',
      'MySQL connection establishment timed out.',
      cause: error,
    );
  } catch (_) {
    expired = true;
    connection?.getSocket().destroy();
    rethrow;
  }
}
