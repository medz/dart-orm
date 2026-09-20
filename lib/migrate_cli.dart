/// Migration commands for a project-owned Dart executable.
///
/// Pass a statically imported history to [runMigrationCli]. Database commands
/// obtain their connection from [MigrationConnection]; inspection requests a
/// read-only connection where the selected database supports it.
///
/// {@category Tooling}
/// {@canonicalFor migration.MigrationConnection}
/// {@canonicalFor migration.runMigrationCli}
library;

export 'src/cli/migration.dart' show MigrationConnection, runMigrationCli;
