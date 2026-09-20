/// Typed MySQL queries with explicit connection and transaction ownership.
///
/// Await [mysql] to connect and verify the server before using its generated
/// table getters. Each database owns one queued physical connection. MySQL and
/// MariaDB have distinct engine identities and migration histories.
///
/// Use `package:orm/drivers/mysql.dart` when only a raw driver is needed.
///
/// {@category Databases}
library;

import 'drivers/mysql.dart';
import 'orm.dart';
export 'drivers/mysql.dart';
export 'orm.dart';

/// Connects to MySQL 8.4+ and returns a typed database owning that connection.
///
/// Completes after authentication, engine/version checks and session setup.
/// MariaDB servers are rejected; use their separate entrypoint. TLS certificates
/// are verified unless [options] explicitly selects another policy.
///
/// [onQuery], [onAcquire] and [onDecode] observe runtime operations after opening;
/// they do not include the initial connection handshake. Await [Database.close]
/// when the application owner no longer needs the database. Opening a connection
/// does not generate or apply a schema.
Future<Database<Mysql>> mysql(
  MysqlOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
  void Function(DecodeEvent)? onDecode,
}) async => Database(
  await MysqlDriver.open(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
  onDecode: onDecode,
);
