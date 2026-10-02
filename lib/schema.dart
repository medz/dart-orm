/// Declares ordinary Dart model classes for static, typed ORM generation.
///
/// Annotate public classes with [Model], use named field parameters, and run
/// `dart run orm generate` with a `defineConfig` project entrypoint. Queries
/// construct the original DTO and preserve its methods; relation loading is
/// explicit. Generation never executes application factories or constructors.
///
/// {@category Declarations}
/// {@canonicalFor annotations.Model}
/// {@canonicalFor annotations.Projection}
/// {@canonicalFor annotations.Column}
/// {@canonicalFor annotations.Id}
/// {@canonicalFor annotations.Unique}
/// {@canonicalFor annotations.Index}
/// {@canonicalFor annotations.Relation}
/// {@canonicalFor annotations.Ignore}
/// {@canonicalFor annotations.ClientDefault}
/// {@canonicalFor annotations.DatabaseDefault}
/// {@canonicalFor annotations.Computed}
/// {@canonicalFor annotations.Check}
/// {@canonicalFor annotations.ReferentialAction}
library;

export 'src/schema/annotations.dart'
    show
        Model,
        Projection,
        Id,
        Column,
        Unique,
        Index,
        Relation,
        Ignore,
        ClientDefault,
        DatabaseDefault,
        Computed,
        Check,
        ReferentialAction;
