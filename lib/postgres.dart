/// Typed PostgreSQL queries backed by an owned connection pool.
///
/// [postgres] validates configuration and returns immediately. Physical
/// connections open when an operation acquires a pool lease. Import a generated
/// client to access model-specific table getters.
///
/// Use `package:orm/drivers/postgres.dart` for a raw driver or a borrowed pool.
///
/// {@category Databases}
library;

import 'orm.dart';
import 'drivers/postgres.dart';
export 'orm.dart';
export 'drivers/postgres.dart';

/// Creates a typed database that owns a lazily connected PostgreSQL pool.
///
/// Returns synchronously after validating [options]. A successful return does
/// not prove the server is reachable: authentication, TLS and network failures
/// are reported when an operation first acquires a connection. Execute an
/// explicit query if application startup must verify connectivity.
///
/// [onAcquire] includes pool lease acquisition; [onQuery] and [onDecode] observe
/// runtime SQL and result decoding. Await [Database.close] to close the owned
/// pool. Creating the database does not generate or apply a schema.
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
