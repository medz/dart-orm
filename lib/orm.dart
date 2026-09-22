/// Typed queries, explicit transactions and change subscriptions.
///
/// Import a database entrypoint such as `package:orm/sqlite.dart` to open a
/// connection and use this API. [Database] also accepts an independently created
/// driver. Generated clients add typed table getters to each database/session.
///
/// Use [SqlBuilder] to compile queries without connecting, and [SqlDatabase] for
/// raw SQL execution. Schema declarations and migration tools have separate
/// entrypoints so application code need not import development tooling.
///
/// {@category Databases}
/// {@canonicalFor database.Database}
/// {@canonicalFor observation.DecodeEvent}
/// {@canonicalFor watch.WatchQuery}
/// {@canonicalFor watch.WatchSql}
/// {@canonicalFor sql_check.SqlCheck}
/// {@canonicalFor sql_check.checkSqlQuery}
library;

export 'sql.dart';
export 'runtime.dart';
export 'src/orm/database.dart' show Database;
export 'src/orm/observation.dart' show DecodeEvent;
export 'src/orm/watch.dart' show WatchQuery, WatchSql;
export 'src/orm/sql_check.dart' show SqlCheck, checkSqlQuery;
