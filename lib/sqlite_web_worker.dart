/// Entry for compiling a custom dedicated SQLite Web worker.
///
/// Ordinary Dart and Flutter applications use the packaged worker automatically.
/// Custom worker entrypoints call [runSqliteWebWorker] once from `main`.
///
/// {@category Drivers}
/// {@canonicalFor web_worker.runSqliteWebWorker}
library;

export 'src/sqlite/web_worker.dart' show runSqliteWebWorker;
