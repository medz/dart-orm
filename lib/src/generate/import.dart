import 'dart:convert';

import 'package:analyzer/dart/ast/token.dart' show Keyword;
import 'package:dart_style/dart_style.dart';

import '../../migrate.dart';
import '../../runtime.dart';
import 'model.dart';
import 'source.dart';

/// A catalog fact that needs manual handling. Blocking issues prevent a faithful
/// declaration of the affected table or relationship; other issues retain objects
/// which must stay in reviewed, database-specific migrations.
final class SchemaImportIssue {
  /// Stable issue category for programmatic handling.
  final String code;

  /// Physical database object affected by this issue.
  final String object;

  /// Database fact that needs review or cannot be represented faithfully.
  final String detail;

  /// Whether the affected declaration or relationship must be omitted.
  final bool blocking;

  /// Describes an import limitation for one physical [object].
  const SchemaImportIssue(
    this.code,
    this.object,
    this.detail, {
    this.blocking = true,
  });

  /// Machine-readable report fields; not an executable schema definition.
  Map<String, Object?> toJson() => {
    'code': code,
    'object': object,
    'detail': detail,
    'blocking': blocking,
  };
}

/// Editable declarations, physical-to-Dart names, and a separate review report.
/// This is not a migration or permission to replace the existing schema.
final class ImportedSchema {
  /// Engine whose physical catalog was inspected.
  final SqlDialect dialect;

  /// Physical database schema or namespace containing the imported objects.
  final String schema;

  /// Editable Dart model declarations for supported catalog objects.
  final String dart;

  /// Physical table names mapped to their Dart model declaration names.
  final Map<String, String> entities;

  /// Physical table and column names mapped to Dart field names.
  final Map<String, Map<String, String>> fields;

  /// Catalog features that need review or prevented faithful import.
  final List<SchemaImportIssue> issues;
  ImportedSchema._(
    this.dialect,
    this.schema,
    this.dart,
    Map<String, String> entities,
    Map<String, Map<String, String>> fields,
    List<SchemaImportIssue> issues,
  ) : entities = Map.unmodifiable(entities),
      fields = Map.unmodifiable(
        fields.map((k, v) => MapEntry(k, Map<String, String>.unmodifiable(v))),
      ),
      issues = List.unmodifiable(issues);

  /// Whether any unsupported object prevented a faithful declaration.
  bool get hasBlockingIssues => issues.any((i) => i.blocking);

  /// Machine-readable names and review issues, excluding generated Dart source.
  Map<String, Object?> toJson() => {
    'format': 1,
    'dialect': dialect.name,
    'schema': schema,
    'entities': entities,
    'fields': fields,
    'issues': [for (final issue in issues) issue.toJson()],
  };
}

/// Reads the selected database's physical catalog in one consistent
/// catalog snapshot. No user rows are read, inferred, or changed. Omit [tables]
/// to discover user tables; pass exact physical names to restrict the import.
/// Unsupported columns exclude their whole table and produce blocking issues.
Future<ImportedSchema> importSchema(
  SqlDatabase<Backend> db, {
  List<String>? tables,
}) {
  final requested = tables == null ? null : List<String>.unmodifiable(tables);
  if (requested != null &&
      (requested.isEmpty || requested.toSet().length != requested.length)) {
    throw ArgumentError.value(tables, 'tables', 'Choose distinct table names.');
  }
  if (db.inTransaction) {
    throw const OrmException(
      'IMPORT.SESSION',
      'Import needs its own catalog snapshot.',
    );
  }
  return db.transaction(
    (tx) => _importCatalog(tx, requested),
    options: switch (db.dialect) {
      SqlDialect.sqlite => const SqliteTransaction(),
      SqlDialect.postgres => const PostgresTransaction(
        isolation: .repeatableRead,
        readOnly: true,
      ),
      SqlDialect.mysql => const MysqlTransaction(
        isolation: .repeatableRead,
        readOnly: true,
      ),
      SqlDialect.mariadb => const MariadbTransaction(
        isolation: .repeatableRead,
        readOnly: true,
      ),
    },
  );
}

Future<ImportedSchema> _importCatalog(
  SqlDatabase<Backend> db,
  List<String>? requested,
) async {
  final issues = <SchemaImportIssue>[];
  final schema = db.dialect == SqlDialect.sqlite
      ? 'main'
      : (await db.execute(
              SqlCommand(
                isMysqlDialect(db.dialect)
                    ? 'SELECT DATABASE()'
                    : 'SELECT current_schema()',
              ),
            )).rows.single.single
            as String?;
  if (schema == null) {
    throw const OrmException(
      'IMPORT.SCHEMA',
      'Select an existing database or schema in the connection options.',
    );
  }
  final sqliteKinds = <String, String>{};
  if (db.dialect == SqlDialect.sqlite) {
    final list = await db.execute(SqlCommand('PRAGMA main.table_list'));
    if (!list.columns.contains('type')) {
      throw const OrmException(
        'IMPORT.CAPABILITY',
        'SQLite catalog import requires table_list (SQLite 3.37 or later).',
      );
    }
    for (final row in list.rows) {
      sqliteKinds[row[1] as String] = row[2] as String;
    }
  }
  final inventory = await db.execute(
    SqlCommand(
      db.dialect == SqlDialect.sqlite
          ? "SELECT name, type, sql FROM main.sqlite_schema WHERE type IN ('table', 'view') AND substr(name, 1, 7) <> 'sqlite_' ORDER BY name"
          : isMysqlDialect(db.dialect)
          ? "SELECT TABLE_NAME, TABLE_TYPE, '' FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() ORDER BY TABLE_NAME"
          : '''SELECT c.relname, c.relkind::text,
        CASE WHEN c.relkind IN ('v', 'm') THEN pg_get_viewdef(c.oid) ELSE '' END
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = current_schema() AND c.relkind IN ('r', 'p', 'v', 'm', 'f') ORDER BY c.relname''',
    ),
  );
  final inventoryRows = isMysqlDialect(db.dialect)
      ? [
          for (final row in inventory.rows)
            [
              for (final value in row)
                value is List<int> ? utf8.decode(value) : value,
            ],
        ]
      : inventory.rows;
  final objects = {for (final row in inventoryRows) row[0] as String: row};
  final selected =
      requested?.toList() ??
      objects.keys
          .where(
            (n) => !{'_orm_migrations', '_orm_migration_steps'}.contains(n),
          )
          .toList();
  selected.sort();
  final infos = <String, TableInfo>{};
  final generated = <String, Set<String>>{};
  final reported = <String>{};
  for (final name in selected) {
    final object = objects[name];
    if (object == null) {
      issues.add(
        SchemaImportIssue(
          'IMPORT.MISSING',
          name,
          'No table with this exact name exists in the selected schema.',
        ),
      );
      continue;
    }
    final kind = sqliteKinds[name] ?? object[1] as String;
    if (!{'r', 'table', 'BASE TABLE'}.contains(kind)) {
      issues.add(
        SchemaImportIssue(
          'IMPORT.OBJECT',
          name,
          '$kind: ${object[2] ?? ''}',
          blocking:
              requested != null ||
              !{'v', 'm', 'view', 'VIEW', 'shadow'}.contains(kind),
        ),
      );
      continue;
    }
    if (db.dialect == SqlDialect.sqlite) {
      final shadow = await db.execute(
        SqlCommand(
          "SELECT name FROM sqlite_temp_schema WHERE name = ?1 COLLATE NOCASE AND type IN ('table', 'view')",
          [name],
        ),
      );
      if (shadow.rows.isNotEmpty) {
        issues.add(
          SchemaImportIssue(
            'IMPORT.SCOPE',
            name,
            'A temporary object shadows this table.',
          ),
        );
        continue;
      }
    } else if (db.dialect == SqlDialect.postgres) {
      final shape = await db.execute(
        SqlCommand(
          r'''SELECT pg_table_is_visible(c.oid),
        c.relispartition OR EXISTS(SELECT 1 FROM pg_inherits WHERE inhrelid = c.oid OR inhparent = c.oid)
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = current_schema() AND c.relname = $1''',
          [name],
        ),
      );
      if (shape.rows.single[0] != true || shape.rows.single[1] == true) {
        issues.add(
          SchemaImportIssue(
            'IMPORT.SCOPE',
            name,
            'Shadowed, partitioned, or inherited tables need explicit declarations.',
          ),
        );
        continue;
      }
    }
    final before = issues.where((i) => i.blocking).length;
    final info = await inspectTable(db, name);
    for (final extra in info.unmanaged) {
      // SQLite inspection conservatively returns all views. Report each once;
      // views in the selected inventory already have their own object entry.
      if (extra.kind == 'view' && selected.contains(extra.name)) {
        continue;
      }
      final object = extra.kind == 'view'
          ? 'view/${extra.name}'
          : '$name/${extra.kind}/${extra.name}';
      if (!reported.add(object)) {
        continue;
      }
      issues.add(
        SchemaImportIssue(
          'IMPORT.UNMANAGED',
          object,
          extra.definition,
          blocking:
              isMysqlDialect(db.dialect) &&
              {'column', 'table options'}.contains(extra.kind),
        ),
      );
    }
    final identities = <String>{};
    if (info.columns.isEmpty) {
      issues.add(
        SchemaImportIssue(
          'IMPORT.EMPTY',
          name,
          'A model requires at least one column.',
        ),
      );
    }
    Map<String, List<Object?>> modes = {};
    if (db.dialect == SqlDialect.postgres) {
      final result = await db.execute(
        SqlCommand(
          r'''SELECT a.attname, a.attidentity::text, a.attgenerated::text
        FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = current_schema() AND c.relname = $1 AND a.attnum > 0 AND NOT a.attisdropped''',
          [name],
        ),
      );
      modes = {for (final row in result.rows) row[0] as String: row};
    }
    for (final column in info.columns) {
      final path = '$name.${column.name}';
      if (_importColumn(column, db.dialect) == null) {
        issues.add(
          SchemaImportIssue(
            'IMPORT.TYPE',
            path,
            'No exact declaration mapping for ${column.storageType}. No data values were sampled.',
          ),
        );
      }
      if (isMysqlDialect(db.dialect) &&
          column.storageType.startsWith('DATETIME')) {
        issues.add(
          SchemaImportIssue(
            'IMPORT.TEMPORAL_SEMANTICS',
            path,
            'DATETIME does not identify an application timezone. Imported as LocalDateTime; explicitly choose a UTC instant codec if that is the application contract.',
            blocking: false,
          ),
        );
      }
      if (isMysqlDialect(db.dialect) && column.storageType == 'TINYINT(1)') {
        issues.add(
          SchemaImportIssue(
            'IMPORT.BOOLEAN_SEMANTICS',
            path,
            'TINYINT(1) is MySQL boolean storage but does not enforce a 0/1 value domain. Review this bool declaration against the application contract; no rows were sampled.',
            blocking: false,
          ),
        );
      }
      if (info.primaryKey.contains(column.name) && column.nullable) {
        issues.add(
          SchemaImportIssue(
            'IMPORT.NULLABLE_KEY',
            path,
            'Nullable primary keys cannot provide a typed row identity.',
          ),
        );
      }
      if (column.generated && column.computed == null) {
        if (isMysqlDialect(db.dialect) &&
            {'SMALLINT', 'INT', 'BIGINT'}.contains(column.storageType) &&
            !column.nullable &&
            sameStrings(info.primaryKey, [column.name])) {
          identities.add(column.name);
        } else if (db.dialect == SqlDialect.postgres &&
            modes[column.name]![1] == 'd' &&
            modes[column.name]![2] == '' &&
            {'SMALLINT', 'INTEGER', 'BIGINT'}.contains(column.storageType) &&
            !column.nullable &&
            sameStrings(info.primaryKey, [column.name])) {
          identities.add(column.name);
        } else {
          issues.add(
            SchemaImportIssue(
              'IMPORT.GENERATED',
              path,
              'Generated expressions and ALWAYS/non-primary identities need explicit write semantics.',
            ),
          );
        }
      }
    }
    if (info.columns.isNotEmpty &&
        info.columns.every((c) => c.computed != null)) {
      issues.add(
        SchemaImportIssue(
          'IMPORT.COMPUTED_TABLE',
          name,
          'Portable declarations need at least one ordinary column.',
        ),
      );
    }
    if (db.dialect == SqlDialect.sqlite &&
        info.primaryKey.length == 1 &&
        info.columns.any(
          (c) =>
              c.name == info.primaryKey.single &&
              c.storageType == 'INTEGER' &&
              !c.nullable,
        )) {
      final indexes = await db.execute(
        SqlCommand('PRAGMA main.index_list(${_importQuote(name)})'),
      );
      if (!indexes.rows.any((r) => r[3] == 'pk')) {
        identities.add(info.primaryKey.single);
      }
    }
    if (issues.where((i) => i.blocking).length != before) continue;
    infos[name] = info;
    generated[name] = identities;
  }
  return _importDeclarations(infos, generated, db.dialect, schema, issues);
}

// Match physical types exactly. In particular, NUMERIC does not prove BigInt,
// and SQLite TEXT does not prove an application DateTime, enum, or JSON codec.
String? _importColumn(ColumnInfo column, SqlDialect dialect) {
  if (isMysqlDialect(dialect)) return _importMysqlColumn(column);
  return switch ((
    dialect,
    column.temporalPrecision == null
        ? column.storageType
        : column.storageType.replaceFirst(RegExp(r'\([0-6]\)'), ''),
  )) {
    (SqlDialect.sqlite, 'TEXT')
        when column.collation?.toLowerCase() == 'orm_decimal_v1' =>
      'decimal',
    (SqlDialect.postgres, 'NUMERIC') => 'decimal',
    (SqlDialect.postgres, _) when column.decimalPrecision != null => 'decimal',
    (SqlDialect.sqlite, 'INTEGER') ||
    (SqlDialect.postgres, 'SMALLINT' || 'INTEGER' || 'BIGINT') => 'integer',
    (SqlDialect.sqlite, 'TEXT')
        when column.collation?.toLowerCase() == 'orm_date_v1' =>
      'date',
    (SqlDialect.sqlite, 'TEXT')
        when column.collation?.toLowerCase() == 'orm_time_v1' =>
      'time',
    (SqlDialect.sqlite, 'TEXT')
        when column.collation?.toLowerCase() == 'orm_local_datetime_v1' =>
      'localDateTime',
    (SqlDialect.sqlite, 'TEXT')
        when column.collation?.toLowerCase() == 'orm_instant_v1' =>
      'dateTime',
    (_, 'TEXT') => 'text',
    (SqlDialect.sqlite, 'REAL') ||
    (SqlDialect.postgres, 'DOUBLE PRECISION') => 'real',
    (SqlDialect.sqlite, 'BLOB') || (SqlDialect.postgres, 'BYTEA') => 'bytes',
    (SqlDialect.postgres, 'BOOLEAN') => 'boolean',
    (SqlDialect.postgres, 'TIMESTAMPTZ') => 'dateTime',
    (SqlDialect.postgres, 'DATE') => 'date',
    (SqlDialect.postgres, 'TIME WITHOUT TIME ZONE') => 'time',
    (SqlDialect.postgres, 'TIMESTAMP WITHOUT TIME ZONE') => 'localDateTime',
    (SqlDialect.postgres, 'JSONB') => 'json',
    _ => null,
  };
}

String? _importMysqlColumn(ColumnInfo column) {
  final type = column.storageType.toUpperCase();
  // Exact declared storage only: unsigned widths, binary text and arbitrary
  // lengths must not be silently rewritten into the ORM's default types.
  if (type.contains('UNSIGNED') || type.contains('ZEROFILL')) return null;
  if (RegExp(r'^DECIMAL\([0-9]+,[0-9]+\)$').hasMatch(type) &&
      column.decimalPrecision != null) {
    return 'decimal';
  }
  final temporal = column.temporalPrecision == null
      ? type
      : type.replaceFirst(RegExp(r'\([0-6]\)'), '');
  return switch (temporal) {
    'SMALLINT' || 'INT' || 'BIGINT' => 'integer',
    'TINYINT(1)' => 'boolean',
    'VARCHAR(255)' => 'text',
    'DOUBLE' => 'real',
    'LONGBLOB' => 'bytes',
    'DATE' => 'date',
    'TIME' => 'time',
    'DATETIME' => 'localDateTime',
    'JSON' => 'json',
    _ => null,
  };
}

String _importQuote(String name) => '"${name.replaceAll('"', '""')}"';
String _importCap(String name) => name[0].toUpperCase() + name.substring(1);

final class _ImportNames {
  final used = <String>{
    ...Keyword.keywords.keys,
    ...databaseMembers,
    ...generatedTypeNames,
    'column',
    'readColumn',
    'appSchema',
    'models',
    'row',
    'left',
    'right',
    'v',
    'String',
    'int',
    'double',
    'bool',
    'DateTime',
    'BigInt',
    'Uint8List',
    'SqlJson',
    'Decimal',
    'LocalDate',
    'LocalTime',
    'LocalDateTime',
    'Model',
    'model',
    'identity',
    'integer',
    'text',
    'boolean',
    'real',
    'bigInteger',
    'decimal',
    'dateTime',
    'date',
    'time',
    'localDateTime',
    'bytes',
    'json',
    'enumeration',
    'custom',
    'index',
    'check',
    'references',
    'referencedBy',
    'Codecs',
  };
  String take(
    String physical, {
    String fallback = 'field',
    bool entity = false,
  }) {
    final words = physical
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .split(RegExp('[^a-zA-Z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    var base = words.isEmpty
        ? fallback
        : words.first.toLowerCase() +
              words.skip(1).map((w) => _importCap(w.toLowerCase())).join();
    if (!RegExp('^[a-zA-Z]').hasMatch(base)) {
      base = '$fallback${_importCap(base)}';
    }
    var value = base, n = 2;
    Set<String> symbols(String v) => {
      v,
      if (entity) ...[
        _importCap(v),
        '${v}Schema',
        '${v}Table',
        '${_importCap(v)}Fields',
        '${_importCap(v)}TableSet',
        '${_importCap(v)}Updates',
      ],
    };
    while (symbols(value).any(used.contains)) {
      value = '$base${n++}';
    }
    used.addAll(symbols(value));
    return value;
  }
}

ImportedSchema _importDeclarations(
  Map<String, TableInfo> infos,
  Map<String, Set<String>> generated,
  SqlDialect dialect,
  String schema,
  List<SchemaImportIssue> issues,
) {
  final names = _ImportNames();
  final entities = {
    for (final name in infos.keys)
      name: names.take(name, fallback: 'table', entity: true),
  };
  final fieldNames = {for (final name in infos.keys) name: _ImportNames()};
  final columnSymbols = <String>{};
  String field(String table, String column) {
    var result = fieldNames[table]!.take(column);
    while (!columnSymbols.add('_${entities[table]}${_importCap(result)}')) {
      result = fieldNames[table]!.take(result);
    }
    return result;
  }

  final fields = {
    for (final info in infos.values)
      info.name: {
        for (final c in info.columns) c.name: field(info.name, c.name),
      },
  };
  final relations = {for (final info in infos.values) info.name: <String>[]};
  String selection(String table, List<String> columns) {
    final values = columns.map((c) => 'row.${fields[table]![c]}').toList();
    return values.length == 1 ? values.single : '(${values.join(', ')})';
  }

  String mapping(
    String local,
    List<String> columns,
    String target,
    List<String> targetColumns,
  ) =>
      '(${List.generate(columns.length, (i) => '${fields[target]![targetColumns[i]]}: row.${fields[local]![columns[i]]}').join(', ')},)';
  for (final info in infos.values) {
    final entity = entities[info.name]!;
    final foreign = info.foreignKeys.toList()
      ..sort(
        (a, b) => jsonEncode([a.columns, a.target, a.targetColumns, a.onDelete])
            .compareTo(
              jsonEncode([b.columns, b.target, b.targetColumns, b.onDelete]),
            ),
      );
    for (final key in foreign) {
      final target = infos[key.target];
      if (target == null ||
          ![
            target.primaryKey,
            ...target.uniqueKeys,
            for (final i in target.indexes)
              if (i.unique) i.columns,
          ].any((k) => sameStrings(k, key.targetColumns)) ||
          key.columns.asMap().entries.any(
            (entry) =>
                _importColumn(
                  info.columns.singleWhere((c) => c.name == entry.value),
                  dialect,
                ) !=
                _importColumn(
                  target.columns.singleWhere(
                    (c) => c.name == key.targetColumns[entry.key],
                  ),
                  dialect,
                ),
          ) ||
          key.onDelete == 'SET NULL' &&
              key.columns.any(
                (c) => !info.columns.singleWhere((f) => f.name == c).nullable,
              )) {
        issues.add(
          SchemaImportIssue(
            'IMPORT.RELATION',
            '${info.name}/${key.columns.join(',')}',
            'Target ${key.target} must be imported with a matching unique key, compatible types and nullability.',
          ),
        );
        continue;
      }
      final action = switch (key.onDelete) {
        'CASCADE' => 'cascade',
        'SET NULL' => 'setNull',
        'SET DEFAULT' => 'setDefault',
        'NO ACTION' => 'noAction',
        _ => 'restrict',
      };
      var relation = names.take('$entity${_importCap(entities[key.target]!)}');
      while (fieldNames[info.name]!.used.contains(relation)) {
        relation = names.take(relation);
      }
      fieldNames[info.name]!.used.add(relation);
      final inverse = fieldNames[key.target]!.take('${entity}Rows');
      relations[info.name]!.add(
        '$relation: references(${mapping(info.name, key.columns, key.target, key.targetColumns)}, () => ${entities[key.target]}, onDelete: .$action)',
      );
      relations[key.target]!.add(
        '$inverse: referencedBy(() => $entity, on: ${mapping(key.target, key.targetColumns, info.name, key.columns)})',
      );
    }
  }
  final b = StringBuffer(
    '// Imported catalog draft. Review the import report before baselining.\n\n',
  )..writeln("import 'package:orm/schema.dart';");
  for (final info in infos.values) {
    final entity = entities[info.name]!;
    b.writeln(
      'final ${relations[info.name]!.isEmpty ? '' : 'Model '}$entity = model(${dartLiteral(info.name)}, (',
    );
    for (final c in info.columns) {
      final helper = _importColumn(c, dialect)!;
      final options = <String>['name: ${dartLiteral(c.name)}'];
      if (c.integerBits != null && c.integerBits != 64) {
        options.add('bits: ${c.integerBits}');
      }
      if (c.temporalPrecision != null && c.temporalPrecision != 6) {
        options.add('precision: ${c.temporalPrecision}');
      }
      if (c.decimalPrecision != null) {
        options.add(
          'precision: ${c.decimalPrecision}, scale: ${c.decimalScale ?? 0}',
        );
      }
      if (c.declarationDefaultSql != null) {
        options.add('defaultSql: ${dartLiteral(c.declarationDefaultSql!)}');
      }
      var column = '$helper(${options.join(', ')})';
      if (c.nullable) column += '.nullable()';
      if (generated[info.name]!.contains(c.name)) column += '.identity()';
      if (c.computed case final computed?) {
        column +=
            '.computed(${dartLiteral(c.declarationComputed!.expression(dialect))}, storage: .${computed.storage.name})';
        issues.add(
          SchemaImportIssue(
            'IMPORT.COMPUTED_SQL',
            '${info.name}.${c.name}',
            'Computed SQL was read from ${dialect.name}; review expression portability before using another backend.',
            blocking: false,
          ),
        );
      }
      b.writeln('${fields[info.name]![c.name]}: $column,');
    }
    b.writeln('),');
    if (info.primaryKey.isNotEmpty && generated[info.name]!.isEmpty) {
      b.writeln(
        'primaryKey: (row) => ${selection(info.name, info.primaryKey)},',
      );
    }
    final unique = info.uniqueKeys.toList()
      ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    if (unique.isNotEmpty) {
      b.writeln(
        'uniqueKeys: (row) => [${unique.map((k) => selection(info.name, k)).join(', ')}],',
      );
    }
    final indexes = info.indexes.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (indexes.isNotEmpty) {
      b.writeln(
        'indexes: (row) => [${indexes.map((i) => 'index(${selection(info.name, i.columns)}, name: ${dartLiteral(i.name)}, unique: ${i.unique})').join(', ')}],',
      );
    }
    final checks = info.checks.toList()
      ..sort(
        (a, b) =>
            jsonEncode([a.name, a.expression])
                .compareTo(jsonEncode([b.name, b.expression])),
      );
    if (checks.isNotEmpty) {
      b.writeln(
        'checks: [${checks.map((c) => 'check(${dartLiteral(c.expression)}, name: ${c.name == null ? 'null' : dartLiteral(c.name!)})').join(', ')}],',
      );
      issues.add(
        SchemaImportIssue(
          'IMPORT.CHECK_SQL',
          info.name,
          'CHECK expressions use ${dialect.name} SQL. Review other-dialect overrides before deploying this declaration elsewhere.',
          blocking: false,
        ),
      );
    }
    if (relations[info.name]!.isNotEmpty) {
      b.writeln('relations: (row) => (${relations[info.name]!.join(', ')},),');
    }
    b.writeln(');');
  }
  if (infos.isEmpty) {
    b.writeln('// No supported tables were imported. See the import report.');
  }
  return ImportedSchema._(
    dialect,
    schema,
    DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
        .format(b.toString()),
    entities,
    fields,
    issues,
  );
}
