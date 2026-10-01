/// Package command runner for generation and project migrations.
///
/// Run the `orm` executable or pass command arguments to [runOrmCli]. Projects
/// configure their parameterless Dart entrypoint with `defineConfig` from
/// `package:orm/config.dart`. The runner loads that configuration and its frozen
/// migration history only when needed; generation remains offline.
///
/// {@category Tooling}
/// {@canonicalFor runner.runOrmCli}
library;

export 'src/cli/runner.dart' show runOrmCli;
