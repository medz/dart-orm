import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/schema.dart';

import 'definition.dart';
import 'planner.dart';

Future<void> verifyCatalog(
  Session session,
  SchemaSnapshot snapshot,
  Set<String> removedTables,
) async {
  if (session.engine == Engine.sqlite) {
    for (final table in snapshot.tables) {
      await _verifySqlite(session, table);
    }
  } else {
    await _verifyPostgresql(session, snapshot.tables);
  }
  for (final table in removedTables) {
    final result = session.engine == Engine.sqlite
        ? await session.run(
            "SELECT name FROM main.sqlite_schema WHERE type = 'table' AND name = ? COLLATE NOCASE",
            parameters: [table],
          )
        : await session.run(
            'SELECT c.relname FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = \$1 AND c.relname = \$2 AND c.relkind IN (\'r\', \'p\')',
            parameters: [session.schema, table],
          );
    if (result.rows.isNotEmpty) _mismatch(table, 'removed table still exists');
  }
}

Future<void> _verifySqlite(Session session, TableDefinition table) async {
  final source = await session.run(
    '''
SELECT m.sql FROM main.sqlite_schema m
WHERE m.type = 'table' AND m.name = ? COLLATE NOCASE
  AND NOT EXISTS (
    SELECT 1 FROM temp.sqlite_schema t
    WHERE t.type IN ('table', 'view') AND t.name = m.name COLLATE NOCASE
  )
''',
    parameters: [table.name],
  );
  if (source.rows.length != 1 || source.rows.single.single is! String) {
    _mismatch(table.name, 'missing main table or temporary table/view shadow');
  }
  final createSql = source.rows.single.single as String;
  final result = await session.run(
    'PRAGMA main.table_xinfo(${quoteIdentifier(table.name)})',
  );
  final columns = _records(result);
  if (columns.length != table.columns.length) {
    _mismatch(table.name, 'column count or missing table');
  }
  final unique = <String>{};
  final indexes = _records(
    await session.run('PRAGMA main.index_list(${quoteIdentifier(table.name)})'),
  );
  // Rowid aliases have no separate primary-key index; column-level DESC does.
  final separatePrimaryKey = indexes.any((index) => index['origin'] == 'pk');
  for (final index in indexes) {
    if (index['unique'] != 1) continue;
    final indexed = _records(
      await session.run(
        'PRAGMA main.index_info(${quoteIdentifier(index['name'] as String)})',
      ),
    );
    if (index['partial'] != 0 ||
        indexed.length != 1 ||
        indexed.single['name'] is! String) {
      _mismatch(table.name, 'unique index is absent from the frozen schema');
    }
    unique.add(
      physicalIdentity(Engine.sqlite, indexed.single['name'] as String),
    );
  }
  final foreignKeys = _records(
    await session.run(
      'PRAGMA main.foreign_key_list(${quoteIdentifier(table.name)})',
    ),
  );
  for (final column in table.columns) {
    final actual = columns
        .where((c) => _sameSqliteName(c['name'], column.name))
        .firstOrNull;
    if (actual == null) _mismatch(table.name, 'missing column ${column.name}');
    final pk = actual['pk'] != 0;
    if ((actual['type'] as String).toUpperCase() !=
            storageType(Engine.sqlite, column.type) ||
        (actual['notnull'] != 0 ||
                (pk &&
                    column.type == ScalarType.integer &&
                    !separatePrimaryKey)) !=
            !column.nullable ||
        pk != column.primaryKey ||
        actual['hidden'] != 0 ||
        (unique.contains(physicalIdentity(Engine.sqlite, column.name)) &&
                !pk) !=
            (column.unique && !column.primaryKey) ||
        !_defaultMatches(
          Engine.sqlite,
          column,
          actual['dflt_value'] as String?,
        )) {
      _mismatch(table.name, 'definition of ${column.name}');
    }
    if (column.primaryKey &&
        _hasSqlKeyword(createSql, 'AUTOINCREMENT') != column.identity) {
      _mismatch(table.name, 'identity of ${column.name}');
    }
    final actualReferences = foreignKeys
        .where((key) => _sameSqliteName(key['from'], column.name))
        .toList();
    final reference = column.references;
    if (reference == null) {
      if (actualReferences.isNotEmpty) {
        _mismatch(table.name, 'unexpected foreign key ${column.name}');
      }
    } else if (actualReferences.length != 1 ||
        !_sameSqliteName(actualReferences.single['table'], reference.table) ||
        !_sameSqliteName(actualReferences.single['to'], reference.column) ||
        (actualReferences.single['on_delete'] as String).toLowerCase() !=
            reference.onDelete.toLowerCase() ||
        foreignKeys
                .where((key) => key['id'] == actualReferences.single['id'])
                .length !=
            1) {
      _mismatch(table.name, 'foreign key ${column.name}');
    }
  }
  if (foreignKeys.isNotEmpty &&
      (await session.run(
        'PRAGMA main.foreign_key_check(${quoteIdentifier(table.name)})',
      )).rows.isNotEmpty) {
    _mismatch(table.name, 'existing foreign key violations');
  }
}

bool _sameSqliteName(Object? actual, String expected) =>
    actual is String &&
    physicalIdentity(Engine.sqlite, actual) ==
        physicalIdentity(Engine.sqlite, expected);

// Keywords inside defaults, quoted identifiers or comments cannot define the
// table's identity behavior. SQLite has no PRAGMA exposing AUTOINCREMENT.
bool _hasSqlKeyword(String sql, String keyword) => RegExp(
  r"""--[^\n]*(?:\n|$)|/\*[\s\S]*?\*/|'(?:''|[^'])*'|"(?:""|[^"])*"|`(?:``|[^`])*`|\[[^\]]*\]|[A-Za-z_][A-Za-z_0-9]*""",
).allMatches(sql).any((token) => token.group(0)!.toUpperCase() == keyword);

Future<void> _verifyPostgresql(
  Session session,
  List<TableDefinition> tables,
) async {
  if (tables.isEmpty) return;
  // The fixed schema uses one parameter in every catalog query.
  final batchSize = session.capabilities.maxParameters - 1;
  if (batchSize < 1) {
    throw ArgumentError('Catalog verification needs at least two parameters.');
  }
  for (var offset = 0; offset < tables.length; offset += batchSize) {
    final end = offset + batchSize < tables.length
        ? offset + batchSize
        : tables.length;
    final batch = tables.sublist(offset, end);
    final placeholders = List.generate(
      batch.length,
      (i) => '\$${i + 2}',
    ).join(', ');
    final parameters = <Object?>[
      session.schema,
      for (final table in batch) table.name,
    ];
    final columns = _tableRecords(
      await session.run('''
SELECT c.relname AS table_name, a.attname AS name, pg_catalog.format_type(a.atttypid, a.atttypmod) AS type,
       a.attnotnull AS required, a.attidentity::text AS identity,
       pg_catalog.pg_get_expr(d.adbin, d.adrelid) AS default_value
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
WHERE n.nspname = \$1 AND c.relname IN ($placeholders)
  AND c.relkind = 'r' AND NOT c.relispartition AND c.relpersistence = 'p'
  AND a.attnum > 0 AND NOT a.attisdropped
  AND NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class shadow
    WHERE shadow.relnamespace = pg_catalog.pg_my_temp_schema()
      AND shadow.relname = c.relname
  )
ORDER BY a.attnum
''', parameters: parameters),
    );
    // Ordinary FKs have two child checks and two referenced-parent actions.
    // Partition topology is outside the frozen schema; enabled flags alone do
    // not prove enforcement. PostgreSQL 18 added conenforced; JSON keeps older
    // catalogs readable.
    final constraints = _tableRecords(
      await session.run('''
SELECT c.relname AS table_name, k.contype::text AS kind, a.attname AS name, pg_catalog.cardinality(k.conkey) AS key_count,
       target.relname AS target_table, referenced.attname AS target_column,
       target_namespace.nspname AS target_schema, k.confdeltype::text AS on_delete,
       k.convalidated AS validated,
       COALESCE((pg_catalog.to_jsonb(k)->>'conenforced')::boolean, true) AS enforced,
       CASE WHEN k.contype = 'f' THEN (
         SELECT COUNT(*) = 4 AND BOOL_AND(
           t.tgenabled = 'A' OR (t.tgenabled = 'O' AND pg_catalog.current_setting('session_replication_role') <> 'replica')
         )
         FROM pg_catalog.pg_trigger t WHERE t.tgconstraint = k.oid AND t.tgisinternal
       ) ELSE true END AS triggers_active
FROM pg_catalog.pg_constraint k
JOIN pg_catalog.pg_class c ON c.oid = k.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.conkey[1]
LEFT JOIN pg_catalog.pg_class target ON target.oid = k.confrelid
LEFT JOIN pg_catalog.pg_namespace target_namespace ON target_namespace.oid = target.relnamespace
LEFT JOIN pg_catalog.pg_attribute referenced ON referenced.attrelid = target.oid AND referenced.attnum = k.confkey[1]
WHERE n.nspname = \$1 AND c.relname IN ($placeholders) AND k.contype IN ('p', 'u', 'f')
''', parameters: parameters),
    );
    final uniques = _tableRecords(
      await session.run('''
SELECT c.relname AS table_name, a.attname AS name, i.indnkeyatts AS key_count,
       i.indpred IS NOT NULL AS partial, i.indexprs IS NOT NULL AS expression,
       i.indisvalid AS valid, i.indisready AS ready, i.indimmediate AS immediate
FROM pg_catalog.pg_index i
JOIN pg_catalog.pg_class c ON c.oid = i.indrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum = i.indkey[0]
WHERE n.nspname = \$1 AND c.relname IN ($placeholders) AND i.indisunique
''', parameters: parameters),
    );
    for (final table in batch) {
      await _verifyPostgresqlTable(
        session,
        table,
        columns[table.name] ?? const [],
        constraints[table.name] ?? const [],
        uniques[table.name] ?? const [],
      );
    }
  }
}

Future<void> _verifyPostgresqlTable(
  Session session,
  TableDefinition table,
  List<Map<String, Object?>> columns,
  List<Map<String, Object?>> constraints,
  List<Map<String, Object?>> uniques,
) async {
  if (columns.length != table.columns.length) {
    _mismatch(table.name, 'column count or missing table');
  }
  if (constraints.any((constraint) => constraint['key_count'] != 1)) {
    _mismatch(
      table.name,
      'composite constraints are absent from the frozen schema',
    );
  }
  if (uniques.any(
    (index) =>
        index['valid'] != true ||
        index['ready'] != true ||
        index['immediate'] != true,
  )) {
    _mismatch(table.name, 'unique index is not valid, ready and immediate');
  }
  if (uniques.any(
    (index) =>
        index['key_count'] != 1 ||
        index['partial'] != false ||
        index['expression'] != false,
  )) {
    _mismatch(table.name, 'unique index is absent from the frozen schema');
  }
  for (final column in table.columns) {
    final actual = columns.where((c) => c['name'] == column.name).firstOrNull;
    if (actual == null) _mismatch(table.name, 'missing column ${column.name}');
    final primaryKeys = constraints
        .where((c) => c['kind'] == 'p' && c['name'] == column.name)
        .toList();
    final pk = primaryKeys.length == 1 && primaryKeys.single['key_count'] == 1;
    final expectedType = column.type == ScalarType.dateTime
        ? 'TIMESTAMP WITH TIME ZONE'
        : storageType(Engine.postgresql, column.type);
    final actualDefault = actual['default_value'] as String?;
    final defaultMatches = column.defaultValue is DateTime
        ? await _postgresDateDefaultMatches(session, column, actualDefault)
        : _defaultMatches(Engine.postgresql, column, actualDefault);
    if ((actual['type'] as String).toUpperCase() != expectedType ||
        actual['required'] != !column.nullable ||
        pk != column.primaryKey ||
        actual['identity'] != (column.identity ? 'a' : '') ||
        (uniques.any((c) => c['name'] == column.name) && !pk) !=
            (column.unique && !column.primaryKey) ||
        !defaultMatches) {
      _mismatch(table.name, 'definition of ${column.name}');
    }
    final actualReferences = constraints
        .where((c) => c['kind'] == 'f' && c['name'] == column.name)
        .toList();
    final reference = column.references;
    if (reference == null) {
      if (actualReferences.isNotEmpty) {
        _mismatch(table.name, 'unexpected foreign key ${column.name}');
      }
    } else if (actualReferences.length != 1 ||
        actualReferences.single['key_count'] != 1 ||
        actualReferences.single['validated'] != true ||
        actualReferences.single['enforced'] != true ||
        actualReferences.single['triggers_active'] != true ||
        actualReferences.single['target_table'] != reference.table ||
        actualReferences.single['target_column'] != reference.column ||
        actualReferences.single['target_schema'] != session.schema ||
        actualReferences.single['on_delete'] !=
            {
              'restrict': 'r',
              'cascade': 'c',
              'set null': 'n',
              'no action': 'a',
            }[reference.onDelete.toLowerCase()]) {
      _mismatch(table.name, 'foreign key ${column.name}');
    }
  }
}

List<Map<String, Object?>> _records(QueryResult result) => [
  for (final row in result.rows)
    {for (var i = 0; i < result.columns.length; i++) result.columns[i]: row[i]},
];

Map<String, List<Map<String, Object?>>> _tableRecords(QueryResult result) {
  final tables = <String, List<Map<String, Object?>>>{};
  for (final record in _records(result)) {
    (tables[record['table_name'] as String] ??= []).add(record);
  }
  return tables;
}

Never _mismatch(String table, String detail) => throw StateError(
  'Migration snapshot differs from database catalog: $table ($detail).',
);

bool _defaultMatches(Engine engine, ColumnDefinition column, String? actual) {
  final expected = column.defaultValue;
  if (actual == null || expected == null) {
    return actual == null && expected == null;
  }
  var expression = actual.trim();
  while (expression.startsWith('(') && expression.endsWith(')')) {
    expression = expression.substring(1, expression.length - 1).trim();
  }
  if (engine == Engine.sqlite) {
    return expression == literalSql(engine, expected);
  }
  expression = expression
      .replaceFirst(
        RegExp(
          r'::(?:text|bigint|integer|numeric|double precision|boolean|timestamp with time zone|bytea)$',
        ),
        '',
      )
      .trim();
  return switch (expected) {
    int value => int.tryParse(_quotedString(expression) ?? expression) == value,
    double value =>
      double.tryParse(_quotedString(expression) ?? expression) == value,
    bool value => expression.toLowerCase() == value.toString(),
    String value => _quotedString(expression) == value,
    Uint8List value =>
      expression.replaceAll('::text', '').replaceAll(' ', '').toLowerCase() ==
          literalSql(engine, value).replaceAll(' ', '').toLowerCase(),
    _ => false,
  };
}

Future<bool> _postgresDateDefaultMatches(
  Session session,
  ColumnDefinition column,
  String? actual,
) async {
  if (actual == null) return false;
  final literal = _quotedString(
    actual.replaceFirst(RegExp(r'::timestamp with time zone$'), '').trim(),
  );
  if (literal == null) return false;
  // Let PostgreSQL interpret its own BC, expanded-year and timezone spelling.
  // Only a quoted literal is accepted; arbitrary default functions stay rejected.
  final result = await session.run(
    'SELECT \$1::timestamptz = \$2',
    parameters: [literal, column.defaultValue],
  );
  return result.rows.single.single == true;
}

String? _quotedString(String expression) {
  if (!expression.startsWith("'") || !expression.endsWith("'")) return null;
  return expression.substring(1, expression.length - 1).replaceAll("''", "'");
}
