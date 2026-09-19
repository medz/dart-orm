/// PostgreSQL ORM convenience entrypoint. Raw SQL drivers are in drivers/postgres.dart.
library;

import 'orm.dart';
import 'drivers/postgres.dart';
export 'orm.dart';
export 'drivers/postgres.dart';

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
