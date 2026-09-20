import '../../values.dart' show Codec;
import 'model.dart' show ComputedStorage;

/// A public const codec reference. Generation reads its type and storage tag;
/// it never executes the application's encode/decode functions.
final class UseCodec<T> {
  /// Public constant codec used to encode and decode the annotated field.
  final Codec<T> codec;

  /// Associates a field with a public const variable or static const codec.
  const UseCodec(this.codec);
}

/// Stable database text for an enum constant, independent of its Dart name.
final class EnumValue {
  /// Unique text label stored for the annotated enum constant.
  final String value;

  /// Overrides the default storage label, which is the Dart constant name.
  const EnumValue(this.value);
}

/// Marks a field as part of the table's primary key.
///
/// Multiple [Id] fields form a composite key in field order. Use [Id.generated]
/// only for a single, non-null integer primary key.
///
/// ```dart
/// final class User(@Id.generated() final int id, final String name);
/// ```
///
/// {@category Declarations}
final class Id {
  /// Whether the database generates the identity when an insert omits it.
  final bool generated;

  /// Declares an application-supplied primary-key field.
  const Id() : generated = false;

  /// Declares a database-generated integer primary key.
  const Id.generated() : generated = true;
}

/// Declares a unique constraint for the annotated field.
final class Unique {
  /// Requires stored non-null values to be unique under database semantics.
  const Unique();
}

/// Overrides the physical column name while preserving the Dart field name.
final class ColumnName {
  /// Physical SQL column name, quoted as an identifier during SQL generation.
  final String name;

  /// Associates a Dart field with a stable database column name.
  const ColumnName(this.name);
}

/// A database SQL default used when an insert omits the annotated field.
///
/// The expression is trusted SQL, not a bound parameter. It does not supply a
/// Dart constructor default or run when an existing row is decoded.
final class Default {
  /// SQL expression placed in the column DEFAULT clause.
  final String expression;

  /// Declares a database default such as `CURRENT_TIMESTAMP` or `false`.
  const Default.sql(this.expression);
}

/// Generates an omitted insert value in Dart. This never declares SQL DEFAULT.
/// The factory is referenced during generation, not invoked.
final class ClientDefault<T> {
  /// Public, synchronous factory invoked only when constructing an insert.
  final T Function() factory;

  /// Uses a public top-level function, static method, or constructor tear-off.
  const ClientDefault(this.factory);
}

/// SQL computed by the database; omitted from generated writes.
final class Computed {
  /// Default trusted SQL expression used when a dialect override is absent.
  final String expression;

  /// Optional SQLite expression using physical column names.
  final String? sqlite;

  /// Optional PostgreSQL expression using physical column names.
  final String? postgres;

  /// Optional MySQL expression using physical column names.
  final String? mysql;

  /// Optional MariaDB expression using physical column names.
  final String? mariadb;

  /// Whether the database stores the result or computes it when read.
  final ComputedStorage storage;

  /// Declares a generated column excluded from generated create and patch APIs.
  const Computed.sql(
    this.expression, {
    this.sqlite,
    this.postgres,
    this.mysql,
    this.mariadb,
    this.storage = ComputedStorage.stored,
  });
}

/// Signed integer column storage. SQL expression results retain the int codec.
final class IntegerBits {
  /// Signed storage width: 16, 32, or 64 bits.
  final int value;

  /// Constrains an integer column; unsupported widths fail generation.
  const IntegerBits(this.value);
}

/// Decimal column precision and scale, matching PostgreSQL NUMERIC(p, s).
final class DecimalDigits {
  /// Total declared decimal precision, from 1 through 1000.
  final int precision;

  /// Declared scale, from -1000 through 1000; defaults to zero.
  final int scale;

  /// Constrains decimal column storage; each database validates its own limits.
  const DecimalDigits(this.precision, [this.scale = 0]);
}

/// Fractional second digits (0..6) for time, local timestamp or UTC instant columns.
final class TemporalPrecision {
  /// Number of fractional second digits, from 0 through 6.
  final int digits;

  /// Declares storage precision without changing the Dart field type.
  const TemporalPrecision(this.digits);
}

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

/// A fixed SQL file with declared result and parameter Record types.
/// Run query generation, then check the output against each target database.
/// Paths are relative to this declaration's Dart library. [R] is a named-record
/// result typedef; [P] is a named record or `()` for no parameters.
///
/// ```dart
/// typedef UserName = ({String name});
/// final userNames = sqlQuery<UserName, ({int minimumId})>(
///   sqlite: 'user_names.sql',
/// );
/// ```
///
/// {@category Declarations}
SqlDeclaration<R, P> sqlQuery<R, P>({
  String? sqlite,
  String? postgres,
  String? mysql,
  String? mariadb,
}) => SqlDeclaration(sqlite, postgres, mysql, mariadb);

/// Source metadata for a typed SQL query; creating it does not execute SQL.
///
/// Use [sqlQuery] in a top-level declaration recognized by the generator.
final class SqlDeclaration<R, P> {
  /// SQLite SQL file, relative to the declaring Dart library.
  final String? sqlite;

  /// PostgreSQL SQL file, relative to the declaring Dart library.
  final String? postgres;

  /// MySQL SQL file, relative to the declaring Dart library.
  final String? mysql;

  /// MariaDB SQL file, relative to the declaring Dart library.
  final String? mariadb;

  /// Stores dialect-specific source paths without opening them.
  const SqlDeclaration(this.sqlite, this.postgres, this.mysql, this.mariadb);
}

/// Declares an independently named table backed by the Dart model [M].
///
/// Place this call in a public top-level variable. [M] must be a supported final
/// primary-constructor class or named-record typedef in the same source file.
/// The variable name determines the default physical name unless [table] is set.
/// Model constructors are not executed during generation.
///
/// ```dart
/// final class User(@Id() final int id, final String email);
/// final users = entity<User>(table: 'app_users');
/// final emailIndex = users.index((user) => user.email);
/// ```
///
/// {@category Declarations}
Entity<M> entity<M>({String? table}) => Entity<M>(table);

/// A source-level table declaration with model, key, and constraint types.
///
/// Use [entity] to create a declaration the generator can discover. Constraint
/// methods describe source syntax; calling them does not modify a live database.
///
/// {@category Declarations}
final class Entity<M> {
  /// Explicit physical table name, or null to derive it from the declaration.
  final String? table;

  /// Stores the optional physical name without registering or opening a table.
  const Entity(this.table);

  /// Selects one field or a record of fields for a relationship key.
  ///
  /// Selector order determines composite-key column order.
  EntityKey<M, K> key<K>(K Function(M) selector) => EntityKey(this, selector);

  /// Declares a primary key in a separate top-level variable.
  ///
  /// Selected columns must be non-nullable and cannot duplicate an annotated key.
  SchemaConstraint primaryKey<K>(K Function(M) selector) =>
      const SchemaConstraint();

  /// Declares a unique key on one field or an ordered record of fields.
  SchemaConstraint unique<K>(K Function(M) selector) =>
      const SchemaConstraint();

  /// Trusted SQL using physical column names. Omitted name uses the declaration
  /// name; explicit name: null preserves an unnamed imported constraint.
  SchemaConstraint check(
    String expression, {
    String? name,
    String? sqlite,
    String? postgres,
    String? mysql,
    String? mariadb,
  }) => const SchemaConstraint();

  /// Declares an index on the selected physical columns in selector order.
  ///
  /// The top-level declaration supplies the default name; [name] overrides it.
  /// [unique] also permits this index to serve as a foreign-key target.
  SchemaConstraint index<K>(
    K Function(M) selector, {
    String? name,
    bool unique = false,
  }) => const SchemaConstraint();
}

/// An ordered set of model fields used to declare a relationship.
///
/// Obtain this through [Entity.key]. The generator reads the selector syntax and
/// does not call it against an application object.
final class EntityKey<M, K> {
  /// Table declaration owning the selected fields.
  final Entity<M> entity;

  /// Source selector for one field or a record of fields.
  final K Function(M) selector;

  /// Stores a table and selector without evaluating the selector.
  const EntityKey(this.entity, this.selector);

  /// Declares a foreign key and generated query navigation to [target].
  ///
  /// The target must be a primary or unique key in matching column order, with
  /// compatible Dart and storage types. [inverse] adds reverse navigation;
  /// [onDelete] controls database-enforced deletion behavior.
  SchemaConstraint references<N>(
    EntityKey<N, K> target, {
    String? inverse,
    ReferentialAction onDelete = ReferentialAction.restrict,
  }) => const SchemaConstraint();

  /// Read-only query navigation without a database foreign key. Matching rows
  /// may be absent or duplicated; this declaration creates no write effects.
  SchemaConstraint relatesTo<N>(EntityKey<N, K> target, {String? inverse}) =>
      const SchemaConstraint();
}

/// Marker returned by source-level key, index, check, and relation declarations.
///
/// The generator reads the original top-level expression. This marker carries no
/// runtime database operation or mutable constraint registry.
final class SchemaConstraint {
  /// Creates a marker without evaluating or applying a schema change.
  const SchemaConstraint();
}
