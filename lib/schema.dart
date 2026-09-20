/// Declares typed Dart models, storage annotations, and relationships.
///
/// Import this library in a schema source file. [entity] associates a Dart model
/// with a physical table; annotations such as [Id], [Default], and [UseCodec]
/// define stored values. Top-level key and relationship declarations generate
/// query access without executing application constructors or opening a database.
///
/// ```dart
/// import 'package:orm/schema.dart';
///
/// final class User(@Id.generated() final int id, final String email);
/// final users = entity<User>();
/// final uniqueEmail = users.unique((user) => user.email);
/// ```
///
/// Run `dart run orm generate path/to/schema.dart` to generate the typed client.
/// Use `package:orm/schema_model.dart` for physical metadata and
/// `package:orm/migrate.dart` to apply reviewed schema changes.
///
/// {@category Declarations}
/// {@canonicalFor declaration.ClientDefault}
/// {@canonicalFor declaration.ColumnName}
/// {@canonicalFor declaration.Computed}
/// {@canonicalFor declaration.DecimalDigits}
/// {@canonicalFor declaration.Default}
/// {@canonicalFor declaration.Entity}
/// {@canonicalFor declaration.EntityKey}
/// {@canonicalFor declaration.EnumValue}
/// {@canonicalFor declaration.Id}
/// {@canonicalFor declaration.IntegerBits}
/// {@canonicalFor declaration.ReferentialAction}
/// {@canonicalFor declaration.SchemaConstraint}
/// {@canonicalFor declaration.SqlDeclaration}
/// {@canonicalFor declaration.TemporalPrecision}
/// {@canonicalFor declaration.Unique}
/// {@canonicalFor declaration.UseCodec}
/// {@canonicalFor declaration.entity}
/// {@canonicalFor declaration.sqlQuery}
library;

export 'values.dart';
export 'schema_model.dart' show ComputedStorage;
export 'src/schema/declaration.dart'
    show
        ClientDefault,
        ColumnName,
        Computed,
        DecimalDigits,
        Default,
        Entity,
        EntityKey,
        EnumValue,
        Id,
        IntegerBits,
        ReferentialAction,
        SchemaConstraint,
        SqlDeclaration,
        TemporalPrecision,
        Unique,
        UseCodec,
        entity,
        sqlQuery;
