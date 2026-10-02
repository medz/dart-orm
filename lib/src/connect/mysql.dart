import '../driver/driver.dart' show Mysql;
import '../mysql/driver.dart' show MysqlDriver;
import '../mysql/options.dart' show MysqlOptions;
import '../runtime/database.dart' show SqlDatabase;
import '../runtime/events.dart' show AcquisitionEvent, QueryEvent;

/// Opens a connection and returns its owning SQL runtime.
///
/// Completion confirms that the driver and storage have initialized.
/// Closing the returned runtime closes its driver and owned resources. Session
/// and transaction callbacks borrow that runtime. Opening applies no schema.
/// [onQuery] observes SQL execution; [onAcquire] observes connection acquisition.
/// Model decoding observers belong to the optional ORM view.
Future<SqlDatabase<Mysql>> mysql(
  MysqlOptions options, {
  void Function(QueryEvent)? onQuery,
  void Function(AcquisitionEvent)? onAcquire,
}) async => SqlDatabase(
  await MysqlDriver.open(options),
  onQuery: onQuery,
  onAcquire: onAcquire,
);
