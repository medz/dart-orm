/// Optional build_runner factories for model and named SQL generation.
///
/// Select source libraries with `generate_for` in `build.yaml`. Applications
/// import the generated files; these builders run only during development.
///
/// {@category Tooling}
/// {@canonicalFor build.ormBuilder}
/// {@canonicalFor build.ormQueryBuilder}
library;

export 'src/generate/build.dart' show ormBuilder, ormQueryBuilder;
