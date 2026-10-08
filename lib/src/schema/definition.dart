import 'package:orm/database.dart' show Engine;

/// Portable scalar types. Driver mappings preserve their documented semantics.
enum ScalarType { integer, text, boolean, real, dateTime, bytes }

/// A frozen foreign-key target, independent of application classes.
final class ForeignKey {
  const ForeignKey(this.table, this.column, {this.onDelete = 'restrict'});
  final String table;
  final String column;
  final String onDelete;
}

/// Column identity, storage constraints and literal default.
final class ColumnDefinition {
  const ColumnDefinition({
    required this.name,
    required this.field,
    required this.type,
    this.nullable = false,
    this.primaryKey = false,
    this.identity = false,
    this.unique = false,
    this.defaultValue,
    this.references,
  });
  final String name;
  final String field;
  final ScalarType type;
  final bool nullable;
  final bool primaryKey;
  final bool identity;
  final bool unique;
  final Object? defaultValue;
  final ForeignKey? references;
}

/// Physical table identity is never inferred from a Dart record type.
final class TableDefinition {
  const TableDefinition(this.name, this.columns);
  final String name;
  final List<ColumnDefinition> columns;
  ColumnDefinition column(String field) => columns.firstWhere(
    (c) => c.field == field,
    orElse: () => throw ArgumentError('Unknown field $field in $name'),
  );
}

/// Engine-specific schema description. Generated snapshots use const data;
/// migration definitions copy and freeze caller-provided collections.
final class SchemaSnapshot {
  const SchemaSnapshot({required this.engine, required this.tables});
  final Engine engine;
  final List<TableDefinition> tables;
}
