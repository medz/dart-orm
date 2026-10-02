/// Postgres connections for SQL execution and optional typed model views.
///
/// [postgres] opens an owning SQL runtime. Import `package:orm/sql.dart` for
/// SQL operations, and `package:orm/orm.dart` to add a model view of that runtime.
/// [PostgresDriver] remains available for explicit driver ownership and leasing.
///
/// {@category Databases}
/// {@canonicalFor driver.PostgresDriver}
/// {@canonicalFor failure.PostgresFailure}
/// {@canonicalFor options.PostgresOptions}
/// {@canonicalFor options.PostgresTls}
/// {@canonicalFor temporal.postgresTypeRegistry}
/// {@canonicalFor driver.Postgres}
/// {@canonicalFor postgres.postgres}
library;

export 'src/connect/postgres.dart' show postgres;
export 'src/driver/driver.dart' show Postgres;
export 'src/postgres/driver.dart' show PostgresDriver;
export 'src/postgres/failure.dart' show PostgresFailure;
export 'src/postgres/options.dart' show PostgresOptions, PostgresTls;
export 'src/postgres/temporal.dart' show postgresTypeRegistry;
