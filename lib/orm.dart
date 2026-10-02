/// Optional typed model views and query change subscriptions.
///
/// Add [Database.fromSql] to an existing SQL runtime opened through an engine
/// entrypoint such as `package:orm/sqlite.dart`. Generated clients add typed
/// table getters to that view and its borrowed transaction sessions.
///
/// Import `package:orm/sql.dart` for query expressions and SQL execution. Model
/// declarations and migration tools have their own explicit entrypoints.
///
/// {@category Databases}
/// {@canonicalFor database.Database}
/// {@canonicalFor observation.DecodeEvent}
/// {@canonicalFor watch.WatchQuery}
/// {@canonicalFor watch.WatchSql}
/// {@canonicalFor model_query.Write}
/// {@canonicalFor model_query.WriteRows}
/// {@canonicalFor model_query.InsertWrite}
/// {@canonicalFor model_query.BatchWrite}
/// {@canonicalFor model_query.ModelQuery}
/// {@canonicalFor model_query.ModelTable}
/// {@canonicalFor model_query.ModelWritePlan}
/// {@canonicalFor model_query.ModelTableWritePlan}
library;

export 'src/orm/database.dart' show Database;
export 'src/orm/observation.dart' show DecodeEvent;
export 'src/orm/watch.dart' show WatchQuery, WatchSql;

export 'src/orm/model_query.dart'
    show
        Write,
        WriteRows,
        InsertWrite,
        BatchWrite,
        ModelQuery,
        ModelTable,
        ModelWritePlan,
        ModelTableWritePlan;
