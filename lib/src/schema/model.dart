import '../../driver.dart' show SqlDialect;
import '../../values.dart';

/// Physical column metadata coupled to the Dart/storage [Codec].
///
/// This value is usable without generated models or a connection. Schema and
/// migration validation enforce combinations such as generated identities,
/// nullability, defaults, and engine-specific storage limits.
///
/// {@category Schema}
final class Column<T> {
  /// Physical SQL name, quoted as an identifier when SQL is rendered.
  final String name;

  /// Typed conversion used for stored values and selected results.
  final Codec<T> codec;

  /// Whether the physical column permits SQL NULL.
  final bool nullable;

  /// Whether the database supplies an integer primary-key identity.
  final bool generated;

  /// Trusted SQL default expression used when an insert omits this column.
  final String? defaultSql;

  /// Database-generated expression; computed columns are excluded from writes.
  final ComputedColumn? computed;

  /// Called once for an omitted value when constructing an insert. Prepared
  /// mutations retain that value; compilation and updates never call this.
  final T Function()? clientDefault;

  /// Signed integer storage width (16, 32 or 64). The default is 64.
  /// This describes the column, not the result width of SQL arithmetic.
  final int? integerBits;

  /// Optional decimal column precision, separate from expression result types.
  final int? decimalPrecision;

  /// Optional decimal column scale, paired with [decimalPrecision].
  final int? decimalScale;

  /// Optional fractional second precision, from 0 through 6.
  final int? temporalPrecision;

  /// Describes one physical column without creating or validating a database.
  const Column(
    this.name,
    this.codec, {
    this.nullable = false,
    this.generated = false,
    this.defaultSql,
    this.computed,
    this.clientDefault,
    this.integerBits,
    this.decimalPrecision,
    this.decimalScale,
    this.temporalPrecision,
  });
}

/// How a database maintains a computed column, subject to engine capabilities.
enum ComputedStorage {
  /// Stores the generated value and recomputes it when its inputs change.
  stored,

  /// Computes the generated value when it is read.
  virtual,
}

/// Database-computed SQL using physical column names.
final class ComputedColumn {
  /// Trusted SQLite expression using physical column names.
  final String sqlite;

  /// Trusted PostgreSQL expression using physical column names.
  final String postgres;

  /// Explicit MySQL expression, or null when that dialect is unsupported.
  final String? mysql;

  /// Explicit MariaDB expression, or null when that dialect is unsupported.
  final String? mariadb;

  /// Storage strategy requested from the target database.
  final ComputedStorage storage;

  /// Uses one trusted SQL expression for every supported dialect.
  const ComputedColumn(
    String expression, {
    this.storage = ComputedStorage.stored,
  }) : sqlite = expression,
       postgres = expression,
       mysql = expression,
       mariadb = expression;

  /// Uses explicit dialect expressions without silently substituting another.
  const ComputedColumn.forDialects({
    required this.sqlite,
    required this.postgres,
    this.mysql,
    this.mariadb,
    this.storage = ComputedStorage.stored,
  });

  /// Returns the target expression or throws if that dialect was not declared.
  String expression(SqlDialect dialect) => switch (dialect) {
    SqlDialect.sqlite => sqlite,
    SqlDialect.postgres => postgres,
    SqlDialect.mysql =>
      mysql ??
          (throw const OrmException(
            'SCHEMA.DIALECT',
            'Declare the MySQL expression explicitly.',
          )),
    SqlDialect.mariadb =>
      mariadb ??
          (throw const OrmException(
            'SCHEMA.DIALECT',
            'Declare the MariaDB expression explicitly.',
          )),
  };
}

/// A database foreign key described with ordered physical column names.
///
/// Source and target columns must have matching arity and compatible storage.
/// Creating this value does not execute DDL or infer an index.
final class ForeignKey {
  /// Source columns in key order.
  final List<String> columns;

  /// Physical name of the referenced table.
  final String target;

  /// PostgreSQL namespace of the target, independent of its table name.
  /// Null retains an unqualified historical target.
  final String? targetNamespace;

  /// Stable physical identity for matching references, never parsed as SQL.
  String get targetIdentity =>
      targetNamespace == null ? target : '$targetNamespace.$target';

  /// Target key columns in the corresponding source-column order.
  final List<String> targetColumns;

  /// SQL referential action, validated for the target database.
  final String onDelete;

  /// Describes a foreign key; the default deletion action is `RESTRICT`.
  const ForeignKey(
    this.columns,
    this.target,
    this.targetColumns, {
    this.onDelete = 'RESTRICT',
    this.targetNamespace,
  });
}

/// A row CHECK expression. A null name leaves naming to the database.
final class CheckSchema {
  /// Physical constraint name, or null to retain an unnamed constraint.
  final String? name;

  /// Trusted SQLite expression using physical column names.
  final String sqlite;

  /// Trusted PostgreSQL expression using physical column names.
  final String postgres;

  /// Explicit MySQL expression, or null when that dialect is unsupported.
  final String? mysql;

  /// Explicit MariaDB expression, or null when that dialect is unsupported.
  final String? mariadb;

  /// Uses one trusted SQL expression for all dialects.
  const CheckSchema(this.name, String expression)
    : sqlite = expression,
      postgres = expression,
      mysql = expression,
      mariadb = expression;

  /// Uses explicit dialect expressions; omitted engines remain unsupported.
  const CheckSchema.forDialects(
    this.name, {
    required this.sqlite,
    required this.postgres,
    this.mysql,
    this.mariadb,
  });

  /// Returns the target expression or rejects an undeclared dialect.
  String expression(SqlDialect dialect) => switch (dialect) {
    SqlDialect.sqlite => sqlite,
    SqlDialect.postgres => postgres,
    SqlDialect.mysql =>
      mysql ??
          (throw const OrmException(
            'SCHEMA.DIALECT',
            'Declare the MySQL expression explicitly.',
          )),
    SqlDialect.mariadb =>
      mariadb ??
          (throw const OrmException(
            'SCHEMA.DIALECT',
            'Declare the MariaDB expression explicitly.',
          )),
  };
}

/// A simple index over ordered physical columns.
final class IndexSchema {
  /// Physical SQL index name.
  final String name;

  /// Indexed columns in the requested index order.
  final List<String> columns;

  /// Whether the database enforces uniqueness for this index.
  final bool unique;

  /// Describes an index without creating it or inferring sort expressions.
  const IndexSchema(this.name, this.columns, {this.unique = false});
}

/// Immutable physical table metadata, independent of Dart model identity.
///
/// The constructor copies collection inputs, including nested key and index
/// column lists. Schema consumers validate engine support before executing DDL.
///
/// ```dart
/// final accounts = TableSchema(
///   'accounts',
///   columns: [Column('id', Codecs.integer), Column('email', Codecs.text)],
///   primaryKey: ['id'],
///   uniqueKeys: [['email']],
/// );
/// ```
///
/// {@category Schema}
final class TableSchema {
  /// Physical table name.
  final String name;

  /// PostgreSQL namespace. Generated PostgreSQL models always specify this,
  /// including `public`; other engines reject explicit namespaces.
  /// Null also preserves the meaning and fingerprints of historical metadata.
  final String? namespace;

  /// Stable physical identity for maps and diagnostics, never parsed as SQL.
  String get identity => namespace == null ? name : '$namespace.$name';

  /// Ordered columns used to render the physical schema.
  final List<Column<Object?>> columns;

  /// Ordered primary-key column names, or an empty list when absent.
  final List<String> primaryKey;

  /// Ordered column groups with database uniqueness constraints.
  final List<List<String>> uniqueKeys;

  /// Database-enforced references to keys in other physical tables.
  final List<ForeignKey> foreignKeys;

  /// Explicit indexes; foreign keys do not imply extra indexes here.
  final List<IndexSchema> indexes;

  /// Database CHECK constraints expressed in trusted SQL.
  final List<CheckSchema> checks;

  /// Columns with Dart insert factories, derived from [columns].
  final List<Column<Object?>> clientDefaults;

  /// Copies schema collections without opening or altering a database.
  TableSchema(
    this.name, {
    this.namespace,
    required List<Column<Object?>> columns,
    List<String> primaryKey = const [],
    List<List<String>> uniqueKeys = const [],
    List<ForeignKey> foreignKeys = const [],
    List<IndexSchema> indexes = const [],
    List<CheckSchema> checks = const [],
  }) : columns = List.unmodifiable(columns),
       clientDefaults = List.unmodifiable(
         columns.where((c) => c.clientDefault != null),
       ),
       primaryKey = List.unmodifiable(primaryKey),
       uniqueKeys = List.unmodifiable(
         uniqueKeys.map(List<String>.unmodifiable),
       ),
       foreignKeys = List.unmodifiable([
         for (final key in foreignKeys)
           ForeignKey(
             List.unmodifiable(key.columns),
             key.target,
             List.unmodifiable(key.targetColumns),
             onDelete: key.onDelete,
             targetNamespace: key.targetNamespace,
           ),
       ]),
       checks = List.unmodifiable(checks),
       indexes = List.unmodifiable([
         for (final index in indexes)
           IndexSchema(
             index.name,
             List.unmodifiable(index.columns),
             unique: index.unique,
           ),
       ]);
}
