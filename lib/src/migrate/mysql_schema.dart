import '../../driver.dart' show SqlCommand, SqlDialect;
import '../../schema_model.dart'
    show CheckSchema, Column, ForeignKey, IndexSchema, TableSchema;
import '../../values.dart' show OrmException;
import 'catalog.dart' show normalizeDefault;
import 'schema.dart' show checkDefinition, foreignKey, validateSchema;
import 'snapshot.dart' show foreignKeyJson;
import 'sql_utils.dart' show migrationHash, quoteIdentifier;
import 'sqlite_checks.dart' show sqliteTokens;
import 'step.dart' show CheckedTableSql, MigrationStep;

bool isMysqlFamily(SqlDialect dialect) =>
    dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb;

String _mysqlName(String kind, Object signature) =>
    '_orm_${kind}_${migrationHash(signature).substring(0, 24)}';
String mysqlForeignName(String table, ForeignKey key) => _mysqlName('fk', [
  table,
  {
    ...foreignKeyJson(key),
    'onDelete': key.onDelete == 'NO ACTION' ? 'RESTRICT' : key.onDelete,
  },
]);
String mysqlUniqueName(String table, List<String> columns) =>
    _mysqlName('uk', [table, columns]);

TableSchema mysqlCopy(
  TableSchema table, {
  String? name,
  List<Column<Object?>>? columns,
  List<String>? primaryKey,
  List<List<String>>? uniqueKeys,
  List<ForeignKey>? foreignKeys,
  List<IndexSchema>? indexes,
  List<CheckSchema>? checks,
}) => TableSchema(
  name ?? table.name,
  columns: columns ?? table.columns,
  primaryKey: primaryKey ?? table.primaryKey,
  uniqueKeys: uniqueKeys ?? table.uniqueKeys,
  foreignKeys: foreignKeys ?? table.foreignKeys,
  indexes: indexes ?? table.indexes,
  checks: checks ?? table.checks,
);

TableSchema mysqlPhysicalTable(TableSchema table) {
  final indexes = table.indexes.toList();
  for (final key in table.foreignKeys) {
    final candidates = [
      table.primaryKey,
      ...table.uniqueKeys,
      ...indexes.map((i) => i.columns),
    ];
    final covered = candidates.any(
      (columns) =>
          columns.length >= key.columns.length &&
          key.columns.indexed.every((entry) => columns[entry.$1] == entry.$2),
    );
    if (!covered) {
      indexes.add(
        IndexSchema(
          _mysqlName('fkidx', [table.name, key.columns]),
          key.columns,
        ),
      );
    }
  }
  return mysqlCopy(table, indexes: indexes);
}

void validateMysqlSchema(List<TableSchema> tables, SqlDialect dialect) {
  void distinct(Iterable<String> names) {
    final seen = <String>{};
    for (final name in names) {
      if (!seen.add(name.toLowerCase())) {
        throw const OrmException(
          'SCHEMA.DUPLICATE',
          'MySQL/MariaDB schema names must be distinct ignoring case.',
        );
      }
    }
  }

  distinct(tables.map((table) => table.name));
  if (dialect == SqlDialect.mysql) {
    distinct(
      tables
          .expand((table) => table.checks.map((check) => check.name))
          .whereType<String>(),
    );
  }
  void identifier(String value) {
    if (value.runes.length > 64) {
      throw const OrmException(
        'SCHEMA.IDENTIFIER',
        'MySQL and MariaDB identifiers cannot exceed 64 characters.',
      );
    }
  }

  for (final table in tables) {
    identifier(table.name);
    distinct(table.columns.map((column) => column.name));
    distinct(table.indexes.map((index) => index.name));
    distinct(table.checks.map((check) => check.name).whereType<String>());
    if ({
      '_orm_migrations',
      '_orm_migration_steps',
    }.contains(table.name.toLowerCase())) {
      throw const OrmException(
        'SCHEMA.RESERVED',
        'Migration metadata table names are reserved.',
      );
    }
    for (final column in table.columns) {
      identifier(column.name);
      if (column.codec.sqlType == 'decimal' &&
          (column.decimalPrecision == null ||
              column.decimalPrecision! > 65 ||
              (column.decimalScale ?? 0) < 0 ||
              (column.decimalScale ?? 0) > 30 ||
              (column.decimalScale ?? 0) > column.decimalPrecision!)) {
        throw const OrmException(
          'SCHEMA.DECIMAL_DIGITS',
          'MySQL/MariaDB decimals require explicit precision 1..65 and scale 0..30 not exceeding precision.',
        );
      }
      if (column.computed != null && !column.nullable) {
        throw const OrmException(
          'SCHEMA.COMPUTED',
          'Portable MySQL/MariaDB generated columns must be nullable.',
        );
      }
    }
    for (final check in table.checks) {
      if (check.name != null) identifier(check.name!);
      check.expression(dialect);
    }
    for (final index in table.indexes) {
      identifier(index.name);
    }
    for (final key in table.foreignKeys) {
      if (key.onDelete == 'SET DEFAULT') {
        throw const OrmException(
          'SCHEMA.FOREIGN_KEY',
          'InnoDB does not support ON DELETE SET DEFAULT.',
        );
      }
    }
  }
}

String mysqlStorageType(String type) => switch (type) {
  'integer' => 'BIGINT',
  'bigint' => 'DECIMAL(65,0)',
  'decimal' => 'DECIMAL',
  'text' => 'VARCHAR(255)',
  'boolean' => 'TINYINT(1)',
  'real' => 'DOUBLE',
  'date' => 'DATE',
  'time' => 'TIME(6)',
  'instant' || 'timestamp' || 'local_datetime' => 'DATETIME(6)',
  'json' => 'JSON',
  'blob' => 'LONGBLOB',
  _ => throw OrmException(
    'SCHEMA.TYPE',
    'No MySQL/MariaDB storage mapping for $type.',
  ),
};
String mysqlColumnType(Column<Object?> column) =>
    switch (column.codec.sqlType) {
      'integer' => switch (column.integerBits ?? 64) {
        16 => 'SMALLINT',
        32 => 'INT',
        _ => 'BIGINT',
      },
      'decimal' =>
        'DECIMAL(${column.decimalPrecision},${column.decimalScale ?? 0})',
      'time' => 'TIME(${column.temporalPrecision ?? 6})',
      'instant' ||
      'timestamp' ||
      'local_datetime' => 'DATETIME(${column.temporalPrecision ?? 6})',
      _ => mysqlStorageType(column.codec.sqlType),
    };

String mysqlColumn(Column<Object?> column, SqlDialect dialect) {
  final result = StringBuffer(
    '${quoteIdentifier(column.name)} ${mysqlColumnType(column)}',
  );
  if (column.codec.sqlType == 'text') {
    result.write(' CHARACTER SET utf8mb4 COLLATE utf8mb4_bin');
  }
  if (column.computed case final computed?) {
    result.write(
      ' GENERATED ALWAYS AS (${computed.expression(dialect)}) ${computed.storage.name.toUpperCase()}',
    );
  } else {
    result.write(column.nullable ? ' NULL' : ' NOT NULL');
    if (column.defaultSql case final value?) {
      final sql = normalizeDefault(value)!;
      // MySQL reparses parenthesized string defaults. With
      // NO_BACKSLASH_ESCAPES that can change stored backslashes; ordinary
      // literal defaults also avoid unnecessary expression-default metadata.
      final tokens = sqliteTokens(sql);
      final literal =
          tokens.length == 1 &&
              (tokens.single.text.startsWith('s:') ||
                  {'NULL', 'TRUE', 'FALSE'}.contains(tokens.single.text)) ||
          RegExp(r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$')
              .hasMatch(sql);
      final requiresExpression =
          dialect == SqlDialect.mysql &&
          {'json', 'blob'}.contains(column.codec.sqlType);
      result.write(
        ' DEFAULT ${literal && !requiresExpression ? sql : '($sql)'}',
      );
    }
    if (column.generated) result.write(' AUTO_INCREMENT');
  }
  return result.toString();
}

String mysqlCreateTable(TableSchema table, SqlDialect dialect) {
  final definitions = [
    for (final column in table.columns) mysqlColumn(column, dialect),
    if (table.primaryKey.isNotEmpty)
      'PRIMARY KEY (${table.primaryKey.map(quoteIdentifier).join(', ')})',
    for (final key in table.uniqueKeys)
      'CONSTRAINT ${quoteIdentifier(mysqlUniqueName(table.name, key))} UNIQUE (${key.map(quoteIdentifier).join(', ')})',
    for (final index in table.indexes)
      '${index.unique ? 'UNIQUE ' : ''}INDEX ${quoteIdentifier(index.name)} (${index.columns.map(quoteIdentifier).join(', ')})',
    for (final check in table.checks) checkDefinition(check, dialect),
  ];
  return 'CREATE TABLE ${quoteIdentifier(table.name)} (${definitions.join(', ')}) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin';
}

String mysqlAddForeign(String table, ForeignKey key) =>
    'ADD CONSTRAINT ${quoteIdentifier(mysqlForeignName(table, key))} ${foreignKey(key)}';

List<SqlCommand> mysqlCreateSchema(
  List<TableSchema> tables,
  SqlDialect dialect,
) {
  validateSchema(tables, dialect);
  final physical = tables.map(mysqlPhysicalTable).toList();
  return List.unmodifiable([
    for (final table in physical) SqlCommand(mysqlCreateTable(table, dialect)),
    for (final table in physical)
      if (table.foreignKeys.isNotEmpty)
        SqlCommand(
          'ALTER TABLE ${quoteIdentifier(table.name)} ${table.foreignKeys.map((key) => mysqlAddForeign(table.name, key)).join(', ')}',
        ),
  ]);
}

List<MigrationStep> mysqlCreateSteps(
  List<TableSchema> tables,
  SqlDialect dialect,
) {
  final physical = tables.map(mysqlPhysicalTable).toList();
  return [
    for (final table in physical)
      CheckedTableSql(
        mysqlCreateTable(table, dialect),
        after: mysqlCopy(table, foreignKeys: []),
      ),
    for (final table in physical)
      if (table.foreignKeys.isNotEmpty)
        CheckedTableSql(
          'ALTER TABLE ${quoteIdentifier(table.name)} ${table.foreignKeys.map((key) => mysqlAddForeign(table.name, key)).join(', ')}',
          before: mysqlCopy(table, foreignKeys: []),
          after: table,
        ),
  ];
}
