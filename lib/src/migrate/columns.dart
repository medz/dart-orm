// Live column inspection and comparison with declared storage.

import '../../driver.dart' show Backend, SqlCommand, SqlDialect;
import '../../runtime.dart' show SqlDatabase;
import '../../values.dart' show OrmException;
import '../../schema_model.dart'
    show Column, ComputedColumn, ComputedStorage, TableSchema;
import 'catalog.dart' show normalizeDefault;
import 'computed.dart'
    show computedDeclaration, sqliteComputedColumns, verifyComputed;
import 'mysql_catalog.dart' show mysqlColumns;
import 'mysql_schema.dart' show isMysqlFamily;
import 'schema.dart' show columnStorageType;
import 'sql_utils.dart' show quoteIdentifier;
import 'sqlite_checks.dart'
    show
        sqliteChecks,
        sqliteColumnCollations,
        sqliteDecimalDigits,
        sqliteIntegerBits,
        sqliteName,
        sqliteTemporalPrecision,
        uncoerceDecimalDefault,
        uncoerceTemporal;

/// Actual catalog columns, rather than a claimed migration version.
final class ColumnInfo {
  /// Physical column name.
  final String name;

  /// Database storage type as normalized by the engine's catalog reader.
  final String storageType;

  /// Whether the inspected column permits SQL NULL.
  final bool nullable;

  /// Catalog default expression, or null when no SQL default is present.
  final String? defaultSql;

  /// Engine-specific generated, hidden, or identity flag from the catalog.
  ///
  /// [computed] independently describes a recognized computed expression.
  final bool generated;

  /// Database-computed expression and storage mode, when recognized.
  final ComputedColumn? computed;

  /// Recognized signed integer width, or null when not applicable or unknown.
  final int? integerBits;

  /// Catalog collation name, including ORM storage collations where applicable.
  final String? collation;

  /// Recognized maximum decimal digits, or null for unconstrained/other storage.
  final int? decimalPrecision;

  /// Recognized decimal fractional digits, or null when not constrained.
  final int? decimalScale;

  /// Recognized fractional-second precision, or null for other storage.
  final int? temporalPrecision;

  /// Records physical column facts without interpreting them as a Dart model.
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
      ? uncoerceDecimalDefault(
              normalizeDefault(defaultSql)!,
              decimalPrecision!,
              decimalScale ?? 0,
            ) ??
            defaultSql
      : defaultSql != null && storageType == 'TEXT' && temporalPrecision != null
      ? uncoerceTemporal(
              normalizeDefault(defaultSql)!,
              temporalCollationKind(collation)!,
              temporalPrecision!,
            ) ??
            defaultSql
      : defaultSql;

  /// SQL suitable for a declaration, without ORM storage coercion wrappers.
  ComputedColumn? get declarationComputed => computedDeclaration(this);
}

/// Reads storage types, nullability, defaults, and computed-column metadata.
Future<List<ColumnInfo>> inspectColumns(
  SqlDatabase<Backend> db,
  String table, {
  String? namespace,
}) async {
  if (namespace != null && db.dialect != SqlDialect.postgres) {
    throw const OrmException(
      'SCHEMA.NAMESPACE',
      'Database schemas require PostgreSQL.',
    );
  }
  if (isMysqlFamily(db.dialect)) return mysqlColumns(db, table);
  if (db.dialect == SqlDialect.sqlite) {
    final rows = await db.execute(
      SqlCommand('PRAGMA table_xinfo(${quoteIdentifier(table)})'),
    );
    final indexes = await db.execute(
      SqlCommand('PRAGMA index_list(${quoteIdentifier(table)})'),
    );
    final rowidPrimaryKey = !indexes.rows.any((r) => r[3] == 'pk');
    final ddl = await db.execute(
      SqlCommand(
        "SELECT sql FROM main.sqlite_schema WHERE type = 'table' AND name = ?1",
        [table],
      ),
    );
    final sql = ddl.rows.firstOrNull?.first as String? ?? '';
    final checks = sqliteChecks(sql);
    final computed = sqliteComputedColumns(sql);
    final collations = {
      for (final c in sqliteColumnCollations(sql))
        sqliteName(c.column): c.collation,
    };
    final columns = <ColumnInfo>[];
    for (final row in rows.rows) {
      final name = row[1] as String;
      final type = (row[2] as String).toUpperCase();
      final collation = collations[sqliteName(name)] ?? 'BINARY';
      final digits =
          type == 'TEXT' && collation.toLowerCase() == 'orm_decimal_v1'
          ? sqliteDecimalDigits(name, checks)
          : null;
      columns.add(
        ColumnInfo(
          name: name,
          storageType: type,
          collation: collation,
          decimalPrecision: digits?.$1,
          decimalScale: digits?.$2,
          temporalPrecision:
              type == 'TEXT' && temporalCollationKind(collation) != null
              ? sqliteTemporalPrecision(
                  name,
                  temporalCollationKind(collation)!,
                  checks,
                )
              : null,
          nullable: row[3] == 0 && !(row[5] != 0 && rowidPrimaryKey),
          defaultSql: row[4] as String?,
          generated: (row[6] as int) > 0,
          computed: computed[sqliteName(name)],
          integerBits: type == 'INTEGER'
              ? sqliteIntegerBits(name, checks)
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
WHERE c.relname = \$1 AND n.nspname = coalesce(\$2::text, current_schema()) AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY a.attnum''',
      [table, namespace],
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
  SqlDatabase<Backend> db,
  List<TableSchema> tables,
) async {
  final differences = <String>[];
  for (final table in tables) {
    final inspected = await inspectColumns(
      db,
      table.name,
      namespace: table.namespace,
    );
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
      if (column.storageType != columnStorageType(expected, db.dialect)) {
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
      if (!matchesDecimalDigits(expected, column)) {
        differences.add('$path decimal precision/scale differs');
      }
      if (db.dialect == SqlDialect.sqlite &&
          !matchesCollation(expected, column)) {
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
      await verifyComputed(
        db,
        table,
        inspected,
        contextMatches: contextMatches,
      ),
    );
  }
  return differences;
}

bool matchesCollation(Column<Object?> expected, ColumnInfo actual) =>
    (actual.collation ?? 'BINARY').toLowerCase() ==
    sqliteCollation(expected.codec.sqlType);

String sqliteCollation(String type) => switch (type) {
  'decimal' ||
  'date' ||
  'time' ||
  'local_datetime' ||
  'instant' => 'orm_${type}_v1',
  _ => 'binary',
};

bool matchesDecimalDigits(Column<Object?> expected, ColumnInfo actual) =>
    expected.decimalPrecision == actual.decimalPrecision &&
    (expected.decimalScale ?? 0) == (actual.decimalScale ?? 0);

(int, int)? _postgresDecimalDigits(String type) {
  final match = RegExp(
    r'^numeric\((\d+),(-?\d+)\)$',
    caseSensitive: false,
  ).firstMatch(type.replaceAll(' ', ''));
  return match == null ? null : (int.parse(match[1]!), int.parse(match[2]!));
}

String? temporalCollationKind(String? collation) =>
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
