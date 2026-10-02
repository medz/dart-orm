/// Sqlite connections for SQL execution and optional typed model views.
///
/// [sqlite] opens an owning SQL runtime. Import `package:orm/sql.dart` for
/// SQL operations, and `package:orm/orm.dart` to add a model view of that runtime.
/// [SqliteDriver] remains available for explicit driver ownership and leasing.
///
/// {@category Databases}
/// {@canonicalFor driver.SqliteDriver}
/// {@canonicalFor failure.SqliteFailure}
/// {@canonicalFor options.SqliteOptions}
/// {@canonicalFor options.SqliteWebOptions}
/// {@canonicalFor options.SqliteJournal}
/// {@canonicalFor driver.Sqlite}
/// {@canonicalFor sqlite.sqlite}
library;

export 'src/connect/sqlite.dart' show sqlite;
export 'src/driver/driver.dart' show Sqlite;
export 'src/sqlite/driver.dart' show SqliteDriver;
export 'src/sqlite/failure.dart' show SqliteFailure;
export 'src/sqlite/options.dart'
    show SqliteOptions, SqliteWebOptions, SqliteJournal;
