part of '../../migrate.dart';

/// Portable schema facts saved with migrations. Codecs are restored for DDL;
/// custom domain decoding remains in the generated application client.
final class SchemaSnapshot {
  final List<TableSchema> tables;
  SchemaSnapshot(List<TableSchema> tables)
    : tables = List.unmodifiable(tables) {
    for (final dialect in SqlDialect.values) {
      createSchema(tables, dialect);
    }
  }
  factory SchemaSnapshot.fromJson(Map<String, Object?> json) {
    if (json['format'] != 1) {
      throw const OrmException(
        'SCHEMA.FORMAT',
        'Unsupported schema snapshot format.',
      );
    }
    return SchemaSnapshot([
      for (final value in json['tables'] as List<Object?>)
        _readTable(value as Map<String, Object?>),
    ]);
  }
  Map<String, Object?> toJson() => {
    'format': 1,
    'tables': [for (final table in tables) _tableJson(table)],
  };
  String get checksum => _hash(toJson());
  static TableSchema _readTable(Map<String, Object?> json) => TableSchema(
    json['name'] as String,
    columns: [
      for (final value in json['columns'] as List<Object?>)
        _readColumn(value as Map<String, Object?>),
    ],
    primaryKey: (json['primaryKey'] as List<Object?>).cast<String>(),
    uniqueKeys: [
      for (final key in json['uniqueKeys'] as List<Object?>)
        (key as List<Object?>).cast<String>(),
    ],
    indexes: [
      for (final value in json['indexes'] as List<Object?>)
        _readIndex(value as Map<String, Object?>),
    ],
    foreignKeys: [
      for (final value in json['foreignKeys'] as List<Object?>)
        _readForeignKey(value as Map<String, Object?>),
    ],
  );
  static Column<Object?> _readColumn(Map<String, Object?> json) {
    final codec = switch (json['type']) {
      'integer' => Codecs.integer,
      'bigint' => Codecs.bigint,
      'decimal' => Codecs.decimal,
      'text' => Codecs.text,
      'real' => Codecs.real,
      'boolean' => Codecs.boolean,
      'timestamp' => Codecs.dateTime,
      'blob' => Codecs.bytes,
      'json' => Codecs.json,
      _ => throw OrmException(
        'SCHEMA.TYPE',
        'Unknown storage type ${json['type']}.',
      ),
    };
    final nullable = json['nullable'] as bool;
    return Column<Object?>(
      json['name'] as String,
      nullable ? codec.nullable() : codec,
      nullable: nullable,
      generated: json['generated'] as bool,
      defaultSql: json['default'] as String?,
      integerBits: json['integerBits'] as int?,
      decimalPrecision: json['decimalPrecision'] as int?,
      decimalScale: json['decimalScale'] as int?,
    );
  }

  static IndexSchema _readIndex(Map<String, Object?> json) => IndexSchema(
    json['name'] as String,
    (json['columns'] as List<Object?>).cast<String>(),
    unique: json['unique'] as bool,
  );
  static ForeignKey _readForeignKey(Map<String, Object?> json) => ForeignKey(
    (json['columns'] as List<Object?>).cast<String>(),
    json['target'] as String,
    (json['targetColumns'] as List<Object?>).cast<String>(),
    onDelete: json['onDelete'] as String,
  );
}

Map<String, Object?> _columnJson(Column<Object?> column) => {
  'name': column.name,
  'type': column.codec.sqlType,
  'nullable': column.nullable,
  'generated': column.generated,
  if (column.defaultSql != null) 'default': column.defaultSql,
  if (column.integerBits != null && column.integerBits != 64)
    'integerBits': column.integerBits,
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
};
