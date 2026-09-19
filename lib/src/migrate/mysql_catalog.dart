part of '../../migrate.dart';

// information_schema reports some textual metadata with a BLOB wire type.
// Decode only these known catalog-query result cells, never application BLOBs.
List<List<Object?>> _mysqlCatalogRows(SqlResult result) => [
  for (final row in result.rows)
    [for (final value in row) value is List<int> ? utf8.decode(value) : value],
];

String _mysqlExpression(String? expression) {
  if (expression == null) return '';
  final normalized = _normalizeDefault(expression)!;
  if (normalized.toUpperCase() == 'NULL') return '';
  final tokens = _sqliteTokens(normalized);
  final normalizedTokens = <String>[
    for (var i = 0; i < tokens.length; i++)
      if (!(tokens[i].text == '_UTF8MB4' &&
          i + 1 < tokens.length &&
          tokens[i + 1].text.startsWith('s:')))
        tokens[i].text.startsWith('i:')
            ? tokens[i].text.substring(2).toUpperCase()
            : tokens[i].text == 'NOW' &&
                  i + 1 < tokens.length &&
                  tokens[i + 1].text == '('
            ? 'CURRENT_TIMESTAMP'
            : tokens[i].text,
  ];
  return jsonEncode(_mysqlExpressionTree(normalizedTokens) ?? normalizedTokens);
}

// MySQL inserts parentheses around binary CHECK/generated expressions. Parse
// only this small operator grammar so redundant parentheses compare equally
// while a * (b + c) remains different from a * b + c. Unknown SQL is compared
// strictly as tokens; never discard precedence-bearing punctuation.
Object? _mysqlExpressionTree(List<String> input) {
  const precedence = {
    'OR': 10,
    'AND': 20,
    '=': 30,
    '<>': 30,
    '!=': 30,
    '<': 30,
    '>': 30,
    '<=': 30,
    '>=': 30,
    '+': 40,
    '-': 40,
    '*': 50,
    '/': 50,
    '%': 50,
  };
  final tokens = <String>[];
  for (var i = 0; i < input.length; i++) {
    final combined = i + 1 < input.length ? '${input[i]}${input[i + 1]}' : '';
    if (const {'<=', '>=', '<>', '!='}.contains(combined)) {
      tokens.add(combined);
      i++;
    } else {
      tokens.add(input[i]);
    }
  }
  var offset = 0, depth = 0;
  late Object Function(int) expression;
  Object atom() {
    if (offset == tokens.length || ++depth > 128) throw const FormatException();
    try {
      final token = tokens[offset++];
      if (token == '(') {
        final result = expression(0);
        if (offset == tokens.length || tokens[offset++] != ')') {
          throw const FormatException();
        }
        return result;
      }
      if (token == '+' || token == '-' || token == 'NOT') {
        return ['unary', token, expression(token == 'NOT' ? 25 : 60)];
      }
      if (precedence.containsKey(token) ||
          const {')', ',', '.'}.contains(token)) {
        throw const FormatException();
      }
      if (offset < tokens.length && tokens[offset] == '(') {
        offset++;
        final arguments = <Object>[];
        if (offset == tokens.length) throw const FormatException();
        while (tokens[offset] != ')') {
          arguments.add(expression(0));
          if (offset == tokens.length) throw const FormatException();
          if (tokens[offset] != ',') break;
          offset++;
          if (offset == tokens.length || tokens[offset] == ')') {
            throw const FormatException();
          }
        }
        if (offset == tokens.length || tokens[offset++] != ')') {
          throw const FormatException();
        }
        return ['call', token, arguments];
      }
      return ['atom', token];
    } finally {
      depth--;
    }
  }

  expression = (minimum) {
    var left = atom();
    while (offset < tokens.length) {
      final priority = precedence[tokens[offset]];
      if (priority == null || priority < minimum) break;
      final operator = tokens[offset++];
      left = ['binary', operator, left, expression(priority + 1)];
    }
    return left;
  };
  try {
    final result = expression(0);
    return offset == tokens.length ? result : null;
  } on FormatException catch (_) {
    return null;
  }
}

String _mysqlDefaultExpression(String? expression, Column<Object?> column) {
  if (expression == null) return '';
  final sql = _normalizeDefault(expression)!;
  if (sql.toUpperCase() == 'NULL') return '';
  final clock = RegExp(
    r'^(?:CURRENT_TIMESTAMP|NOW)(?:\(([0-6]?)\))?$',
    caseSensitive: false,
  ).firstMatch(sql);
  if (clock != null) {
    return 'current_timestamp:${clock[1]?.isNotEmpty == true ? clock[1] : '0'}';
  }
  final tokens = _sqliteTokens(sql);
  if (tokens.length == 1 &&
      {'TRUE', 'FALSE'}.contains(tokens.single.text) &&
      {
        'integer',
        'bigint',
        'decimal',
        'real',
        'boolean',
      }.contains(column.codec.sqlType)) {
    return tokens.single.text == 'TRUE' ? 'number:1' : 'number:0';
  }
  if ({
    'integer',
    'bigint',
    'decimal',
    'real',
    'boolean',
  }.contains(column.codec.sqlType)) {
    final text = tokens.length == 1 && tokens.single.text.startsWith('s:')
        ? tokens.single.text.substring(2)
        : sql;
    if (RegExp(r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$')
        .hasMatch(text)) {
      return 'number:${Decimal.parse(text)}';
    }
  }
  if (tokens.length == 1 && tokens.single.text.startsWith('s:')) {
    final text = tokens.single.text.substring(2);
    try {
      final temporal = switch (column.codec.sqlType) {
        'date' => Codecs.date.decode(text).toString(),
        'time' => Codecs.time.decode(text).toString(),
        'local_datetime' => Codecs.localDateTime.decode(text).toString(),
        'instant' => Codecs.dateTime.encode(Codecs.dateTime.decode(text)),
        _ => null,
      };
      if (temporal != null) return 'temporal:$temporal';
    } on FormatException catch (_) {
      // An unrecognized literal stays structurally distinct rather than being
      // guessed equivalent to a server value.
    }
  }
  return _mysqlExpression(sql);
}

String _mysqlCatalogDefault(String expression, SqlDialect dialect) {
  if (dialect == SqlDialect.mysql) {
    // MySQL COLUMN_DEFAULT adds a transport escape layer to generated
    // expressions, even though the driver has already decoded its wire value.
    return expression.replaceAllMapped(RegExp(r"\\(['\\])"), (m) => m[1]!);
  }
  // MariaDB serializes string literals using backslash escapes independently
  // of NO_BACKSLASH_ESCAPES. Return valid SQL for our fixed session mode.
  final result = StringBuffer();
  var offset = 0;
  for (final token in _sqliteTokens(expression)) {
    if (!token.text.startsWith('s:')) continue;
    final value = token.text
        .substring(2)
        .replaceAllMapped(
          RegExp(r'\\([0bnrtZ\\])'),
          (m) => switch (m[1]) {
            '0' => '\u0000',
            'b' => '\b',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'Z' => '\u001a',
            _ => '\\',
          },
        );
    result.write(expression.substring(offset, token.start));
    result.write("'${value.replaceAll("'", "''")}'");
    offset = token.end;
  }
  result.write(expression.substring(offset));
  return result.toString();
}

Future<List<CheckInfo>> _mysqlChecks(
  SqlDatabase<Backend> db,
  String table,
) async {
  final rows = await db.execute(
    SqlCommand(
      db.dialect == SqlDialect.mysql
          ? '''SELECT cc.CONSTRAINT_NAME, cc.CHECK_CLAUSE, tc.ENFORCED
FROM information_schema.CHECK_CONSTRAINTS cc
JOIN information_schema.TABLE_CONSTRAINTS tc ON tc.CONSTRAINT_SCHEMA=cc.CONSTRAINT_SCHEMA AND tc.CONSTRAINT_NAME=cc.CONSTRAINT_NAME
WHERE tc.TABLE_SCHEMA=DATABASE() AND tc.TABLE_NAME=? AND tc.CONSTRAINT_TYPE='CHECK' '''
          : '''SELECT CONSTRAINT_NAME, CHECK_CLAUSE, 'YES'
FROM information_schema.CHECK_CONSTRAINTS WHERE CONSTRAINT_SCHEMA=DATABASE() AND TABLE_NAME=?''',
      [table],
    ),
  );
  return [
    for (final row in _mysqlCatalogRows(rows))
      CheckInfo(
        row[0] as String,
        '${row[1]}${row[2] == 'YES' ? '' : ' /* NOT ENFORCED */'}',
      ),
  ];
}

Future<List<ColumnInfo>> _mysqlColumns(
  SqlDatabase<Backend> db,
  String table,
) async {
  final rows = await db.execute(
    SqlCommand(
      '''SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT,
EXTRA, GENERATION_EXPRESSION, NUMERIC_PRECISION, NUMERIC_SCALE, DATETIME_PRECISION, COLLATION_NAME, CHARACTER_MAXIMUM_LENGTH
FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? ORDER BY ORDINAL_POSITION''',
      [table],
    ),
  );
  final checks = db.dialect == SqlDialect.mariadb
      ? await _mysqlChecks(db, table)
      : const <CheckInfo>[];
  return [
    for (final row in _mysqlCatalogRows(rows))
      _mysqlColumnInfo(row, db.dialect, checks),
  ];
}

ColumnInfo _mysqlColumnInfo(
  List<Object?> row,
  SqlDialect dialect,
  List<CheckInfo> checks,
) {
  final name = row[0] as String, kind = (row[1] as String).toLowerCase();
  final declared = (row[2] as String).toLowerCase(),
      extra = (row[5] as String).toUpperCase();
  final precision = row[7] as int?,
      scale = row[8] as int?,
      digits = row[9] as int?;
  final jsonAlias =
      kind == 'longtext' &&
      dialect == SqlDialect.mariadb &&
      row[10] == 'utf8mb4_bin' &&
      checks.any(
        (c) =>
            c.name == name &&
            _mysqlExpression(c.expression) ==
                _mysqlExpression('json_valid(${_quote(name)})'),
      );
  final storage = declared.contains('unsigned') || declared.contains('zerofill')
      ? declared.toUpperCase()
      : switch (kind) {
          'smallint' => 'SMALLINT',
          'int' || 'integer' => 'INT',
          'bigint' => 'BIGINT',
          'tinyint' when declared == 'tinyint(1)' => 'TINYINT(1)',
          'varchar' => 'VARCHAR(${row[11]})',
          'decimal' => 'DECIMAL($precision,$scale)',
          'time' => 'TIME(${digits ?? 0})',
          'datetime' => 'DATETIME(${digits ?? 0})',
          'longtext' when jsonAlias => 'JSON',
          _ => declared.toUpperCase(),
        };
  String? defaultSql = row[4] as String?;
  if (defaultSql != null) {
    if (dialect == SqlDialect.mariadb || extra.contains('DEFAULT_GENERATED')) {
      defaultSql = _mysqlCatalogDefault(defaultSql, dialect);
    } else if ({
      'varchar',
      'char',
      'text',
      'longtext',
      'date',
      'datetime',
      'timestamp',
      'time',
    }.contains(kind)) {
      defaultSql = "'${defaultSql.replaceAll("'", "''")}'";
    }
  }
  if (defaultSql?.toUpperCase() == 'NULL') defaultSql = null;
  final expression = row[6] as String?;
  return ColumnInfo(
    name: name,
    storageType: storage,
    nullable: row[3] == 'YES',
    defaultSql: defaultSql,
    generated: extra.contains('AUTO_INCREMENT'),
    computed: expression == null || expression.isEmpty
        ? null
        : ComputedColumn(
            expression,
            storage: extra.contains('STORED') || extra.contains('PERSISTENT')
                ? .stored
                : .virtual,
          ),
    integerBits: switch (kind) {
      'smallint' => 16,
      'int' || 'integer' => 32,
      'bigint' => 64,
      _ => null,
    },
    decimalPrecision: kind == 'decimal' ? precision : null,
    decimalScale: kind == 'decimal' ? scale : null,
    temporalPrecision: {'time', 'datetime', 'timestamp'}.contains(kind)
        ? (digits ?? 0)
        : null,
    collation: row[10] as String?,
  );
}

Future<TableInfo> _mysqlTable(SqlDatabase<Backend> db, String table) async {
  final columns = await _mysqlColumns(db, table);
  final primary = <String>[],
      unique = <List<String>>[],
      indexes = <IndexSchema>[];
  final foreign = <ForeignKey>[], unmanaged = <CatalogObject>[];
  final properties = await db.execute(
    SqlCommand(
      '''SELECT TABLE_TYPE, ENGINE, TABLE_COLLATION, CREATE_OPTIONS
FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?''',
      [table],
    ),
  );
  if (properties.rows.isNotEmpty) {
    final row = _mysqlCatalogRows(properties).single;
    if (row[0] != 'BASE TABLE' ||
        row[1] != 'InnoDB' ||
        row[2] != 'utf8mb4_bin' ||
        (row[3] as String).isNotEmpty) {
      unmanaged.add(CatalogObject('table options', table, row.toString()));
    }
    final shown = await db.execute(
      SqlCommand('SHOW CREATE TABLE ${_quote(table)}'),
    );
    if (shown.rows.isNotEmpty &&
        RegExp(
          r'^CREATE\s+TEMPORARY\s+TABLE\b',
          caseSensitive: false,
        ).hasMatch(_mysqlCatalogRows(shown).single[1] as String)) {
      unmanaged.add(
        CatalogObject(
          'temporary table',
          table,
          _mysqlCatalogRows(shown).single[1] as String,
        ),
      );
    }
  }
  final details = await db.execute(
    SqlCommand(
      '''SELECT COLUMN_NAME, EXTRA, COLUMN_COMMENT, COLUMN_TYPE, COLLATION_NAME
FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?''',
      [table],
    ),
  );
  for (final row in _mysqlCatalogRows(details)) {
    final extra = (row[1] as String)
        .toUpperCase()
        .replaceAll('AUTO_INCREMENT', '')
        .replaceAll('DEFAULT_GENERATED', '')
        .replaceAll('STORED GENERATED', '')
        .replaceAll('VIRTUAL GENERATED', '')
        .replaceAll('PERSISTENT', '')
        .trim();
    final found = columns.singleWhere((c) => c.name == row[0]);
    if (extra.isNotEmpty ||
        row[2] != '' ||
        (row[3] as String).contains('unsigned') ||
        found.storageType.startsWith('VARCHAR') &&
            found.collation != 'utf8mb4_bin' ||
        !RegExp(
          r'^(SMALLINT|INT|BIGINT|TINYINT\(1\)|VARCHAR\([0-9]+\)|DECIMAL\([0-9]+,[0-9]+\)|DOUBLE|DATE|TIME\([0-6]\)|DATETIME\([0-6]\)|JSON|LONGBLOB)$',
        ).hasMatch(found.storageType)) {
      unmanaged.add(
        CatalogObject('column', '$table.${row[0]}', row.toString()),
      );
    }
  }
  final statistics = await db.execute(
    SqlCommand(
      '''SELECT INDEX_NAME, NON_UNIQUE, SEQ_IN_INDEX, COLUMN_NAME,
SUB_PART, COLLATION, INDEX_TYPE, ${db.dialect == SqlDialect.mysql ? "EXPRESSION, IS_VISIBLE" : "NULL, IF(IGNORED='NO','YES','NO')"}
FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=? ORDER BY INDEX_NAME, SEQ_IN_INDEX''',
      [table],
    ),
  );
  final grouped = <String, List<List<Object?>>>{};
  for (final row in _mysqlCatalogRows(statistics)) {
    (grouped[row[0] as String] ??= []).add(row);
  }
  for (final entry in grouped.entries) {
    final rows = entry.value;
    if (rows.any(
      (r) =>
          r[3] == null ||
          r[4] != null ||
          r[5] != 'A' ||
          r[6] != 'BTREE' ||
          r[7] != null ||
          r[8] != 'YES',
    )) {
      unmanaged.add(CatalogObject('index', entry.key, rows.toString()));
      continue;
    }
    final keys = rows.map((r) => r[3] as String).toList();
    if (entry.key == 'PRIMARY') {
      primary.addAll(keys);
    } else if (rows.first[1] == 0 &&
        entry.key == _mysqlUniqueName(table, keys)) {
      unique.add(keys);
    } else {
      indexes.add(IndexSchema(entry.key, keys, unique: rows.first[1] == 0));
    }
  }
  final references = await db.execute(
    SqlCommand(
      '''SELECT k.CONSTRAINT_NAME, k.COLUMN_NAME, k.REFERENCED_TABLE_NAME,
k.REFERENCED_COLUMN_NAME, r.DELETE_RULE, r.UPDATE_RULE, k.REFERENCED_TABLE_SCHEMA=DATABASE()
FROM information_schema.KEY_COLUMN_USAGE k
JOIN information_schema.REFERENTIAL_CONSTRAINTS r ON r.CONSTRAINT_SCHEMA=k.CONSTRAINT_SCHEMA AND r.CONSTRAINT_NAME=k.CONSTRAINT_NAME AND r.TABLE_NAME=k.TABLE_NAME
WHERE k.TABLE_SCHEMA=DATABASE() AND k.TABLE_NAME=? AND k.REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY k.CONSTRAINT_NAME, k.ORDINAL_POSITION''',
      [table],
    ),
  );
  final foreignRows = <String, List<List<Object?>>>{};
  for (final row in _mysqlCatalogRows(references)) {
    (foreignRows[row[0] as String] ??= []).add(row);
  }
  for (final entry in foreignRows.entries) {
    final rows = entry.value, row = entry.value.first;
    if (!{'RESTRICT', 'NO ACTION'}.contains(row[5]) || row[6] != 1) {
      unmanaged.add(CatalogObject('foreign key', entry.key, rows.toString()));
      continue;
    }
    final key = ForeignKey(
      rows.map((r) => r[1] as String).toList(),
      row[2] as String,
      rows.map((r) => r[3] as String).toList(),
      onDelete: row[4] as String,
    );
    foreign.add(key);
    if (entry.key != _mysqlForeignName(table, key)) {
      unmanaged.add(
        CatalogObject('constraint name', entry.key, rows.toString()),
      );
    }
  }
  final checks = (await _mysqlChecks(db, table))
      .where(
        (check) => !columns.any(
          (column) =>
              db.dialect == SqlDialect.mariadb &&
              column.storageType == 'JSON' &&
              check.name == column.name &&
              _mysqlExpression(check.expression) ==
                  _mysqlExpression('json_valid(${_quote(column.name)})'),
        ),
      )
      .toList();
  for (final check in checks) {
    if (check.expression.endsWith('/* NOT ENFORCED */')) {
      unmanaged.add(CatalogObject('check', check.name!, check.expression));
    }
  }
  final triggers = await db.execute(
    SqlCommand(
      '''SELECT TRIGGER_NAME, ACTION_STATEMENT
FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA=DATABASE() AND EVENT_OBJECT_TABLE=?''',
      [table],
    ),
  );
  unmanaged.addAll(
    _mysqlCatalogRows(triggers)
        .map((r) => CatalogObject('trigger', r[0] as String, r[1] as String)),
  );
  return TableInfo(
    name: table,
    columns: columns,
    primaryKey: primary,
    uniqueKeys: unique,
    foreignKeys: foreign,
    indexes: indexes,
    unmanaged: unmanaged,
    checks: checks,
  );
}

Future<SchemaVerification> _mysqlVerifySchema(
  SqlDatabase<Backend> db,
  SchemaSnapshot expected,
) async {
  final differences = <String>[], unmanaged = <CatalogObject>[];
  for (final source in expected.tables) {
    final table = _mysqlPhysicalTable(source),
        actual = await _mysqlTable(db, source.name);
    unmanaged.addAll(actual.unmanaged);
    final columns = {for (final column in actual.columns) column.name: column};
    for (final column in table.columns) {
      final found = columns.remove(column.name),
          name = '${table.name}.${column.name}';
      if (found == null) {
        differences.add('$name is missing');
        continue;
      }
      if (found.storageType != _mysqlColumnType(column)) {
        differences.add('$name type differs');
      }
      if (found.nullable != column.nullable) {
        differences.add('$name nullability differs');
      }
      if (found.generated != column.generated) {
        differences.add('$name generation differs');
      }
      if (_mysqlDefaultExpression(found.defaultSql, column) !=
          _mysqlDefaultExpression(column.defaultSql, column)) {
        differences.add('$name default differs');
      }
      if (_mysqlExpression(found.computed?.expression(db.dialect)) !=
              _mysqlExpression(column.computed?.expression(db.dialect)) ||
          found.computed?.storage != column.computed?.storage) {
        differences.add('$name computed expression differs');
      }
    }
    for (final name in columns.keys) {
      differences.add('${table.name}.$name is unmanaged');
    }
    List<String> set(Iterable<Object?> items) =>
        items.map((item) => jsonEncode(_canonical(item))).toList()..sort();
    void compare(String name, Object expected, Object found) {
      if (_hash(expected) != _hash(found)) {
        differences.add('${table.name} $name differs');
      }
    }

    Map<String, Object?> fk(ForeignKey key) => {
      ..._foreignKeyJson(key),
      'onDelete': key.onDelete == 'NO ACTION' ? 'RESTRICT' : key.onDelete,
    };
    compare('primary key', table.primaryKey, actual.primaryKey);
    compare('unique keys', set(table.uniqueKeys), set(actual.uniqueKeys));
    compare(
      'indexes',
      set(table.indexes.map(_indexJson)),
      set(actual.indexes.map(_indexJson)),
    );
    compare(
      'foreign keys',
      set(table.foreignKeys.map(fk)),
      set(actual.foreignKeys.map(fk)),
    );
    final unmatched = actual.checks.toList();
    for (final check in table.checks) {
      final match = unmatched.indexWhere(
        (c) =>
            (check.name == null || check.name == c.name) &&
            _mysqlExpression(check.expression(db.dialect)) ==
                _mysqlExpression(c.expression),
      );
      if (match < 0) {
        differences.add('${table.name} checks differs');
      } else {
        unmatched.removeAt(match);
      }
    }
    if (unmatched.isNotEmpty) differences.add('${table.name} checks differs');
  }
  return SchemaVerification(
    List.unmodifiable(differences),
    List.unmodifiable(unmanaged),
  );
}
