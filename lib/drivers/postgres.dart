/// PostgreSQL connection pools for raw SQL runtimes and typed ORM sessions.
///
/// [PostgresDriver] owns its pool by default. [PostgresDriver.borrow] uses a
/// caller-owned pool and leaves it open when the driver closes.
///
/// {@category Drivers}
/// {@canonicalFor driver.PostgresDriver}
/// {@canonicalFor failure.PostgresFailure}
/// {@canonicalFor options.PostgresOptions}
/// {@canonicalFor options.PostgresTls}
/// {@canonicalFor temporal.postgresTypeRegistry}
// Stable names distinguish raw drivers from ORM entrypoints in Dartdoc.
// ignore: unnecessary_library_name
library drivers_postgres;

export '../driver.dart';
export '../src/postgres/driver.dart' show PostgresDriver;
export '../src/postgres/failure.dart' show PostgresFailure;
export '../src/postgres/options.dart' show PostgresOptions, PostgresTls;
export '../src/postgres/temporal.dart' show postgresTypeRegistry;
