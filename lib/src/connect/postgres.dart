import '../driver/driver.dart' show Postgres;
import '../postgres/driver.dart' show PostgresDriver;
import '../postgres/options.dart' show PostgresOptions;
import '../runtime/database.dart' show SqlDatabase;
import '../runtime/events.dart' show AcquisitionEvent, QueryEvent;

/// Creates an owning SQL runtime with a lazily connected PostgreSQL pool.
///
/// The first operation acquires a connection; construction does not verify server reachability.
/// Closing the returned runtime closes its driver and owned resources. Session
/// and transaction callbacks borrow that runtime. Opening applies no schema.
/// [onQuery] observes SQL execution; [onAcquire] observes connection acquisition.
/// Model decoding observers belong to the optional ORM view.
SqlDatabase<Postgres> postgres(
  PostgresOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
}) => SqlDatabase(
  PostgresDriver(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
);
