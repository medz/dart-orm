/// Transport encryption and server identity checks for PostgreSQL connections.
enum PostgresTls {
  /// Encrypts traffic and verifies the server certificate and hostname.
  verifyFull,

  /// Encrypts traffic without verifying the server identity.
  require,

  /// Opens an unencrypted connection.
  disable,
}

/// Configuration for an owned PostgreSQL connection pool.
///
/// Connection details belong in [url]; timeouts, TLS, and pool size use the typed
/// options here. URL query parameters and fragments are rejected when opening.
final class PostgresOptions {
  /// A `postgres://` or `postgresql://` URL with one database path segment.
  final Uri url;

  /// Transport policy; server identity verification is enabled by default.
  final PostgresTls tls;

  /// Maximum simultaneous physical connections; must be at least one.
  final int maxConnections;

  /// Deadline for establishing each new physical connection.
  final Duration connectTimeout;

  /// Driver pool queue limit; separate from opening a new connection.
  final Duration poolTimeout;

  /// Default statement deadline, overridable for each execution.
  final Duration queryTimeout;

  /// Label exposed by PostgreSQL in connection and activity diagnostics.
  final String applicationName;

  /// Optional, quoted schema used as the connection search path.
  final String? schema;

  /// Creates pool configuration; opening the driver validates its values.
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
