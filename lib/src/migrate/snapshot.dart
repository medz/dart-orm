part of '../../migrate.dart';

/// Physical schema facts saved as Dart with migrations. Storage codecs support DDL;
/// custom domain decoding remains in the generated application client.
final class SchemaSnapshot {
  final List<TableSchema> tables;
  SchemaSnapshot(List<TableSchema> tables)
    : tables = List.unmodifiable(tables) {
    for (final dialect in SqlDialect.values) {
      createSchema(tables, dialect);
    }
  }
  Map<String, Object?> toJson() => {
    'format': 1,
    'tables': [for (final table in tables) _tableJson(table)],
  };
  String get checksum => _hash(toJson());
}

CheckSchema _readCheck(Map<String, Object?> json) => CheckSchema.forDialects(
  json['name'] as String?,
  sqlite: json['sqlite'] as String,
  postgres: json['postgres'] as String,
);

Map<String, Object?> _checkJson(CheckSchema check) => {
  'name': check.name,
  'sqlite': check.sqlite,
  'postgres': check.postgres,
};

Map<String, Object?> _columnJson(Column<Object?> column) => {
  'name': column.name,
  'type': column.codec.sqlType,
  'nullable': column.nullable,
  'generated': column.generated,
  if (column.defaultSql != null) 'default': column.defaultSql,
  if (column.computed != null) 'computed': _computedJson(column.computed!),
  if (column.integerBits != null && column.integerBits != 64)
    'integerBits': column.integerBits,
  if (column.temporalPrecision != null && column.temporalPrecision != 6)
    'temporalPrecision': column.temporalPrecision,
  if (column.decimalPrecision != null)
    'decimalPrecision': column.decimalPrecision,
  if (column.decimalPrecision != null &&
      column.decimalScale != null &&
      column.decimalScale != 0)
    'decimalScale': column.decimalScale,
};
Map<String, Object?> _indexJson(IndexSchema index) => {
  'name': index.name,
  'columns': index.columns,
  'unique': index.unique,
};
Map<String, Object?> _foreignKeyJson(ForeignKey key) => {
  'columns': key.columns,
  'target': key.target,
  'targetColumns': key.targetColumns,
  'onDelete': key.onDelete,
};
Map<String, Object?> _tableJson(TableSchema table) => {
  'name': table.name,
  'columns': [for (final column in table.columns) _columnJson(column)],
  'primaryKey': table.primaryKey,
  'uniqueKeys': table.uniqueKeys,
  'indexes': [for (final index in table.indexes) _indexJson(index)],
  'foreignKeys': [for (final key in table.foreignKeys) _foreignKeyJson(key)],
  if (table.checks.isNotEmpty) 'checks': table.checks.map(_checkJson).toList(),
};
