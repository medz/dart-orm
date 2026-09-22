/// Optional build_runner factories for model generation.
///
/// Select libraries with `generate_for`, or configure `schema` and `database`
/// options to collect a definition directory as one client. Applications
/// import the generated files; these builders run only during development.
///
/// {@category Tooling}
/// {@canonicalFor build.ormBuilder}
library;

export 'src/generate/build.dart' show ormBuilder;
