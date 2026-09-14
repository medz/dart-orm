part of '../../migrate.dart';

final class CatalogObject {
  final String kind;
  final String name;
  final String definition;
  const CatalogObject(this.kind, this.name, this.definition);
}

final class TableInfo {
  final String name;
  final List<ColumnInfo> columns;
  final List<String> primaryKey;
  final List<List<String>> uniqueKeys;
  final List<ForeignKey> foreignKeys;
  final List<IndexSchema> indexes;
  final List<CatalogObject> unmanaged;
  const TableInfo({
    required this.name,
    required this.columns,
    required this.primaryKey,
    required this.uniqueKeys,
    required this.foreignKeys,
    required this.indexes,
    required this.unmanaged,
  });
}

final class SchemaVerification {
  final List<String> differences;
  final List<CatalogObject> unmanaged;
  const SchemaVerification(this.differences, this.unmanaged);

  /// Equality of the declared schema facts; inspect unmanaged objects separately.
  bool get matches => differences.isEmpty;
}

Future<TableInfo> inspectTable(Database<Backend> db, String table) async {
  final columns = await inspectColumns(db, table);
  final primary = <String>[],
      unique = <List<String>>[],
      indexes = <IndexSchema>[];
  final foreign = <ForeignKey>[], unmanaged = <CatalogObject>[];
  if (db.dialect == SqlDialect.sqlite) {
    final info = await db.execute(
      SqlCommand('PRAGMA table_xinfo(${_quote(table)})'),
    );
    final primaryRows = info.rows.where((r) => (r[5] as int) > 0).toList()
      ..sort((a, b) => (a[5] as int).compareTo(b[5] as int));
    primary.addAll(primaryRows.map((r) => r[1] as String));
    final list = await db.execute(
      SqlCommand('PRAGMA index_list(${_quote(table)})'),
    );
    for (final row in list.rows) {
      final name = row[1] as String;
      final parts = await db.execute(
        SqlCommand('PRAGMA index_xinfo(${_quote(name)})'),
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
          keys.any((r) => r[2] == null || r[3] != 0 || r[4] != 'BINARY')) {
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
      SqlCommand('PRAGMA foreign_key_list(${_quote(table)})'),
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
    if (sql != null &&
        _sqlWords(sql).any(
          {
            'CHECK',
            'DEFERRABLE',
            'COLLATE',
            'STRICT',
            'WITHOUT',
            'AUTOINCREMENT',
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
 c.condeferrable, c.convalidated, pg_get_constraintdef(c.oid), tn.nspname
FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
JOIN pg_namespace n ON n.oid = r.relnamespace
LEFT JOIN pg_class t ON t.oid = c.confrelid
LEFT JOIN pg_namespace tn ON tn.oid = t.relnamespace
WHERE n.nspname = current_schema() AND r.relname = $1''',
        [table],
      ),
    );
    final schemaName = (await db.execute(SqlCommand('SELECT current_schema()')))
        .rows
        .single
        .single;
    for (final row in constraints.rows) {
      final kind = row[1] as String,
          keys = (row[2] as List<Object?>).cast<String>();
      if (kind == 'p') {
        primary.addAll(keys);
      } else if (kind == 'u' && row[8] == false && row[9] == true) {
        unique.add(keys);
      } else if (kind == 'f' &&
          row[6] == 'a' &&
          row[7] == 's' &&
          row[8] == false &&
          row[9] == true &&
          row[11] == schemaName) {
        foreign.add(
          ForeignKey(
            keys,
            row[3] as String,
            (row[4] as List<Object?>).cast<String>(),
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
      } else if (kind != 'n') {
        unmanaged.add(
          CatalogObject('constraint', row[0] as String, row[10] as String),
        );
      }
    }
    final list = await db.execute(
      SqlCommand(
        r'''
SELECT ic.relname, i.indisunique, i.indisvalid AND i.indisready,
 ARRAY(SELECT a.attname::text FROM unnest(i.indkey) WITH ORDINALITY k(num, ord)
       LEFT JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.num ORDER BY k.ord),
 pg_get_indexdef(i.indexrelid), i.indexprs IS NULL AND i.indpred IS NULL
 AND i.indnatts = i.indnkeyatts AND am.amname = 'btree'
 AND NOT EXISTS(SELECT 1 FROM unnest(i.indoption) v WHERE v <> 0)
FROM pg_index i JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_namespace n ON n.oid = t.relnamespace JOIN pg_class ic ON ic.oid = i.indexrelid
JOIN pg_am am ON am.oid = ic.relam
WHERE n.nspname = current_schema() AND t.relname = $1
AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid AND c.contype IN ('p', 'u', 'x'))''',
        [table],
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
WHERE c.relname = $1 AND n.nspname = current_schema() AND NOT t.tgisinternal
UNION ALL SELECT 'policy', policyname, coalesce(qual, '') || ' / ' || coalesce(with_check, '')
FROM pg_policies WHERE schemaname = current_schema() AND tablename = $1''',
        [table],
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
    columns: columns,
    primaryKey: primary,
    uniqueKeys: unique,
    foreignKeys: foreign,
    indexes: indexes,
    unmanaged: unmanaged,
  );
}

Future<SchemaVerification> verifySchema(
  Database<Backend> db,
  SchemaSnapshot expected,
) async {
  final differences = <String>[], unmanaged = <CatalogObject>[];
  for (final table in expected.tables) {
    final actual = await inspectTable(db, table.name);
    unmanaged.addAll(actual.unmanaged);
    final columns = {for (final c in actual.columns) c.name: c};
    for (final column in table.columns) {
      final found = columns.remove(column.name),
          path = '${table.name}.${column.name}';
      if (found == null) {
        differences.add('$path is missing');
        continue;
      }
      if (found.storageType != _storageType(column.codec.sqlType, db.dialect)) {
        differences.add('$path type differs');
      }
      if (found.nullable != column.nullable) {
        differences.add('$path nullability differs');
      }
      if (_normalizeDefault(found.defaultSql) !=
          _normalizeDefault(column.defaultSql)) {
        differences.add('$path default differs');
      }
      if (db.dialect == SqlDialect.postgres &&
          found.generated != column.generated) {
        differences.add('$path generation differs');
      }
      if (db.dialect == SqlDialect.sqlite && found.generated) {
        differences.add('$path uses an unmodeled generated expression');
      }
    }
    for (final name in columns.keys) {
      differences.add('${table.name}.$name is unmanaged');
    }
    void compare(String kind, Object? desired, Object? found) {
      if (_hash(desired) != _hash(found)) {
        differences.add('${table.name} $kind differs');
      }
    }

    List<String> set(Iterable<Object?> values) =>
        values.map((v) => jsonEncode(_canonical(v))).toList()..sort();
    compare('primary key', table.primaryKey, actual.primaryKey);
    compare('unique keys', set(table.uniqueKeys), set(actual.uniqueKeys));
    compare(
      'foreign keys',
      set(table.foreignKeys.map(_foreignKeyJson)),
      set(actual.foreignKeys.map(_foreignKeyJson)),
    );
    compare(
      'indexes',
      set(table.indexes.map(_indexJson)),
      set(actual.indexes.map(_indexJson)),
    );
  }
  return SchemaVerification(
    List.unmodifiable(differences),
    List.unmodifiable(unmanaged),
  );
}

String? _normalizeDefault(String? value) {
  if (value == null) return null;
  var normalized = value.trim();
  // Remove only the trailing casts introduced for simple typed literals.
  normalized = normalized.replaceFirst(
    RegExp(
      r'::(text|bigint|integer|boolean|double precision|numeric|timestamp with time zone)$',
      caseSensitive: false,
    ),
    '',
  );
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
  return normalized;
}
