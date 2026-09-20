// Physical schema validation and engine-specific DDL.

import 'dart:convert' show utf8;

import '../../driver.dart' show SqlCommand, SqlDialect;
import '../../schema_model.dart'
    show
        CheckSchema,
        Column,
        ComputedStorage,
        ForeignKey,
        IndexSchema,
        TableSchema;
import '../../values.dart' show OrmException;
import 'columns.dart' show sqliteCollation;
import 'mysql_schema.dart'
    show
        isMysqlFamily,
        mysqlColumn,
        mysqlColumnType,
        mysqlCreateSchema,
        mysqlStorageType,
        validateMysqlSchema;
import 'sql_utils.dart' show quoteIdentifier;
import 'sqlite_checks.dart' show sqliteName;

/// Creates a new schema. Applications should execute the resulting SQL through
/// reviewed migrations; this does not inspect or mutate an existing database.
List<SqlCommand> createSchema(List<TableSchema> tables, SqlDialect dialect) {
  if (isMysqlFamily(dialect)) return mysqlCreateSchema(tables, dialect);
  final commands = <SqlCommand>[];
  validateSchema(tables, dialect);
  for (final table in tables) {
    commands.add(SqlCommand(createTable(table, dialect)));
  }
  if (dialect == SqlDialect.postgres) {
    // Creating constraints after all tables also supports cycles and self links.
    for (final table in tables) {
      for (final key in table.foreignKeys) {
        commands.add(
          SqlCommand(
            'ALTER TABLE ${quoteIdentifier(table.name)} ADD ${foreignKey(key)}',
          ),
        );
      }
    }
  }
  for (final table in tables) {
    for (final index in table.indexes) {
      commands.add(
        SqlCommand(
          'CREATE ${index.unique ? 'UNIQUE ' : ''}INDEX ${quoteIdentifier(index.name)} '
          'ON ${quoteIdentifier(table.name)} (${index.columns.map(quoteIdentifier).join(', ')})',
        ),
      );
    }
  }
  return List.unmodifiable(commands);
}

void validateSchema(List<TableSchema> tables, [SqlDialect? dialect]) {
  if (dialect != null && isMysqlFamily(dialect)) {
    validateMysqlSchema(tables, dialect);
  }
  String identifier(String name) {
    if (name.isEmpty ||
        name.contains('\u0000') ||
        dialect == SqlDialect.postgres && utf8.encode(name).length > 63) {
      throw const OrmException(
        'SCHEMA.IDENTIFIER',
        'Identifiers must be non-empty, contain no NUL, and fit PostgreSQL\'s 63-byte limit.',
      );
    }
    return dialect == SqlDialect.sqlite ? sqliteName(name) : name;
  }

  final names = <String>{};
  final indexes = <String>{};
  for (final table in tables) {
    if (!names.add(identifier(table.name))) {
      throw const OrmException('SCHEMA.DUPLICATE', 'Duplicate table name.');
    }
  }
  for (final table in tables) {
    final columns = <String>{};
    if (table.columns.every((c) => c.computed != null)) {
      throw const OrmException(
        'SCHEMA.COMPUTED',
        'A table needs at least one ordinary column.',
      );
    }
    final checkNames = <String>{};
    for (final check in table.checks) {
      if ((dialect == null
              ? check.sqlite.trim().isEmpty && check.postgres.trim().isEmpty
              : check.expression(dialect).trim().isEmpty) ||
          check.name != null && !checkNames.add(identifier(check.name!))) {
        throw const OrmException(
          'SCHEMA.CHECK',
          'CHECK expressions and names must be non-empty; names must be unique per table.',
        );
      }
    }
    for (final column in table.columns) {
      if (dialect != null) _storageType(column.codec.sqlType, dialect);
      if (column.computed case final computed?) {
        if ((dialect == null
                ? computed.sqlite.trim().isEmpty &&
                      computed.postgres.trim().isEmpty
                : computed.expression(dialect).trim().isEmpty) ||
            column.generated ||
            column.defaultSql != null ||
            column.clientDefault != null ||
            (dialect == SqlDialect.sqlite &&
                table.primaryKey.contains(column.name))) {
          throw const OrmException(
            'SCHEMA.COMPUTED',
            'Computed columns require non-empty SQL, no identity/default, and cannot be a SQLite primary key.',
          );
        }
      }
      if (column.decimalPrecision != null || column.decimalScale != null) {
        if (column.codec.sqlType != 'decimal' ||
            column.decimalPrecision == null ||
            column.decimalPrecision! < 1 ||
            column.decimalPrecision! > 1000 ||
            (column.decimalScale ?? 0) < -1000 ||
            (column.decimalScale ?? 0) > 1000) {
          throw const OrmException(
            'SCHEMA.DECIMAL_DIGITS',
            'Decimal precision must be 1..1000 and scale -1000..1000 on a decimal column.',
          );
        }
      }
      if (column.temporalPrecision != null &&
          (!{
                'time',
                'local_datetime',
                'instant',
              }.contains(column.codec.sqlType) ||
              column.temporalPrecision! < 0 ||
              column.temporalPrecision! > 6)) {
        throw const OrmException(
          'SCHEMA.TEMPORAL_PRECISION',
          'Temporal precision requires time, local timestamp or instant storage and 0..6 digits.',
        );
      }
      if (column.integerBits != null &&
          (column.codec.sqlType != 'integer' ||
              !{16, 32, 64}.contains(column.integerBits))) {
        throw const OrmException(
          'SCHEMA.INTEGER_BITS',
          'Integer width must be 16, 32 or 64 on an integer column.',
        );
      }
      if (!columns.add(identifier(column.name))) {
        throw const OrmException('SCHEMA.DUPLICATE', 'Duplicate column name.');
      }
    }
    for (final key in [
      if (table.primaryKey.isNotEmpty) table.primaryKey,
      ...table.uniqueKeys,
      ...table.indexes.map((i) => i.columns),
    ]) {
      if (key.isEmpty ||
          key.toSet().length != key.length ||
          key.any((name) => !table.columns.any((c) => c.name == name))) {
        throw const OrmException(
          'SCHEMA.KEY',
          'Keys require distinct, declared columns and cannot be empty.',
        );
      }
      if (dialect == SqlDialect.postgres &&
          key.any(
            (name) => table.columns.any(
              (c) =>
                  c.name == name &&
                  c.computed?.storage == ComputedStorage.virtual,
            ),
          )) {
        throw const OrmException(
          'SCHEMA.COMPUTED',
          'PostgreSQL 18 does not support indexes or unique keys on virtual computed columns.',
        );
      }
    }
    if (table.columns.any(
      (c) => c.nullable && table.primaryKey.contains(c.name),
    )) {
      throw const OrmException(
        'SCHEMA.KEY',
        'Primary key columns cannot be nullable.',
      );
    }
    for (final index in table.indexes) {
      final name = identifier(index.name);
      if (names.contains(name) || !indexes.add(name)) {
        throw const OrmException(
          'SCHEMA.DUPLICATE',
          'Tables and indexes must have distinct names in a schema.',
        );
      }
    }
    for (final key in table.foreignKeys) {
      foreignKey(key);
      identifier(key.target);
      if (key.columns.toSet().length != key.columns.length ||
          key.targetColumns.toSet().length != key.targetColumns.length ||
          key.columns.any(
            (name) => !table.columns.any((c) => c.name == name),
          )) {
        throw const OrmException(
          'SCHEMA.FOREIGN_KEY',
          'Foreign keys require distinct, declared local columns.',
        );
      }
      for (final name in key.targetColumns) {
        identifier(name);
      }
    }
    final generated = table.columns.where((c) => c.generated).toList();
    if (generated.length > 1 ||
        generated.any(
          (c) =>
              c.codec.sqlType != 'integer' ||
              c.nullable ||
              table.primaryKey.length != 1 ||
              table.primaryKey.single != c.name,
        )) {
      throw const OrmException(
        'SCHEMA.IDENTITY',
        'Identity requires a non-null single integer primary key.',
      );
    }
  }
}

String createTable(TableSchema table, SqlDialect dialect, {String? name}) {
  final definitions = <String>[];
  for (final c in table.columns) {
    definitions.add(columnDefinition(c, dialect));
  }
  if (table.primaryKey.isNotEmpty &&
      !(dialect == SqlDialect.sqlite &&
          table.columns.any((c) => c.generated))) {
    definitions.add(
      'PRIMARY KEY (${table.primaryKey.map(quoteIdentifier).join(', ')})',
    );
  }
  for (final key in table.uniqueKeys) {
    definitions.add('UNIQUE (${key.map(quoteIdentifier).join(', ')})');
  }
  definitions.addAll(table.checks.map((c) => checkDefinition(c, dialect)));
  if (dialect == SqlDialect.sqlite) {
    for (final key in table.foreignKeys) {
      definitions.add(foreignKey(key));
    }
  }

  return 'CREATE TABLE ${quoteIdentifier(name ?? table.name)} (${definitions.join(', ')})';
}

String checkDefinition(CheckSchema check, SqlDialect dialect) =>
    '${check.name == null ? '' : 'CONSTRAINT ${quoteIdentifier(check.name!)} '}CHECK (${check.expression(dialect)}\n)';

String columnDefinition(Column<Object?> c, SqlDialect dialect) {
  if (isMysqlFamily(dialect)) return mysqlColumn(c, dialect);
  final b = StringBuffer(
    '${quoteIdentifier(c.name)} ${columnStorageType(c, dialect)}',
  );
  if (dialect == SqlDialect.sqlite &&
      sqliteCollation(c.codec.sqlType) != 'binary') {
    b.write(' COLLATE "${sqliteCollation(c.codec.sqlType)}"');
  }
  if (c.generated) {
    b.write(
      dialect == SqlDialect.sqlite
          ? ' PRIMARY KEY'
          : ' GENERATED BY DEFAULT AS IDENTITY',
    );
  }
  if (!c.nullable) b.write(' NOT NULL');
  if (c.computed case final computed?) {
    b.write(
      ' GENERATED ALWAYS AS (${coerceColumn(computed.expression(dialect), c, dialect)}\n) ${computed.storage.name.toUpperCase()}',
    );
  }
  if (c.defaultSql case final value?) {
    b.write(' DEFAULT (${coerceColumn(value, c, dialect)})');
  }
  if (dialect == SqlDialect.sqlite &&
      c.temporalPrecision != null &&
      c.temporalPrecision != 6) {
    b.write(
      ' CHECK (${temporalCheck(c.name, c.codec.sqlType, c.temporalPrecision!)})',
    );
  }
  if (dialect == SqlDialect.sqlite && c.decimalPrecision != null) {
    b.write(
      ' CHECK (${decimalCheck(c.name, c.decimalPrecision!, c.decimalScale ?? 0)})',
    );
  }
  if (dialect == SqlDialect.sqlite &&
      c.integerBits != null &&
      c.integerBits != 64) {
    b.write(' CHECK (${integerCheck(c.name, c.integerBits!)})');
  }
  return b.toString();
}

String createIndexSql(String table, IndexSchema index) =>
    'CREATE ${index.unique ? 'UNIQUE ' : ''}INDEX ${quoteIdentifier(index.name)} '
    'ON ${quoteIdentifier(table)} (${index.columns.map(quoteIdentifier).join(', ')})';

String foreignKey(ForeignKey key) {
  if (key.columns.isEmpty ||
      key.columns.length != key.targetColumns.length ||
      !{
        'RESTRICT',
        'NO ACTION',
        'CASCADE',
        'SET NULL',
        'SET DEFAULT',
      }.contains(key.onDelete)) {
    throw const OrmException(
      'SCHEMA.FOREIGN_KEY',
      'Invalid foreign key declaration.',
    );
  }
  return 'FOREIGN KEY (${key.columns.map(quoteIdentifier).join(', ')}) REFERENCES ${quoteIdentifier(key.target)} '
      '(${key.targetColumns.map(quoteIdentifier).join(', ')}) ON DELETE ${key.onDelete}';
}

String _storageType(String type, SqlDialect dialect) => isMysqlFamily(dialect)
    ? mysqlStorageType(type)
    : switch ((dialect, type)) {
        (SqlDialect.sqlite, 'integer') => 'INTEGER',
        (
          SqlDialect.sqlite,
          'bigint' ||
              'text' ||
              'timestamp' ||
              'instant' ||
              'json' ||
              'decimal' ||
              'date' ||
              'time' ||
              'local_datetime',
        ) =>
          'TEXT',
        (SqlDialect.sqlite, 'boolean') => 'INTEGER',
        (SqlDialect.sqlite, 'real') => 'REAL',
        (SqlDialect.sqlite, 'blob') => 'BLOB',
        (SqlDialect.postgres, 'integer') => 'BIGINT',
        (SqlDialect.postgres, 'bigint' || 'decimal') => 'NUMERIC',
        (SqlDialect.postgres, 'text') => 'TEXT',
        (SqlDialect.postgres, 'real') => 'DOUBLE PRECISION',
        (SqlDialect.postgres, 'boolean') => 'BOOLEAN',
        (SqlDialect.postgres, 'timestamp' || 'instant') => 'TIMESTAMPTZ',
        (SqlDialect.postgres, 'date') => 'DATE',
        (SqlDialect.postgres, 'time') => 'TIME WITHOUT TIME ZONE',
        (SqlDialect.postgres, 'local_datetime') =>
          'TIMESTAMP WITHOUT TIME ZONE',
        (SqlDialect.postgres, 'json') => 'JSONB',
        (SqlDialect.postgres, 'blob') => 'BYTEA',
        _ => throw OrmException(
          'SCHEMA.TYPE',
          'No $dialect mapping for $type.',
        ),
      };

String columnStorageType(Column<Object?> column, SqlDialect dialect) =>
    isMysqlFamily(dialect)
    ? mysqlColumnType(column)
    : dialect == SqlDialect.postgres &&
          column.codec.sqlType == 'decimal' &&
          column.decimalPrecision != null
    ? 'NUMERIC(${column.decimalPrecision},${column.decimalScale ?? 0})'
    : dialect == SqlDialect.postgres && column.codec.sqlType == 'integer'
    ? switch (column.integerBits ?? 64) {
        16 => 'SMALLINT',
        32 => 'INTEGER',
        _ => 'BIGINT',
      }
    : dialect == SqlDialect.postgres &&
          column.temporalPrecision != null &&
          column.temporalPrecision != 6
    ? switch (column.codec.sqlType) {
        'time' => 'TIME(${column.temporalPrecision}) WITHOUT TIME ZONE',
        'local_datetime' =>
          'TIMESTAMP(${column.temporalPrecision}) WITHOUT TIME ZONE',
        'instant' => 'TIMESTAMPTZ(${column.temporalPrecision})',
        _ => throw const OrmException(
          'SCHEMA.TEMPORAL_PRECISION',
          'Temporal precision requires temporal storage.',
        ),
      }
    : _storageType(column.codec.sqlType, dialect);

bool sameStorage(Column<Object?> a, Column<Object?> b) =>
    a.codec.sqlType == b.codec.sqlType &&
    (a.temporalPrecision ?? 6) == (b.temporalPrecision ?? 6) &&
    (a.integerBits ?? 64) == (b.integerBits ?? 64) &&
    a.decimalPrecision == b.decimalPrecision &&
    (a.decimalScale ?? 0) == (b.decimalScale ?? 0);

String coerceColumn(
  String expression,
  Column<Object?> column,
  SqlDialect dialect,
) => dialect == SqlDialect.sqlite && column.decimalPrecision != null
    ? 'orm_decimal_cast_v1($expression, ${column.decimalPrecision}, ${column.decimalScale ?? 0})'
    : dialect == SqlDialect.sqlite &&
          column.temporalPrecision != null &&
          column.temporalPrecision != 6
    ? "orm_temporal_cast_v1($expression, '${column.codec.sqlType}', ${column.temporalPrecision})"
    : expression;

String temporalCheck(String name, String kind, int digits) =>
    "${quoteIdentifier(name)} IS NULL OR orm_temporal_fits_v1(${quoteIdentifier(name)}, '$kind', $digits)";

String decimalCheck(String name, int precision, int scale) =>
    '${quoteIdentifier(name)} IS NULL OR orm_decimal_fits_v1(${quoteIdentifier(name)}, $precision, $scale)';

String integerCheck(String name, int bits) {
  final column = quoteIdentifier(name), max = bits == 16 ? 32767 : 2147483647;
  return "$column IS NULL OR (typeof($column) = 'integer' AND $column BETWEEN ${-max - 1} AND $max)";
}
