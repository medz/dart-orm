/// Physical table metadata shared by SQL compilation and schema migrations.
library;

import 'driver.dart' show SqlDialect;
import 'values.dart';
export 'driver.dart' show SqlDialect;
export 'values.dart';

final class Column<T> {
  final String name;
  final Codec<T> codec;
  final bool nullable;
  final bool generated;
  final String? defaultSql;
  final ComputedColumn? computed;

  /// Called once for an omitted value when constructing an insert. Prepared
  /// mutations retain that value; compilation and updates never call this.
  final T Function()? clientDefault;

  /// Signed integer storage width (16, 32 or 64). The default is 64.
  /// This describes the column, not the result width of SQL arithmetic.
  final int? integerBits;
  final int? decimalPrecision;
  final int? decimalScale;
  final int? temporalPrecision;
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

enum ComputedStorage { stored, virtual }

/// Database-computed SQL using physical column names.
final class ComputedColumn {
  final String sqlite, postgres;
  final String? mysql, mariadb;
  final ComputedStorage storage;
  const ComputedColumn(
    String expression, {
    this.storage = ComputedStorage.stored,
  }) : sqlite = expression,
       postgres = expression,
       mysql = expression,
       mariadb = expression;
  const ComputedColumn.forDialects({
    required this.sqlite,
    required this.postgres,
    this.mysql,
    this.mariadb,
    this.storage = ComputedStorage.stored,
  });
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

final class ForeignKey {
  final List<String> columns;
  final String target;
  final List<String> targetColumns;
  final String onDelete;
  const ForeignKey(
    this.columns,
    this.target,
    this.targetColumns, {
    this.onDelete = 'RESTRICT',
  });
}

/// A row CHECK expression. A null name leaves naming to the database.
final class CheckSchema {
  final String? name;
  final String sqlite;
  final String postgres;
  final String? mysql, mariadb;
  const CheckSchema(this.name, String expression)
    : sqlite = expression,
      postgres = expression,
      mysql = expression,
      mariadb = expression;
  const CheckSchema.forDialects(
    this.name, {
    required this.sqlite,
    required this.postgres,
    this.mysql,
    this.mariadb,
  });
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

final class IndexSchema {
  final String name;
  final List<String> columns;
  final bool unique;
  const IndexSchema(this.name, this.columns, {this.unique = false});
}

final class TableSchema {
  final String name;
  final List<Column<Object?>> columns;
  final List<String> primaryKey;
  final List<List<String>> uniqueKeys;
  final List<ForeignKey> foreignKeys;
  final List<IndexSchema> indexes;
  final List<CheckSchema> checks;
  final List<Column<Object?>> clientDefaults;
  TableSchema(
    this.name, {
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
