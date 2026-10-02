import 'dart:convert';

import 'package:analyzer/dart/ast/token.dart' show Keyword;
import 'package:dart_style/dart_style.dart';

import '../driver/driver.dart';
import '../migrate/catalog.dart';
import '../migrate/columns.dart';
import '../runtime/database.dart';
import '../runtime/options.dart';
import '../values/codec.dart';
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

  /// Physical table names mapped to their annotated Dart class names.
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
    'Id',
    'Unique',
    'Index',
    'ClientDefault',
    'DatabaseDefault',
    'Ignore',
    'Check',
    'Computed',
    'ReferentialAction',
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
      name: _importCap(names.take(name, fallback: 'table', entity: true)),
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
  String selection(String table, List<String> columns) =>
      '[${columns.map((c) => dartLiteral(fields[table]![c]!)).join(', ')}]';
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
        '@Relation(target: ${entities[key.target]}, name: ${dartLiteral(relation)}, fields: ${selection(info.name, key.columns)}, keys: ${selection(key.target, key.targetColumns)}, inverse: ${dartLiteral(inverse)}, onDelete: .$action)',
      );
    }
  }
  final b = StringBuffer(
    '// Imported catalog draft. Review the import report before baselining.\n\n',
  );
  if (infos.values.any(
    (info) => info.columns.any((c) => _importColumn(c, dialect) == 'bytes'),
  )) {
    b.writeln("import 'dart:typed_data';");
  }
  b.writeln("import 'package:orm/schema.dart';");
  if (infos.values.any(
    (info) => info.columns.any(
      (column) => const {
        'decimal',
        'date',
        'time',
        'localDateTime',
        'json',
      }.contains(_importColumn(column, dialect)),
    ),
  )) {
    b.writeln("import 'package:orm/values.dart';");
  }
  for (final info in infos.values) {
    final entity = entities[info.name]!;
    b.writeln(
      '@Model(table: ${dartLiteral(info.name)}${dialect == SqlDialect.postgres ? ', namespace: ${dartLiteral(schema)}' : ''})',
    );
    final unique = info.uniqueKeys.toList()
      ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    for (final key in unique) {
      b.writeln('@Unique(${selection(info.name, key)})');
    }
    final indexes = info.indexes.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final index in indexes) {
      b.writeln(
        '@Index(${selection(info.name, index.columns)}, name: ${dartLiteral(index.name)}, unique: ${index.unique})',
      );
    }
    final checks = info.checks.toList()
      ..sort(
        (a, b) =>
            jsonEncode([a.name, a.expression])
                .compareTo(jsonEncode([b.name, b.expression])),
      );
    for (final check in checks) {
      b.writeln(
        '@Check(${dartLiteral(check.expression)}${check.name == null ? '' : ', name: ${dartLiteral(check.name!)}'})',
      );
    }
    for (final relation in relations[info.name]!) {
      b.writeln(relation);
    }
    b.writeln('final class $entity {');
    for (final column in info.columns) {
      if (info.primaryKey.contains(column.name)) {
        b.writeln(
          generated[info.name]!.contains(column.name)
              ? '@Id(generated: true)'
              : '@Id()',
        );
      }
      final options = <String>['name: ${dartLiteral(column.name)}'];
      if (column.integerBits != null && column.integerBits != 64) {
        options.add('bits: ${column.integerBits}');
      }
      if (column.temporalPrecision != null && column.temporalPrecision != 6) {
        options.add('precision: ${column.temporalPrecision}');
      }
      if (column.decimalPrecision != null) {
        options.add(
          'precision: ${column.decimalPrecision}, scale: ${column.decimalScale ?? 0}',
        );
      }
      b.writeln('@Column(${options.join(', ')})');
      if (column.declarationDefaultSql case final sql?) {
        b.writeln('@DatabaseDefault.sql(${dartLiteral(sql)})');
      }
      if (column.computed case final computed?) {
        b.writeln(
          '@Computed(${dartLiteral(column.declarationComputed!.expression(dialect))}, storage: .${computed.storage.name})',
        );
        issues.add(
          SchemaImportIssue(
            'IMPORT.COMPUTED_SQL',
            '${info.name}.${column.name}',
            'Computed SQL was read from ${dialect.name}; review expression portability before using another backend.',
            blocking: false,
          ),
        );
      }
      final type = switch (_importColumn(column, dialect)!) {
        'integer' => 'int',
        'text' => 'String',
        'boolean' => 'bool',
        'real' => 'double',
        'decimal' => 'Decimal',
        'dateTime' => 'DateTime',
        'date' => 'LocalDate',
        'time' => 'LocalTime',
        'localDateTime' => 'LocalDateTime',
        'bytes' => 'Uint8List',
        'json' => 'SqlJson',
        final kind => throw StateError(
          'Unexpected imported column kind: $kind',
        ),
      };
      b.writeln(
        'final $type${column.nullable ? '?' : ''} ${fields[info.name]![column.name]};',
      );
    }
    if (checks.isNotEmpty) {
      issues.add(
        SchemaImportIssue(
          'IMPORT.CHECK_SQL',
          info.name,
          'CHECK expressions use ${dialect.name} SQL. Review other-dialect overrides before deploying this declaration elsewhere.',
          blocking: false,
        ),
      );
    }
    // @Id order follows constructor order. A physical primary key may order its
    // columns differently from the table's column declarations.
    final constructorColumns = [
      ...info.primaryKey,
      for (final column in info.columns)
        if (!info.primaryKey.contains(column.name)) column.name,
    ];
    b.writeln('const $entity({');
    for (final column in constructorColumns) {
      b.writeln('required this.${fields[info.name]![column]},');
    }
    b.writeln('});');
    b.writeln('}');
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
