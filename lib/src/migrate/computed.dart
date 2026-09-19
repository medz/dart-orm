part of '../../migrate.dart';

Map<String, Object?> _computedJson(ComputedColumn value) => {
  'sqlite': value.sqlite,
  'postgres': value.postgres,
  if (value.mysql != null && value.mysql != value.postgres)
    'mysql': value.mysql,
  if (value.mariadb != null && value.mariadb != value.postgres)
    'mariadb': value.mariadb,
  'storage': value.storage.name,
};

typedef _SqliteComputed = ({
  String column,
  ComputedColumn value,
  int start,
  int end,
});

List<_SqliteComputed> _sqliteComputed(String sql) {
  final tokens = _sqliteTokens(sql), result = <_SqliteComputed>[];
  var depth = 0, beginning = false;
  String? column;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.text == '(') {
      depth++;
      if (depth == 1) beginning = true;
    } else if (token.text == ')') {
      depth--;
    } else if (depth == 1 && token.text == ',') {
      beginning = true;
      column = null;
    } else if (depth == 1 && beginning) {
      column =
          {
            'CONSTRAINT',
            'PRIMARY',
            'UNIQUE',
            'CHECK',
            'FOREIGN',
          }.contains(token.text)
          ? null
          : token.text.startsWith('i:') || token.text.startsWith('s:')
          ? token.text.substring(2)
          : sql.substring(token.start, token.end);
      beginning = false;
    } else if (depth == 1 &&
        column != null &&
        token.text == 'AS' &&
        i + 1 < tokens.length &&
        tokens[i + 1].text == '(') {
      var nested = 1, end = i + 2;
      for (; end < tokens.length; end++) {
        if (tokens[end].text == '(') nested++;
        if (tokens[end].text == ')' && --nested == 0) break;
      }
      if (nested != 0) break;
      final expression = sql
          .substring(tokens[i + 1].end, tokens[end].start)
          .trim();
      var start = i;
      if (i >= 2 &&
          tokens[i - 2].text == 'GENERATED' &&
          tokens[i - 1].text == 'ALWAYS') {
        start -= 2;
      }
      var storage = ComputedStorage.virtual;
      if (end + 1 < tokens.length &&
          {'STORED', 'VIRTUAL'}.contains(tokens[end + 1].text)) {
        storage = tokens[++end].text == 'STORED'
            ? ComputedStorage.stored
            : ComputedStorage.virtual;
      }
      result.add((
        column: column,
        value: ComputedColumn(expression, storage: storage),
        start: tokens[start].start,
        end: tokens[end].end,
      ));
      i = end;
    }
  }
  return result;
}

Map<String, ComputedColumn> _sqliteComputedColumns(String sql) => {
  for (final c in _sqliteComputed(sql)) _sqliteName(c.column): c.value,
};

String _withoutComputed(String sql) {
  final result = StringBuffer();
  var start = 0;
  for (final c in _sqliteComputed(sql)) {
    result.write(sql.substring(start, c.start));
    start = c.end;
  }
  return (result..write(sql.substring(start))).toString();
}

ComputedColumn? _declarationComputed(ColumnInfo column) {
  final value = column.computed;
  if (value != null &&
      column.storageType == 'TEXT' &&
      column.temporalPrecision != null) {
    final expression = _uncoerceTemporal(
      value.sqlite,
      _temporalCollationKind(column.collation)!,
      column.temporalPrecision!,
    );
    return expression == null
        ? value
        : ComputedColumn(expression, storage: value.storage);
  }
  if (value == null ||
      column.storageType != 'TEXT' ||
      column.decimalPrecision == null) {
    return value;
  }
  final expression = _uncoerceDecimalDefault(
    value.sqlite,
    column.decimalPrecision!,
    column.decimalScale ?? 0,
  );
  return expression == null
      ? value
      : ComputedColumn(expression, storage: value.storage);
}

Future<List<String>> _verifyComputed(
  SqlDatabase<Backend> db,
  TableSchema table,
  List<ColumnInfo> actual, {
  bool contextMatches = true,
}) async {
  final differences = <String>[], expressions = <String>[], paths = <String>[];
  for (final column in table.columns) {
    final found = actual.where((c) => c.name == column.name).firstOrNull;
    final expected = column.computed, observed = found?.computed;
    if (expected == null && observed == null) continue;
    final path = '${table.name}.${column.name}';
    if (!contextMatches ||
        expected == null ||
        observed == null ||
        expected.storage != observed.storage) {
      differences.add('$path computed expression or storage differs');
      continue;
    }
    paths.add(path);
    final pair = [
      _coerceColumn(expected.expression(db.dialect), column, db.dialect),
      observed.expression(db.dialect),
    ];
    // PostgreSQL stores assignment casts in pg_attrdef. Compare both sides in
    // their actual column type, including numeric precision and scale.
    expressions.addAll(
      db.dialect == SqlDialect.postgres
          ? pair.map(
              (sql) =>
                  'CAST(($sql\n) AS ${_columnStorageType(column, db.dialect)})',
            )
          : pair,
    );
  }
  final signatures = await _checkExpressions(db, table.name, expressions);
  for (var i = 0; i < paths.length; i++) {
    if (signatures[i * 2] != signatures[i * 2 + 1]) {
      differences.add('${paths[i]} computed expression or storage differs');
    }
  }
  return differences;
}

TableSchema _materializedColumns(TableSchema table) => TableSchema(
  table.name,
  columns: [
    for (final c in table.columns)
      Column<Object?>(
        c.name,
        c.codec,
        nullable: c.nullable,
        generated: c.generated,
        defaultSql: c.defaultSql,
        integerBits: c.integerBits,
        decimalPrecision: c.decimalPrecision,
        decimalScale: c.decimalScale,
        temporalPrecision: c.temporalPrecision,
      ),
  ],
  primaryKey: table.primaryKey,
  uniqueKeys: table.uniqueKeys,
  indexes: table.indexes,
  checks: table.checks,
  foreignKeys: table.foreignKeys,
);
