part of '../../migrate.dart';

/// Creates a new schema. Applications should execute the resulting SQL through
/// reviewed migrations; this does not inspect or mutate an existing database.
List<SqlCommand> createSchema(List<TableSchema> tables, SqlDialect dialect) {
  final commands = <SqlCommand>[];
  _validateSchema(tables, dialect);
  for (final table in tables) {
    commands.add(SqlCommand(_createTable(table, dialect)));
  }
  if (dialect == SqlDialect.postgres) {
    // Creating constraints after all tables also supports cycles and self links.
    for (final table in tables) {
      for (final key in table.foreignKeys) {
        commands.add(
          SqlCommand(
            'ALTER TABLE ${_quote(table.name)} ADD ${_foreignKey(key)}',
          ),
        );
      }
    }
  }
  for (final table in tables) {
    for (final index in table.indexes) {
      commands.add(
        SqlCommand(
          'CREATE ${index.unique ? 'UNIQUE ' : ''}INDEX ${_quote(index.name)} '
          'ON ${_quote(table.name)} (${index.columns.map(_quote).join(', ')})',
        ),
      );
    }
  }
  return List.unmodifiable(commands);
}

void _validateSchema(List<TableSchema> tables, [SqlDialect? dialect]) {
  final names = <String>{};
  for (final table in tables) {
    if (!names.add(table.name)) {
      throw const OrmException('SCHEMA.DUPLICATE', 'Duplicate table name.');
    }
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
          check.name != null &&
              (check.name!.isEmpty ||
                  !checkNames.add(_sqliteName(check.name!)))) {
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
      if (!columns.add(column.name)) {
        throw const OrmException('SCHEMA.DUPLICATE', 'Duplicate column name.');
      }
    }
    for (final key in [
      table.primaryKey,
      ...table.uniqueKeys,
      ...table.indexes.map((i) => i.columns),
    ]) {
      if (key.any((name) => !columns.contains(name))) {
        throw const OrmException(
          'SCHEMA.KEY',
          'Key references an unknown column.',
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

String _createTable(TableSchema table, SqlDialect dialect, {String? name}) {
  final definitions = <String>[];
  for (final c in table.columns) {
    definitions.add(_columnDefinition(c, dialect));
  }
  if (table.primaryKey.isNotEmpty &&
      !(dialect == SqlDialect.sqlite &&
          table.columns.any((c) => c.generated))) {
    definitions.add('PRIMARY KEY (${table.primaryKey.map(_quote).join(', ')})');
  }
  for (final key in table.uniqueKeys) {
    definitions.add('UNIQUE (${key.map(_quote).join(', ')})');
  }
  definitions.addAll(table.checks.map((c) => _checkDefinition(c, dialect)));
  if (dialect == SqlDialect.sqlite) {
    for (final key in table.foreignKeys) {
      definitions.add(_foreignKey(key));
    }
  }

  return 'CREATE TABLE ${_quote(name ?? table.name)} (${definitions.join(', ')})';
}

String _checkDefinition(CheckSchema check, SqlDialect dialect) =>
    '${check.name == null ? '' : 'CONSTRAINT ${_quote(check.name!)} '}CHECK (${check.expression(dialect)}\n)';

String _columnDefinition(Column<Object?> c, SqlDialect dialect) {
  final b = StringBuffer('${_quote(c.name)} ${_columnStorageType(c, dialect)}');
  if (dialect == SqlDialect.sqlite &&
      _sqliteCollation(c.codec.sqlType) != 'binary') {
    b.write(' COLLATE "${_sqliteCollation(c.codec.sqlType)}"');
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
      ' GENERATED ALWAYS AS (${_coerceColumn(computed.expression(dialect), c, dialect)}\n) ${computed.storage.name.toUpperCase()}',
    );
  }
  if (c.defaultSql case final value?) {
    b.write(' DEFAULT (${_coerceColumn(value, c, dialect)})');
  }
  if (dialect == SqlDialect.sqlite &&
      c.temporalPrecision != null &&
      c.temporalPrecision != 6) {
    b.write(
      ' CHECK (${_temporalCheck(c.name, c.codec.sqlType, c.temporalPrecision!)})',
    );
  }
  if (dialect == SqlDialect.sqlite && c.decimalPrecision != null) {
    b.write(
      ' CHECK (${_decimalCheck(c.name, c.decimalPrecision!, c.decimalScale ?? 0)})',
    );
  }
  if (dialect == SqlDialect.sqlite &&
      c.integerBits != null &&
      c.integerBits != 64) {
    b.write(' CHECK (${_integerCheck(c.name, c.integerBits!)})');
  }
  return b.toString();
}

String _createIndex(String table, IndexSchema index) =>
    'CREATE ${index.unique ? 'UNIQUE ' : ''}INDEX ${_quote(index.name)} '
    'ON ${_quote(table)} (${index.columns.map(_quote).join(', ')})';

String _foreignKey(ForeignKey key) {
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
  return 'FOREIGN KEY (${key.columns.map(_quote).join(', ')}) REFERENCES ${_quote(key.target)} '
      '(${key.targetColumns.map(_quote).join(', ')}) ON DELETE ${key.onDelete}';
}

String _storageType(String type, SqlDialect dialect) =>
    switch ((dialect, type)) {
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
      (SqlDialect.postgres, 'local_datetime') => 'TIMESTAMP WITHOUT TIME ZONE',
      (SqlDialect.postgres, 'json') => 'JSONB',
      (SqlDialect.postgres, 'blob') => 'BYTEA',
      _ => throw OrmException('SCHEMA.TYPE', 'No $dialect mapping for $type.'),
    };

String _columnStorageType(Column<Object?> column, SqlDialect dialect) =>
    dialect == SqlDialect.postgres &&
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

bool _sameStorage(Column<Object?> a, Column<Object?> b) =>
    a.codec.sqlType == b.codec.sqlType &&
    (a.temporalPrecision ?? 6) == (b.temporalPrecision ?? 6) &&
    (a.integerBits ?? 64) == (b.integerBits ?? 64) &&
    a.decimalPrecision == b.decimalPrecision &&
    (a.decimalScale ?? 0) == (b.decimalScale ?? 0);

String _coerceColumn(
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

String _temporalCheck(String name, String kind, int digits) =>
    "${_quote(name)} IS NULL OR orm_temporal_fits_v1(${_quote(name)}, '$kind', $digits)";

String _decimalCheck(String name, int precision, int scale) =>
    '${_quote(name)} IS NULL OR orm_decimal_fits_v1(${_quote(name)}, $precision, $scale)';

String _integerCheck(String name, int bits) {
  final column = _quote(name), max = bits == 16 ? 32767 : 2147483647;
  return "$column IS NULL OR (typeof($column) = 'integer' AND $column BETWEEN ${-max - 1} AND $max)";
}

/// Actual catalog columns, rather than a claimed migration version.
final class ColumnInfo {
  final String name;
  final String storageType;
  final bool nullable;
  final String? defaultSql;
  final bool generated;
  final ComputedColumn? computed;
  final int? integerBits;
  final String? collation;
  final int? decimalPrecision;
  final int? decimalScale;
  final int? temporalPrecision;
  const ColumnInfo({
    required this.name,
    required this.storageType,
    required this.nullable,
    this.defaultSql,
    this.generated = false,
    this.computed,
    this.integerBits,
    this.collation,
    this.decimalPrecision,
    this.decimalScale,
    this.temporalPrecision,
  });

  /// Removes the managed SQLite default coercion when drafting a declaration.
  String? get declarationDefaultSql =>
      defaultSql != null && storageType == 'TEXT' && decimalPrecision != null
      ? _uncoerceDecimalDefault(
              _normalizeDefault(defaultSql)!,
              decimalPrecision!,
              decimalScale ?? 0,
            ) ??
            defaultSql
      : defaultSql != null && storageType == 'TEXT' && temporalPrecision != null
      ? _uncoerceTemporal(
              _normalizeDefault(defaultSql)!,
              _temporalCollationKind(collation)!,
              temporalPrecision!,
            ) ??
            defaultSql
      : defaultSql;

  /// SQL suitable for a declaration, without ORM storage coercion wrappers.
  ComputedColumn? get declarationComputed => _declarationComputed(this);
}

Future<List<ColumnInfo>> inspectColumns(
  Database<Backend> db,
  String table,
) async {
  if (db.dialect == SqlDialect.sqlite) {
    final rows = await db.execute(
      SqlCommand('PRAGMA table_xinfo(${_quote(table)})'),
    );
    final indexes = await db.execute(
      SqlCommand('PRAGMA index_list(${_quote(table)})'),
    );
    final rowidPrimaryKey = !indexes.rows.any((r) => r[3] == 'pk');
    final ddl = await db.execute(
      SqlCommand(
        "SELECT sql FROM main.sqlite_schema WHERE type = 'table' AND name = ?1",
        [table],
      ),
    );
    final sql = ddl.rows.firstOrNull?.first as String? ?? '';
    final checks = _sqliteChecks(sql);
    final computed = _sqliteComputedColumns(sql);
    final collations = {
      for (final c in _sqliteColumnCollations(sql))
        _sqliteName(c.column): c.collation,
    };
    final columns = <ColumnInfo>[];
    for (final row in rows.rows) {
      final name = row[1] as String;
      final type = (row[2] as String).toUpperCase();
      final collation = collations[_sqliteName(name)] ?? 'BINARY';
      final digits =
          type == 'TEXT' && collation.toLowerCase() == 'orm_decimal_v1'
          ? _sqliteDecimalDigits(name, checks)
          : null;
      columns.add(
        ColumnInfo(
          name: name,
          storageType: type,
          collation: collation,
          decimalPrecision: digits?.$1,
          decimalScale: digits?.$2,
          temporalPrecision:
              type == 'TEXT' && _temporalCollationKind(collation) != null
              ? _sqliteTemporalPrecision(
                  name,
                  _temporalCollationKind(collation)!,
                  checks,
                )
              : null,
          nullable: row[3] == 0 && !(row[5] != 0 && rowidPrimaryKey),
          defaultSql: row[4] as String?,
          generated: (row[6] as int) > 0,
          computed: computed[_sqliteName(name)],
          integerBits: type == 'INTEGER'
              ? _sqliteIntegerBits(name, checks)
              : null,
        ),
      );
    }
    return columns;
  }

  final result = await db.execute(
    SqlCommand(
      '''
SELECT a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod),
       NOT a.attnotnull, pg_get_expr(d.adbin, d.adrelid),
       a.attidentity <> '' OR a.attgenerated <> '', a.attgenerated::text
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
WHERE c.relname = \$1 AND n.nspname = current_schema() AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum''',
      [table],
    ),
  );
  return [
    for (final row in result.rows)
      ColumnInfo(
        name: row[0] as String,
        storageType: _postgresStorageName(row[1] as String),
        temporalPrecision: _postgresTemporalPrecision(row[1] as String),
        nullable: row[2] as bool,
        defaultSql: row[5] == '' ? row[3] as String? : null,
        generated: row[4] as bool,
        computed: row[5] == ''
            ? null
            : ComputedColumn(
                row[3] as String,
                storage: row[5] == 's'
                    ? ComputedStorage.stored
                    : ComputedStorage.virtual,
              ),
        decimalPrecision: _postgresDecimalDigits(row[1] as String)?.$1,
        decimalScale: _postgresDecimalDigits(row[1] as String)?.$2,
        integerBits: switch ((row[1] as String).toUpperCase()) {
          'SMALLINT' => 16,
          'INTEGER' => 32,
          'BIGINT' => 64,
          _ => null,
        },
      ),
  ];
}

/// Column drift check. Constraints, indexes and unmanaged objects are separate
/// catalog checks; this method does not pretend that columns prove full equality.
Future<List<String>> verifyColumns(
  Database<Backend> db,
  List<TableSchema> tables,
) async {
  final differences = <String>[];
  for (final table in tables) {
    final inspected = await inspectColumns(db, table.name);
    final actual = {for (final c in inspected) c.name: c};
    var contextMatches = true;
    for (final expected in table.columns) {
      final column = actual.remove(expected.name);
      final path = '${table.name}.${expected.name}';
      if (column == null) {
        contextMatches = false;
        differences.add('$path is missing');
        continue;
      }
      if (column.storageType != _columnStorageType(expected, db.dialect)) {
        contextMatches = false;
        differences.add('$path type is ${column.storageType}');
      }
      if (column.nullable != expected.nullable) {
        differences.add('$path nullability differs');
      }
      if ((column.temporalPrecision ?? 6) !=
          (expected.temporalPrecision ?? 6)) {
        differences.add('$path temporal precision differs');
      }
      if (!_matchesDecimalDigits(expected, column)) {
        differences.add('$path decimal precision/scale differs');
      }
      if (db.dialect == SqlDialect.sqlite &&
          !_matchesCollation(expected, column)) {
        differences.add('$path collation differs');
      }
      if (expected.codec.sqlType == 'integer' &&
          (column.integerBits ?? 64) != (expected.integerBits ?? 64)) {
        differences.add('$path integer width differs');
      }
    }
    for (final extra in actual.keys) {
      differences.add('${table.name}.$extra is unmanaged');
    }
    differences.addAll(
      await _verifyComputed(
        db,
        table,
        inspected,
        contextMatches: contextMatches,
      ),
    );
  }
  return differences;
}

bool _matchesCollation(Column<Object?> expected, ColumnInfo actual) =>
    (actual.collation ?? 'BINARY').toLowerCase() ==
    _sqliteCollation(expected.codec.sqlType);

String _sqliteCollation(String type) => switch (type) {
  'decimal' ||
  'date' ||
  'time' ||
  'local_datetime' ||
  'instant' => 'orm_${type}_v1',
  _ => 'binary',
};

bool _matchesDecimalDigits(Column<Object?> expected, ColumnInfo actual) =>
    expected.decimalPrecision == actual.decimalPrecision &&
    (expected.decimalScale ?? 0) == (actual.decimalScale ?? 0);

(int, int)? _postgresDecimalDigits(String type) {
  final match = RegExp(
    r'^numeric\((\d+),(-?\d+)\)$',
    caseSensitive: false,
  ).firstMatch(type.replaceAll(' ', ''));
  return match == null ? null : (int.parse(match[1]!), int.parse(match[2]!));
}

String? _temporalCollationKind(String? collation) =>
    switch (collation?.toLowerCase()) {
      'orm_time_v1' => 'time',
      'orm_local_datetime_v1' => 'local_datetime',
      'orm_instant_v1' => 'instant',
      _ => null,
    };

int? _postgresTemporalPrecision(String type) {
  final match = RegExp(
    r'^(?:time|timestamp)\(([0-6])\) (?:with|without) time zone$',
    caseSensitive: false,
  ).firstMatch(type);
  return match == null ? null : int.parse(match[1]!);
}

String _postgresStorageName(String type) {
  var name = type.toUpperCase().replaceFirstMapped(
    RegExp(r'^TIMESTAMP(\([0-6]\))? WITH TIME ZONE$'),
    (m) => 'TIMESTAMPTZ${m[1] ?? ''}',
  );
  if (_postgresTemporalPrecision(type) == 6) {
    name = name.replaceFirst('(6)', '');
  }
  return name;
}
