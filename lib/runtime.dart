/// Connection leases, transactions and streaming for parameterized SQL.
///
/// Construct [SqlDatabase] with a driver when an application needs raw SQL
/// without typed queries. The database owns the driver; session and transaction
/// callbacks borrow connections and must not escape their callback lifetimes.
///
/// {@category Execution}
/// {@canonicalFor database.SqlDatabase}
/// {@canonicalFor database.SqlDatabaseStreaming}
/// {@canonicalFor events.QueryOperation}
/// {@canonicalFor events.QueryEvent}
/// {@canonicalFor events.AcquisitionEvent}
/// {@canonicalFor options.TransactionOptions}
/// {@canonicalFor options.Isolation}
/// {@canonicalFor options.PostgresTransaction}
/// {@canonicalFor options.SqliteTransactionMode}
/// {@canonicalFor options.SqliteTransaction}
/// {@canonicalFor options.MysqlTransaction}
/// {@canonicalFor options.MariadbTransaction}
/// {@canonicalFor transaction.TransactionRetry}
library;

export 'driver.dart';
export 'src/runtime/database.dart' show SqlDatabase, SqlDatabaseStreaming;
export 'src/runtime/events.dart'
    show QueryOperation, QueryEvent, AcquisitionEvent;
export 'src/runtime/options.dart'
    show
        TransactionOptions,
        Isolation,
        PostgresTransaction,
        SqliteTransactionMode,
        SqliteTransaction,
        MysqlTransaction,
        MariadbTransaction;
export 'src/runtime/transaction.dart' show TransactionRetry;
