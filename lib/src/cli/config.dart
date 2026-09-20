import '../../migrate.dart';
import '../../migrate_cli.dart';

/// Project paths, frozen migration history and database connection ownership.
///
/// Pass this configuration to the project CLI. The history fixes one database
/// engine; changing a connection URL does not translate migrations.
final class OrmConfig {
  /// Source declaration read by generation and migration creation.
  final String schema;

  /// Generated client path, or the schema basename with `.orm.dart` when null.
  final String? output;

  /// Directory containing reviewed migration files and their static registry.
  final String migrations;

  /// Statically imported migrations and their reviewed fingerprints.
  final MigrationHistory history;

  /// Desired physical schema used by inspection and migration commands.
  ///
  /// Migration creation regenerates the declaration before computing its diff.
  final SchemaSnapshot snapshot;

  /// Connection factory for commands that inspect or change a database.
  ///
  /// Offline generation, history validation and recording never call it.
  final MigrationConnection? connect;

  /// Explicit table and column renames applied when creating a migration.
  final SchemaRenames renames;

  /// Table and column conversion expressions for reviewed type changes.
  final Map<String, Map<String, String>> using;

  /// Configures a project without opening a database or executing a migration.
  const OrmConfig({
    this.schema = 'lib/schema.dart',
    this.output,
    this.migrations = 'migrations',
    required this.history,
    required this.snapshot,
    this.connect,
    this.renames = const SchemaRenames(),
    this.using = const {},
  });
}
