/// SQLite connections with background execution on native platforms and Web.
///
/// [SqliteOptions.memory] works on both platforms. Persistent databases use a
/// native file path or a named browser database through [SqliteOptions.persistent].
///
/// {@category Drivers}
/// {@canonicalFor driver.SqliteDriver}
/// {@canonicalFor failure.SqliteFailure}
/// {@canonicalFor options.SqliteOptions}
/// {@canonicalFor options.SqliteWebOptions}
/// {@canonicalFor options.SqliteJournal}
// Stable names distinguish raw drivers from ORM entrypoints in Dartdoc.
// ignore: unnecessary_library_name
library drivers_sqlite;

export '../driver.dart';
export '../src/sqlite/driver.dart' show SqliteDriver;
export '../src/sqlite/failure.dart' show SqliteFailure;
export '../src/sqlite/options.dart'
    show SqliteOptions, SqliteWebOptions, SqliteJournal;
