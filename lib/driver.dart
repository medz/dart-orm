/// Raw SQL connections, bound commands, results, and execution controls.
///
/// A [Driver] leases a [SqlConnection] for an awaited callback. [SqlCommand]
/// keeps SQL text separate from values; [SqlResult] exposes raw rows without
/// generated model decoding. [Capabilities] reports the operations the concrete
/// engine and adapter can perform.
///
/// Concrete drivers are available from `package:orm/sqlite.dart`,
/// `package:orm/postgres.dart`, `package:orm/mysql.dart`, and
/// `package:orm/mariadb.dart`. Import `package:orm/sql.dart` when you
/// also need managed sessions and transactions.
///
/// {@category Drivers}
/// {@canonicalFor driver.AcquisitionOptions}
/// {@canonicalFor driver.Backend}
/// {@canonicalFor driver.CancellationToken}
/// {@canonicalFor driver.Capabilities}
/// {@canonicalFor driver.Driver}
/// {@canonicalFor driver.ExecutionOptions}
/// {@canonicalFor driver.SqlCommand}
/// {@canonicalFor driver.SqlConnection}
/// {@canonicalFor driver.SqlCursor}
/// {@canonicalFor driver.SqlDialect}
/// {@canonicalFor driver.SqlFailure}
/// {@canonicalFor driver.SqlResult}
library;

export 'src/driver/driver.dart'
    show
        AcquisitionOptions,
        Backend,
        CancellationToken,
        Capabilities,
        Driver,
        ExecutionOptions,
        SqlCommand,
        SqlConnection,
        SqlCursor,
        SqlDialect,
        SqlFailure,
        SqlResult;
