part of '../../migrate.dart';

/// Physical schema facts saved as Dart with migrations. Storage codecs support DDL;
/// custom domain decoding remains in the generated application client.
final class SchemaSnapshot {
  final List<TableSchema> tables;
  SchemaSnapshot(List<TableSchema> tables)
    : tables = List.unmodifiable(tables) {
    _validateSchema(tables);
  }

  /// Resolves shared declarations to physical facts for this engine only.
  SchemaSnapshot forDialect(SqlDialect dialect) {
    _validateSchema(tables, dialect);
    return SchemaSnapshot([for (final t in tables) _targetTable(t, dialect)]);
  }

  Map<String, Object?> toJson() => {
    'format': 1,
    'tables': [for (final table in tables) _tableJson(table)],
  };
  String get checksum => _hash(toJson());
}

TableSchema _targetTable(TableSchema table, SqlDialect dialect) {
  final target = TableSchema(
    table.name,
    columns: [
      for (final c in table.columns)
        Column<Object?>(
          c.name,
          c.codec,
          nullable: c.nullable,
          generated: c.generated,
          defaultSql: c.defaultSql,
          computed: c.computed == null
              ? null
              : ComputedColumn(
                  c.computed!.expression(dialect),
                  storage: c.computed!.storage,
                ),
          integerBits: c.integerBits,
          decimalPrecision: c.decimalPrecision,
          decimalScale: c.decimalScale,
          temporalPrecision: c.temporalPrecision,
        ),
    ],
    primaryKey: table.primaryKey,
    uniqueKeys: table.uniqueKeys,
    indexes: table.indexes,
    foreignKeys: table.foreignKeys,
    checks: [
      for (final c in table.checks) CheckSchema(c.name, c.expression(dialect)),
    ],
  );
  return _isMysql(dialect) ? _mysqlPhysicalTable(target) : target;
}

Map<String, Object?> _checkJson(CheckSchema check) => {
  'name': check.name,
  'sqlite': check.sqlite,
  'postgres': check.postgres,
  if (check.mysql != null && check.mysql != check.postgres)
    'mysql': check.mysql,
  if (check.mariadb != null && check.mariadb != check.postgres)
    'mariadb': check.mariadb,
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
