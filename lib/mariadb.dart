/// Typed MariaDB queries with MariaDB-specific capabilities and history.
///
/// Await [mariadb] to connect and verify the server before using its generated
/// table getters. Each database owns one queued physical connection.
///
/// Use `package:orm/drivers/mariadb.dart` when only a raw driver is needed.
///
/// {@category Databases}
library;

import 'drivers/mariadb.dart';
import 'orm.dart';
export 'drivers/mariadb.dart';
export 'orm.dart';

/// Connects to MariaDB 10.6+ and returns a typed database owning that connection.
///
/// Completes after authentication, engine/version checks and session setup.
/// MySQL servers are rejected. Migration execution has a stricter MariaDB 11.8+
/// requirement, independently checked when applying the fixed migration history.
/// TLS certificates are verified unless [options] selects another policy.
///
/// [onQuery], [onAcquire] and [onDecode] observe runtime operations after opening;
/// they do not include the initial connection handshake. Await [Database.close]
/// when the application owner no longer needs the database. Opening a connection
/// does not generate or apply a schema.
Future<Database<Mariadb>> mariadb(
  MariadbOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
  void Function(DecodeEvent)? onDecode,
}) async => Database(
  await MariadbDriver.open(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
  onDecode: onDecode,
);
