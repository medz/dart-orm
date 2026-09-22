/// Declares models and tables together using typed Record column declarations.
///
/// Import this library in a schema source; generate its immutable rows, typed
/// queries and physical snapshot with `dart run orm generate lib/schema.dart`.
/// Declaration callbacks and application factories are not executed by generation.
///
/// ```dart
/// import 'package:orm/schema.dart';
///
/// final user = model('users', (
///   id: identity(),
///   email: text(unique: true),
///   name: text().nullable(),
/// ));
/// ```
///
/// Use the generated client for queries, `schema_model.dart` for physical metadata,
/// and `migrate.dart` for reviewed database changes.
///
/// {@category Declarations}
/// {@canonicalFor declaration.Model}
/// {@canonicalFor declaration.model}
/// {@canonicalFor declaration.ColumnDefinition}
/// {@canonicalFor declaration.IndexDefinition}
/// {@canonicalFor declaration.ReferenceDefinition}
/// {@canonicalFor declaration.CheckDefinition}
/// {@canonicalFor declaration.identity}
/// {@canonicalFor declaration.integer}
/// {@canonicalFor declaration.text}
/// {@canonicalFor declaration.boolean}
/// {@canonicalFor declaration.real}
/// {@canonicalFor declaration.bigInteger}
/// {@canonicalFor declaration.decimal}
/// {@canonicalFor declaration.dateTime}
/// {@canonicalFor declaration.date}
/// {@canonicalFor declaration.time}
/// {@canonicalFor declaration.localDateTime}
/// {@canonicalFor declaration.bytes}
/// {@canonicalFor declaration.json}
/// {@canonicalFor declaration.enumeration}
/// {@canonicalFor declaration.custom}
/// {@canonicalFor declaration.index}
/// {@canonicalFor declaration.references}
/// {@canonicalFor declaration.referencedBy}
/// {@canonicalFor declaration.check}
/// {@canonicalFor declaration.ReferentialAction}
library;

export 'values.dart';
export 'src/schema/declaration.dart'
    show
        ReferentialAction,
        Model,
        model,
        ColumnDefinition,
        IndexDefinition,
        ReferenceDefinition,
        CheckDefinition,
        identity,
        integer,
        text,
        boolean,
        real,
        bigInteger,
        decimal,
        dateTime,
        date,
        time,
        localDateTime,
        bytes,
        json,
        enumeration,
        custom,
        index,
        references,
        referencedBy,
        check;
export 'schema_model.dart' show ComputedStorage;
