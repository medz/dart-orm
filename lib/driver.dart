/// Raw SQL connections, bound commands, results, and execution controls.
///
/// A [Driver] leases a [SqlConnection] for an awaited callback. [SqlCommand]
/// keeps SQL text separate from values; [SqlResult] exposes raw rows without
/// generated model decoding. [Capabilities] reports the operations the concrete
/// engine and adapter can perform.
///
/// Concrete drivers are available from `package:orm/drivers/sqlite.dart`,
/// `package:orm/drivers/postgres.dart`, `package:orm/drivers/mysql.dart`, and
/// `package:orm/drivers/mariadb.dart`. Import `package:orm/runtime.dart` when you
/// also need managed sessions and transactions.
///
/// {@category Drivers}
/// {@canonicalFor driver.AcquisitionOptions}
/// {@canonicalFor driver.Backend}
/// {@canonicalFor driver.CancellationToken}
/// {@canonicalFor driver.Capabilities}
/// {@canonicalFor driver.Driver}
/// {@canonicalFor driver.ExecutionOptions}
/// {@canonicalFor driver.Mariadb}
/// {@canonicalFor driver.Mysql}
/// {@canonicalFor driver.Postgres}
/// {@canonicalFor driver.SqlCommand}
/// {@canonicalFor driver.SqlConnection}
/// {@canonicalFor driver.SqlCursor}
/// {@canonicalFor driver.SqlDialect}
/// {@canonicalFor driver.SqlFailure}
/// {@canonicalFor driver.SqlResult}
/// {@canonicalFor driver.Sqlite}
library;

export 'values.dart';
export 'src/driver/driver.dart'
    show
        AcquisitionOptions,
        Backend,
        CancellationToken,
        Capabilities,
        Driver,
        ExecutionOptions,
        Mariadb,
        Mysql,
        Postgres,
        SqlCommand,
        SqlConnection,
        SqlCursor,
        SqlDialect,
        SqlFailure,
        SqlResult,
        Sqlite;
