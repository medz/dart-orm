/// Runnable project configuration without generated-source imports.
///
/// In `orm.config.dart`, call [defineConfig] from a parameterless `void main()`.
/// Then run `dart run orm generate` or `dart run orm migrate <command>`.
/// Select another entrypoint with `--config path/to/orm.config.dart`; that path
/// is relative to the command's working directory. Model, output and migration
/// paths in the configuration are relative to its own directory.
///
/// Generation works without a generated client, snapshot or migration registry.
/// Migration commands load and validate the selected static history on demand.
/// Database commands use [MigrationConnection] and close the returned runtime.
/// Registration may be evaluated twice to compile that history; keep I/O inside
/// the connection factory. Deploy frozen history through `migrate_cli.dart` when
/// a standalone, ahead-of-time compiled migration executable is needed.
///
/// {@category Tooling}
/// {@canonicalFor config.defineConfig}
library;

export 'driver.dart' show SqlDialect;
export 'migrate.dart' show SchemaRenames;
export 'runtime.dart' show SqlDatabase;
export 'src/cli/config.dart' show defineConfig;
