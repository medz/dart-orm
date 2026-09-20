import 'dart:io';

/// Transport encryption and server identity checks for MySQL and MariaDB.
enum MysqlTls {
  /// TLS with certificate and hostname verification.
  verifyFull,

  /// TLS without certificate verification. Use only on a trusted network.
  require,

  /// Unencrypted transport. The client requires TLS for SHA-2 authentication.
  disable,
}

/// Configuration for one owned MySQL connection.
///
/// The driver queues complete connection leases and configures UTC, strict SQL
/// modes, and autocommit. Additional drivers provide independent concurrency.
class MysqlOptions {
  /// A database URL with one database path segment and no query or fragment.
  final Uri url;

  /// Transport policy; certificate verification is enabled by default.
  final MysqlTls tls;

  /// Deadline for opening and configuring the connection.
  final Duration connectTimeout;

  /// Default statement deadline, overridable for each execution.
  ///
  /// Expiry discards the connection; the server-side outcome may be unknown.
  final Duration queryTimeout;

  /// Optional trust roots or client credentials for TLS.
  final SecurityContext? securityContext;

  /// Creates connection configuration; the driver validates it when opened.
  const MysqlOptions({
    required this.url,
    this.tls = MysqlTls.verifyFull,
    this.connectTimeout = const Duration(seconds: 10),
    this.queryTimeout = const Duration(seconds: 30),
    this.securityContext,
  });
}

/// MariaDB configuration with engine identity checked during connection setup.
final class MariadbOptions extends MysqlOptions {
  /// Creates options for an owned MariaDB connection.
  const MariadbOptions({
    required super.url,
    super.tls,
    super.connectTimeout,
    super.queryTimeout,
    super.securityContext,
  });
}
