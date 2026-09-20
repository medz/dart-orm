/// Project commands configured with ordinary Dart and static migration history.
///
/// Define [OrmConfig] in `orm.config.dart` and pass it to [runOrmCli].
/// Generation works offline; database commands use the explicit connection
/// factory and the database engine fixed by the migration history.
///
/// {@category Tooling}
/// {@canonicalFor config.OrmConfig}
/// {@canonicalFor runner.runOrmCli}
library;

export 'src/cli/config.dart' show OrmConfig;
export 'src/cli/runner.dart' show runOrmCli;
export 'migrate.dart' show MigrationHistory, SchemaRenames, SchemaSnapshot;
export 'migrate_cli.dart' show MigrationConnection;
export 'runtime.dart' show SqlDatabase;
