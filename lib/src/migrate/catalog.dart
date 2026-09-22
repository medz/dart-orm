import 'dart:convert' show jsonEncode;

import '../../driver.dart' show Backend, SqlCommand, SqlDialect;
import '../../values.dart' show OrmException;
import '../../runtime.dart' show SqlDatabase;
import '../../schema_model.dart' show Column, ForeignKey, IndexSchema;
import '../../values.dart'
    show Codecs, Decimal, InstantPrecision, LocalDate, LocalDateTime, LocalTime;
import 'checks.dart' show CheckInfo, matchChecks;
import 'columns.dart'
    show ColumnInfo, inspectColumns, matchesCollation, matchesDecimalDigits;
import 'computed.dart' show verifyComputed, withoutComputed;
import 'mysql_catalog.dart' show mysqlTable, mysqlVerifySchema;
import 'mysql_schema.dart' show isMysqlFamily;
import 'schema.dart' show coerceColumn, columnStorageType;
import 'snapshot.dart' show SchemaSnapshot, foreignKeyJson, indexJson;
import 'sql_utils.dart'
    show canonicalMigrationValue, migrationHash, quoteIdentifier;
import 'sqlite_checks.dart'
    show
        sqliteChecks,
        uncoerceDecimalDefault,
        uncoerceTemporal,
        withoutIntegerChecks,
        withoutStorageCollations;
import 'validation.dart' show sqlWords;

/// A live database object outside the schema features modeled by the ORM.
final class CatalogObject {
  /// Catalog object category, such as `index`, `trigger`, or `view`.
  final String kind;

  /// Physical object name, as reported by the catalog reader.
  final String name;

  /// Catalog SQL or descriptive metadata preserved for manual review.
  final String definition;

  /// Records an object that the ORM cannot safely recreate from modeled fields.
  const CatalogObject(this.kind, this.name, this.definition);
}

/// Physical table facts read from the selected database's catalog.
///
/// [unmanaged] preserves descriptions of objects a migration must not silently
/// replace, such as custom triggers or unsupported index definitions.
final class TableInfo {
  /// PostgreSQL schema explicitly selected for this inspection.
  final String? namespace;

  /// Physical table name used for this inspection.
  final String name;

  /// Column storage metadata in catalog order.
  final List<ColumnInfo> columns;

  /// Primary-key column names in key order; empty when no key exists.
  final List<String> primaryKey;

  /// Modeled unique constraints, each retaining its own column order.
  final List<List<String>> uniqueKeys;

  /// Modeled foreign-key columns, target tables, and deletion actions.
  final List<ForeignKey> foreignKeys;

  /// Index definitions expressible by the ORM's physical schema model.
  final List<IndexSchema> indexes;

  /// Objects requiring separate review before a table rebuild or schema change.
  final List<CatalogObject> unmanaged;

  /// Enforced row CHECK constraints recognized by the catalog reader.
  final List<CheckInfo> checks;

  /// Groups catalog facts without querying or changing the database.
  ///
  /// Supplied lists are retained; use [inspectTable] to obtain live metadata.
  const TableInfo({
    required this.name,
    this.namespace,
    required this.columns,
    required this.primaryKey,
    required this.uniqueKeys,
    required this.foreignKeys,
    required this.indexes,
    required this.unmanaged,
    this.checks = const [],
  });
}

/// Differences between a declared snapshot and the live database catalog.
final class SchemaVerification {
  /// Human-readable mismatches in modeled schema facts.
  final List<String> differences;

  /// Live objects that require separate review, even when [matches] is true.
  final List<CatalogObject> unmanaged;

  /// Records modeled differences and separately reviewable catalog objects.
  const SchemaVerification(this.differences, this.unmanaged);

  /// Equality of the declared schema facts; inspect unmanaged objects separately.
  bool get matches => differences.isEmpty;
}

/// Reads one physical [table] without changing its schema or data.
Future<TableInfo> inspectTable(
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
  if (isMysqlFamily(db.dialect)) return mysqlTable(db, table);
  final columns = await inspectColumns(db, table, namespace: namespace);
  final primary = <String>[],
      unique = <List<String>>[],
      indexes = <IndexSchema>[];
  final foreign = <ForeignKey>[], unmanaged = <CatalogObject>[];
  final checks = <CheckInfo>[];
  if (db.dialect == SqlDialect.sqlite) {
    final info = await db.execute(
      SqlCommand('PRAGMA table_xinfo(${quoteIdentifier(table)})'),
    );
    final primaryRows = info.rows.where((r) => (r[5] as int) > 0).toList()
      ..sort((a, b) => (a[5] as int).compareTo(b[5] as int));
    primary.addAll(primaryRows.map((r) => r[1] as String));
    final list = await db.execute(
      SqlCommand('PRAGMA index_list(${quoteIdentifier(table)})'),
    );
    for (final row in list.rows) {
      final name = row[1] as String;
      final parts = await db.execute(
        SqlCommand('PRAGMA index_xinfo(${quoteIdentifier(name)})'),
      );
      final keys = parts.rows.where((r) => r[5] == 1).toList();
      final sql = await db.execute(
        SqlCommand(
          'SELECT sql FROM sqlite_schema WHERE type = \'index\' AND name = ?1',
          [name],
        ),
      );
      final definition = sql.rows.firstOrNull?.first as String? ?? '';
      if (row[4] == 1 ||
          keys.any(
            (r) =>
                r[2] == null ||
                r[3] != 0 ||
                (r[4] as String).toLowerCase() !=
                    (columns.firstWhere((c) => c.name == r[2]).collation ??
                            'BINARY')
                        .toLowerCase(),
          )) {
        unmanaged.add(CatalogObject('index', name, definition));
        continue;
      }
      final names = keys.map((r) => r[2] as String).toList();
      if (row[3] == 'u') {
        unique.add(names);
      } else if (row[3] != 'pk') {
        indexes.add(IndexSchema(name, names, unique: row[2] == 1));
      }
    }
    final keys = await db.execute(
      SqlCommand('PRAGMA foreign_key_list(${quoteIdentifier(table)})'),
    );
    final grouped = <int, List<List<Object?>>>{};
    for (final row in keys.rows) {
      (grouped[row[0] as int] ??= []).add(row);
    }
    for (final rows in grouped.values) {
      rows.sort((a, b) => (a[1] as int).compareTo(b[1] as int));
      if (rows.any((r) => r[4] == null) ||
          rows.first[5] != 'NO ACTION' ||
          rows.first[7] != 'NONE') {
        unmanaged.add(
          CatalogObject(
            'foreign key',
            '$table#${rows.first[0]}',
            rows.toString(),
          ),
        );
        continue;
      }
      foreign.add(
        ForeignKey(
          rows.map((r) => r[3] as String).toList(),
          rows.first[2] as String,
          rows.map((r) => r[4] as String).toList(),
          onDelete: rows.first[6] as String,
        ),
      );
    }
    final objects = await db.execute(
      SqlCommand(
        "SELECT type, name, sql FROM sqlite_schema WHERE (tbl_name = ?1 AND type = 'trigger') OR type = 'view'",
        [table],
      ),
    );
    for (final row in objects.rows) {
      unmanaged.add(
        CatalogObject(row[0] as String, row[1] as String, row[2] as String),
      );
    }
    final ddl = await db.execute(
      SqlCommand(
        "SELECT sql FROM sqlite_schema WHERE type = 'table' AND name = ?1",
        [table],
      ),
    );
    final sql = ddl.rows.firstOrNull?.first as String?;
    var withoutChecks = sql ?? '';
    if (sql != null) {
      // Storage checks retain their existing column-width/precision meaning.
      final remaining = withoutIntegerChecks(sql, columns);
      final parsed = sqliteChecks(remaining);
      checks.addAll(parsed.map((c) => CheckInfo(c.name, c.expression)));
      final text = StringBuffer();
      var start = 0;
      for (final check in parsed) {
        text.write(remaining.substring(start, check.start));
        start = check.end;
      }
      withoutChecks = (text..write(remaining.substring(start))).toString();
    }
    if (sql != null &&
        sqlWords(
          withoutStorageCollations(withoutComputed(withoutChecks), columns),
        ).any(
          {
            'CHECK',
            'DEFERRABLE',
            'COLLATE',
            'STRICT',
            'WITHOUT',
            'AUTOINCREMENT',
            'CONFLICT',
          }.contains,
        )) {
      unmanaged.add(CatalogObject('table options', table, sql));
    }
  } else {
    final constraints = await db.execute(
      SqlCommand(
        r'''
SELECT c.conname, c.contype::text,
 ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(num, ord)
       JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.num ORDER BY k.ord),
 t.relname,
 ARRAY(SELECT a.attname::text FROM unnest(c.confkey) WITH ORDINALITY k(num, ord)
       JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.num ORDER BY k.ord),
 c.confdeltype::text, c.confupdtype::text, c.confmatchtype::text,
 c.condeferrable, c.convalidated, pg_get_constraintdef(c.oid), tn.nspname,
 coalesce((to_jsonb(i)->>'indnullsnotdistinct')::boolean, false),
 pg_get_expr(c.conbin, c.conrelid), c.connoinherit, c.conislocal, c.coninhcount,
 coalesce((to_jsonb(c)->>'conenforced')::boolean, true)
FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
JOIN pg_namespace n ON n.oid = r.relnamespace
LEFT JOIN pg_class t ON t.oid = c.confrelid
LEFT JOIN pg_namespace tn ON tn.oid = t.relnamespace
LEFT JOIN pg_index i ON i.indexrelid = c.conindid
WHERE n.nspname = coalesce($2::text, current_schema()) AND r.relname = $1''',
        [table, namespace],
      ),
    );
    final schemaName =
        namespace ??
        (await db.execute(SqlCommand('SELECT current_schema()')))
            .rows
            .single
            .single;
    for (final row in constraints.rows) {
      final kind = row[1] as String,
          keys = (row[2] as List<Object?>).cast<String>();
      if (kind == 'p') {
        primary.addAll(keys);
        if (row[8] == true || row[9] != true) {
          unmanaged.add(
            CatalogObject('constraint', row[0] as String, row[10] as String),
          );
        }
      } else if (kind == 'u' &&
          row[8] == false &&
          row[9] == true &&
          row[12] == false) {
        unique.add(keys);
      } else if (kind == 'f' &&
          row[6] == 'a' &&
          row[7] == 's' &&
          row[8] == false &&
          row[9] == true &&
          (namespace != null || row[11] == schemaName)) {
        foreign.add(
          ForeignKey(
            keys,
            row[3] as String,
            (row[4] as List<Object?>).cast<String>(),
            targetNamespace: namespace == null && row[11] == schemaName
                ? null
                : row[11] as String,
            onDelete: switch (row[5]) {
              'a' => 'NO ACTION',
              'r' => 'RESTRICT',
              'c' => 'CASCADE',
              'n' => 'SET NULL',
              'd' => 'SET DEFAULT',
              _ => throw StateError('Unknown FK action'),
            },
          ),
        );
      } else if (kind == 'c' &&
          row[9] == true &&
          row[14] == false &&
          row[15] == true &&
          row[16] == 0 &&
          row[17] == true) {
        checks.add(CheckInfo(row[0] as String, row[13] as String));
      } else if (kind != 'n') {
        unmanaged.add(
          CatalogObject('constraint', row[0] as String, row[10] as String),
        );
      }
    }
    final list = await db.execute(
      SqlCommand(
        r'''
SELECT ic.relname, i.indisunique, i.indisvalid AND i.indisready AND i.indislive,
 ARRAY(SELECT a.attname::text FROM unnest(i.indkey) WITH ORDINALITY k(num, ord)
       LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.num ORDER BY k.ord),
 pg_get_indexdef(i.indexrelid), i.indexprs IS NULL AND i.indpred IS NULL
 AND i.indnatts = i.indnkeyatts AND am.amname = 'btree'
 AND ic.reloptions IS NULL
 AND NOT coalesce((to_jsonb(i)->>'indnullsnotdistinct')::boolean, false)
 AND NOT EXISTS(SELECT 1 FROM unnest(i.indoption) v WHERE v <> 0)
 AND NOT EXISTS(SELECT 1 FROM unnest(i.indclass) v JOIN pg_opclass o ON o.oid = v WHERE NOT o.opcdefault)
 AND NOT EXISTS(SELECT 1 FROM unnest(i.indkey, i.indcollation) k(num, collation_oid)
   JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.num WHERE k.collation_oid <> a.attcollation)
FROM pg_index i JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_namespace n ON n.oid = t.relnamespace JOIN pg_class ic ON ic.oid = i.indexrelid
JOIN pg_am am ON am.oid = ic.relam
WHERE n.nspname = coalesce($2::text, current_schema()) AND t.relname = $1
AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid AND c.contype IN ('p', 'u', 'x'))''',
        [table, namespace],
      ),
    );
    for (final row in list.rows) {
      final keys = row[3] as List<Object?>;
      if (row[2] != true || row[5] != true || keys.contains(null)) {
        unmanaged.add(
          CatalogObject('index', row[0] as String, row[4] as String),
        );
      } else {
        indexes.add(
          IndexSchema(
            row[0] as String,
            keys.cast<String>(),
            unique: row[1] as bool,
          ),
        );
      }
    }
    final extras = await db.execute(
      SqlCommand(
        r'''
SELECT 'trigger', t.tgname, pg_get_triggerdef(t.oid)
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname = $1 AND n.nspname = coalesce($2::text, current_schema()) AND NOT t.tgisinternal
UNION ALL SELECT 'policy', policyname,
 jsonb_build_object('permissive', permissive, 'roles', roles, 'command', cmd,
   'using', qual, 'withCheck', with_check)::text
FROM pg_policies WHERE schemaname = coalesce($2::text, current_schema()) AND tablename = $1
UNION ALL SELECT 'row_security', c.relname,
 jsonb_build_object('enabled', c.relrowsecurity, 'forced', c.relforcerowsecurity)::text
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname = $1 AND n.nspname = coalesce($2::text, current_schema())
AND (c.relrowsecurity OR c.relforcerowsecurity
 OR EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid))''',
        [table, namespace],
      ),
    );
    for (final row in extras.rows) {
      unmanaged.add(
        CatalogObject(row[0] as String, row[1] as String, row[2] as String),
      );
    }
  }
  return TableInfo(
    name: table,
    namespace: namespace,
    columns: columns,
    primaryKey: primary,
    uniqueKeys: unique,
    foreignKeys: foreign,
    indexes: indexes,
    unmanaged: unmanaged,
    checks: List.unmodifiable(checks),
  );
}

/// Compares modeled tables, columns, keys, indexes, and checks with the catalog.
///
/// This does not infer or apply a migration. Inspect the returned unmanaged
/// objects as well as the modeled differences before changing an existing table.
Future<SchemaVerification> verifySchema(
  SqlDatabase<Backend> db,
  SchemaSnapshot expected,
) async {
  if (isMysqlFamily(db.dialect)) return mysqlVerifySchema(db, expected);
  final differences = <String>[], unmanaged = <CatalogObject>[];
  for (final table in expected.tables) {
    final actual = await inspectTable(
      db,
      table.name,
      namespace: table.namespace,
    );
    unmanaged.addAll(actual.unmanaged);
    final columns = {for (final c in actual.columns) c.name: c};
    var checkContextMatches = true;
    for (final column in table.columns) {
      final found = columns.remove(column.name),
          path = '${table.identity}.${column.name}';
      if (found == null) {
        checkContextMatches = false;
        differences.add('$path is missing');
        continue;
      }
      if (found.storageType != columnStorageType(column, db.dialect)) {
        checkContextMatches = false;
        differences.add('$path type differs');
      }
      if (found.nullable != column.nullable) {
        differences.add('$path nullability differs');
      }
      if ((found.temporalPrecision ?? 6) != (column.temporalPrecision ?? 6)) {
        differences.add('$path temporal precision differs');
      }
      if (!matchesDecimalDigits(column, found)) {
        differences.add('$path decimal precision/scale differs');
      }
      if (db.dialect == SqlDialect.sqlite && !matchesCollation(column, found)) {
        differences.add('$path collation differs');
      }
      if (column.codec.sqlType == 'integer' &&
          (found.integerBits ?? 64) != (column.integerBits ?? 64)) {
        differences.add('$path integer width differs');
      }
      if (_columnDefault(found.defaultSql, column) !=
          _columnDefault(
            column.defaultSql == null
                ? null
                : coerceColumn(column.defaultSql!, column, db.dialect),
            column,
          )) {
        differences.add('$path default differs');
      }
      if (db.dialect == SqlDialect.postgres &&
          column.computed == null &&
          found.computed == null &&
          found.generated != column.generated) {
        differences.add('$path generation differs');
      }
      if (db.dialect == SqlDialect.sqlite &&
          found.generated &&
          found.computed == null) {
        differences.add('$path uses an unmodeled generated expression');
      }
    }
    for (final name in columns.keys) {
      differences.add('${table.identity}.$name is unmanaged');
    }
    differences.addAll(
      await verifyComputed(
        db,
        table,
        actual.columns,
        contextMatches: checkContextMatches,
      ),
    );
    void compare(String kind, Object? desired, Object? found) {
      if (migrationHash(desired) != migrationHash(found)) {
        differences.add('${table.identity} $kind differs');
      }
    }

    List<String> set(Iterable<Object?> values) =>
        values.map((v) => jsonEncode(canonicalMigrationValue(v))).toList()
          ..sort();
    compare('primary key', table.primaryKey, actual.primaryKey);
    compare('unique keys', set(table.uniqueKeys), set(actual.uniqueKeys));
    // Expected SQL may no longer resolve when a referenced column/type drifted.
    // Report that schema drift instead of attempting an invalid EXPLAIN.
    final checkMatches = checkContextMatches
        ? await matchChecks(
            db,
            table.name,
            table.checks,
            actual.checks,
            namespace: table.namespace,
          )
        : List<int?>.filled(table.checks.length, null);
    if (checkMatches.any((i) => i == null) ||
        checkMatches.length != actual.checks.length) {
      differences.add('${table.identity} checks differs');
      for (var i = 0; i < actual.checks.length; i++) {
        if (!checkMatches.contains(i)) {
          final c = actual.checks[i];
          unmanaged.add(
            CatalogObject(
              'check',
              c.name ?? '${table.identity}#$i',
              c.expression,
            ),
          );
        }
      }
    }
    compare(
      'foreign keys',
      set(table.foreignKeys.map(foreignKeyJson)),
      set(actual.foreignKeys.map(foreignKeyJson)),
    );
    compare(
      'indexes',
      set(table.indexes.map(indexJson)),
      set(actual.indexes.map(indexJson)),
    );
  }
  return SchemaVerification(
    List.unmodifiable(differences),
    List.unmodifiable(unmanaged),
  );
}

String? _columnDefault(String? value, Column<Object?> column) {
  var normalized = normalizeDefault(value);
  var temporalPrefix = '';
  if (normalized != null &&
      column.temporalPrecision != null &&
      column.temporalPrecision != 6) {
    final inner = uncoerceTemporal(
      normalized,
      column.codec.sqlType,
      column.temporalPrecision!,
    );
    if (inner != null) {
      normalized = normalizeDefault(inner);
      temporalPrefix = 'temporal cast:';
    }
    final type = columnStorageType(
      column,
      SqlDialect.postgres,
    ).toLowerCase().replaceFirst('timestamptz', 'timestamp');
    final native = column.codec.sqlType == 'instant'
        ? '$type with time zone'
        : type;
    if (normalized != null && normalized.endsWith('::$native')) {
      normalized = normalizeDefault(
        normalized.substring(0, normalized.length - native.length - 2),
      );
    }
  }
  if (normalized != null &&
      normalized.startsWith("'") &&
      normalized.endsWith("'")) {
    final literal = normalized.substring(1, normalized.length - 1);
    final parsed = switch (column.codec.sqlType) {
      'instant' => _instantDefault(literal, column.temporalPrecision ?? 6),
      'date' => LocalDate.tryParse(literal),
      'time' => LocalTime.tryParse(literal),
      'local_datetime' => LocalDateTime.tryParse(literal),
      _ => null,
    };
    if (parsed != null) {
      final digits = column.temporalPrecision ?? 6;
      final rounded = switch (parsed) {
        LocalTime() => parsed.withPrecision(digits),
        LocalDateTime() => parsed.withPrecision(digits),
        DateTime() => parsed.withPrecision(digits),
        _ => parsed,
      };
      return '$temporalPrefix$rounded';
    }
  }
  if (normalized == null || column.codec.sqlType != 'decimal') {
    return normalized == null ? null : '$temporalPrefix$normalized';
  }
  final unwrapped = column.decimalPrecision == null
      ? null
      : uncoerceDecimalDefault(
          normalized,
          column.decimalPrecision!,
          column.decimalScale ?? 0,
        );
  final prefix = unwrapped == null ? '' : 'decimal cast:';
  normalized = unwrapped == null ? normalized : normalizeDefault(unwrapped)!;
  // PostgreSQL removes the quotes from a NUMERIC literal. Compare finite
  // literals by value, leaving arbitrary SQL expressions unchanged.
  final literal = normalized.startsWith("'") && normalized.endsWith("'")
      ? normalized.substring(1, normalized.length - 1)
      : normalized;
  return '$prefix${Decimal.tryParse(literal)?.toString() ?? normalized}';
}

String? normalizeDefault(String? value) {
  if (value == null) return null;
  var normalized = value.trim();
  while (normalized.startsWith('(') && normalized.endsWith(')')) {
    var depth = 0;
    var whole = true;
    var quoted = false;
    for (var i = 0; i < normalized.length; i++) {
      if (normalized[i] == "'") {
        if (quoted && i + 1 < normalized.length && normalized[i + 1] == "'") {
          i++;
          continue;
        }
        quoted = !quoted;
      }
      if (quoted) continue;
      if (normalized[i] == '(') depth++;
      if (normalized[i] == ')' && --depth == 0 && i != normalized.length - 1) {
        whole = false;
        break;
      }
    }
    if (!whole) break;
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  // Strip casts only from literals. Expression casts can discard time or
  // precision and must remain visible to drift verification.
  return normalized.replaceFirstMapped(
    RegExp(
      r"^('(?:[^']|'')*'|[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?|true|false)::(?:text|bigint|integer|boolean|double precision|numeric|timestamp with time zone|date|time without time zone|timestamp without time zone)$",
      caseSensitive: false,
    ),
    (match) => match[1]!,
  );
}

String? _instantDefault(String literal, int digits) {
  try {
    return Codecs.dateTime.encode(
      Codecs.dateTime.decode(literal).withPrecision(digits),
    ) as String;
  } on FormatException {
    return null;
  }
}
