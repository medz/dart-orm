import '../../values.dart' show Codec;

import 'model.dart' show ComputedStorage;

/// Database behavior when a referenced row is deleted.
enum ReferentialAction {
  /// Rejects deletion while referencing rows exist.
  restrict,

  /// Deletes rows that reference the deleted row.
  cascade,

  /// Sets referencing columns to SQL NULL; those columns must be nullable.
  setNull,

  /// Assigns the referencing columns' database defaults when supported.
  setDefault,

  /// Uses the database's NO ACTION constraint semantics.
  noAction,
}

/// Maps an ordinary Dart class to a physical table.
///
/// [table] defaults to the class name without case conversion or pluralization.
/// [namespace] overrides the PostgreSQL configuration default; it never changes
/// the Dart class identity, query member name, or connection search path.
final class Model {
  /// Explicit physical table name.
  final String? table;

  /// Explicit PostgreSQL namespace, independent of source paths.
  final String? namespace;

  /// Marks a class for static generation.
  const Model({this.table, this.namespace});
}

/// Includes a field in the primary key, in constructor declaration order.
final class Id {
  /// Whether the database generates this single integer-storage key.
  final bool generated;

  /// Marks a primary-key field. Generated keys may be omitted on creation.
  const Id({this.generated = false});
}

/// Overrides inferred scalar storage metadata without changing the DTO type.
final class Column {
  /// Physical column name; otherwise the field name is converted to snake_case.
  final String? name;

  /// Public constant codec for a domain value. Its type must match the field.
  final Codec<Object?>? codec;

  /// Complete, distinct storage labels for an enum field.
  final Map<Enum, String>? labels;

  /// Integer width, when integer storage is selected.
  final int? bits;

  /// Decimal or temporal precision, according to the storage type.
  final int? precision;

  /// Decimal scale, requiring an explicit precision.
  final int? scale;

  /// Configures physical scalar storage.
  const Column({
    this.name,
    this.codec,
    this.labels,
    this.bits,
    this.precision,
    this.scale,
  });
}

/// Declares a unique field, or a class-level ordered composite unique key.
final class Unique {
  /// Dart field names for class-level usage; empty on a scalar field.
  final List<String> fields;

  /// Declares uniqueness. Strings are checked during generation.
  const Unique([this.fields = const []]);
}

/// Declares a named index using Dart field names, checked during generation.
final class Index {
  /// Ordered fields in the index.
  final List<String> fields;

  /// Physical index name.
  final String name;

  /// Whether the index also enforces uniqueness.
  final bool unique;

  /// Declares a class-level index.
  const Index(this.fields, {required this.name, this.unique = false});
}

/// Declares explicit navigation and optionally a physical foreign key.
///
/// On a scalar field, use [key] for the target field. On a class, use ordered
/// [fields] and [keys]; each pair is validated for type, storage and codec.
/// The target must be reachable through a model source, export or relation.
/// Relations never become DTO fields or automatically loaded placeholders.
final class Relation {
  /// Original annotated target class.
  final Type target;

  /// Generated navigation member on this model's query fields.
  final String name;

  /// Target field for a single-field relation; defaults to its primary key.
  final String? key;

  /// Local fields for class-level composite relations.
  final List<String> fields;

  /// Ordered target fields; defaults to the target primary key.
  final List<String> keys;

  /// Optional reverse navigation; it does not create a second foreign key.
  final String? inverse;

  /// Physical deletion action when [constraint] is true.
  final ReferentialAction onDelete;

  /// Whether to create a database foreign key, rather than read-only navigation.
  final bool constraint;

  /// Declares a checked relation whose loading remains explicit.
  const Relation({
    required this.target,
    required this.name,
    this.key,
    this.fields = const [],
    this.keys = const [],
    this.inverse,
    this.onDelete = ReferentialAction.restrict,
    this.constraint = true,
  });
}

/// Excludes an instance field from persistent scalar mapping.
///
/// An ignored constructor parameter must be optional so complete database rows
/// can still instantiate the DTO without inventing a value for it.
final class Ignore {
  /// Marks a nonpersistent field or constructor parameter.
  const Ignore();
}

/// Supplies an omitted insert value using a public synchronous factory.
///
/// The zero-required-argument factory is referenced, never run during generation.
/// Explicit values, including legal null, bypass it. Patches never apply it.
final class ClientDefault {
  /// Public top-level function, static method or constructor tear-off.
  final Function factory;

  /// Declares a client-side default factory.
  const ClientDefault(this.factory);
}

/// Explicitly declares a database insert default.
///
/// Constructor constants are client-side fallbacks only; they do not imply this
/// annotation or a SQL DEFAULT. An explicit client factory takes precedence over
/// this default. Actual database values always populate complete DTO reads.
final class DatabaseDefault {
  /// Scalar constant to encode as a SQL default, or null for [DatabaseDefault.sql].
  final Object? value;

  /// Trusted SQL expression, without automatic quoting.
  final String? expression;

  /// Uses a scalar constant as a database default, including a legal null.
  const DatabaseDefault(this.value) : expression = null;

  /// Uses a trusted SQL expression as a database default.
  const DatabaseDefault.sql(String sql) : value = null, expression = sql;
}

/// Marks a scalar field as database-computed and excludes it from writes.
/// Expressions are trusted SQL using physical column names.
final class Computed {
  /// SQL used where no dialect override is provided.
  final String expression;

  /// SQLite expression override; empty explicitly marks it unsupported.
  final String? sqlite;

  /// PostgreSQL expression override.
  final String? postgres;

  /// MySQL expression override.
  final String? mysql;

  /// MariaDB expression override.
  final String? mariadb;

  /// Whether computation is stored or virtual, subject to engine capabilities.
  final ComputedStorage storage;

  /// Declares a computed database field.
  const Computed(
    this.expression, {
    this.sqlite,
    this.postgres,
    this.mysql,
    this.mariadb,
    this.storage = ComputedStorage.stored,
  });
}

/// Declares a class-level database check using trusted SQL.
final class Check {
  /// SQL used where no dialect override is provided.
  final String expression;

  /// Optional physical constraint name.
  final String? name;

  /// SQLite expression override; empty explicitly marks it unsupported.
  final String? sqlite;

  /// PostgreSQL expression override.
  final String? postgres;

  /// MySQL expression override.
  final String? mysql;

  /// MariaDB expression override.
  final String? mariadb;

  /// Declares a database check; generation does not execute the expression.
  const Check(
    this.expression, {
    this.name,
    this.sqlite,
    this.postgres,
    this.mysql,
    this.mariadb,
  });
}
