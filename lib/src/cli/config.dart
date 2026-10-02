import '../driver/driver.dart';
import '../migrate/diff.dart';
import 'config_entrypoint.dart';
import 'migration.dart' show MigrationConnection;

/// Registers the project's models, paths and explicit connection factory.
///
/// Call once from `void main()` in `orm.config.dart`, then use `dart run orm`.
/// [models], [output] and [migrations] are resolved relative to that file. A model
/// source may be a Dart file or a recursively discovered directory; folder names
/// never select database namespaces. [defaultNamespace] is the PostgreSQL
/// fallback for models without an explicit namespace.
///
/// No generated source or migration registry is imported by the configuration.
/// Generation and migration creation are offline. Database commands obtain and
/// close their own connection through [connect]; the factory must honor its
/// `readOnly` argument. The selected [database] must match the frozen history.
/// [renames] and [using] are explicit, reviewed hints for migration creation.
///
/// Keep registration free of side effects: migration commands may evaluate the
/// entrypoint again when compiling the static history. Connection setup belongs
/// inside [connect], never in `main`. Connection-specific paths inside that
/// callback follow the application's own rules and are not rewritten by the CLI.
///
/// Throws [FormatException] for empty paths, repeated registration or when called
/// outside a configuration entrypoint loaded by the package CLI.
void defineConfig({
  required SqlDialect database,
  String models = 'lib/models.dart',
  String? output,
  String migrations = 'migrations',
  String? defaultNamespace,
  MigrationConnection? connect,
  SchemaRenames renames = const SchemaRenames(),
  Map<String, Map<String, String>> using = const {},
}) {
  if (models.trim().isEmpty ||
      output != null && output.trim().isEmpty ||
      migrations.trim().isEmpty ||
      defaultNamespace != null && defaultNamespace.trim().isEmpty) {
    throw const FormatException(
      'Configuration paths and namespaces cannot be empty.',
    );
  }
  final invocation = ConfigInvocation.current;
  if (invocation == null) {
    throw const FormatException(
      'Run this configuration with dart run orm <command> --config <path>.',
    );
  }
  invocation.register(
    ProjectConfig(
      database: database,
      models: models,
      output: output,
      migrations: migrations,
      defaultNamespace: defaultNamespace,
      connect: connect,
      renames: renames,
      using: using,
    ),
  );
}
