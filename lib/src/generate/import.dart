part of '../../generate.dart';

/// A catalog fact that needs manual handling. Blocking issues prevent a faithful
/// declaration of the affected table or relationship; other issues retain objects
/// which must stay in reviewed, database-specific migrations.
final class SchemaImportIssue {
  final String code;
  final String object;
  final String detail;
  final bool blocking;
  const SchemaImportIssue(
    this.code,
    this.object,
    this.detail, {
    this.blocking = true,
  });
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
  final SqlDialect dialect;
  final String schema;
  final String dart;
  final Map<String, String> entities;
  final Map<String, Map<String, String>> fields;
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
  bool get hasBlockingIssues => issues.any((i) => i.blocking);
  Map<String, Object?> toJson() => {
    'format': 1,
    'dialect': dialect.name,
    'schema': schema,
    'entities': entities,
    'fields': fields,
    'issues': [for (final issue in issues) issue.toJson()],
  };
}

/// Reads the current PostgreSQL schema or SQLite main database in one consistent
/// catalog snapshot. No user rows are read, inferred, or changed. Omit [tables]
/// to discover user tables; pass exact physical names to restrict the import.
/// Unsupported columns exclude their whole table and produce blocking issues.
Future<ImportedSchema> importSchema(
  Database<Backend> db, {
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
    options: db.dialect == SqlDialect.postgres
        ? const PostgresTransaction(isolation: .repeatableRead, readOnly: true)
        : const SqliteTransaction(),
  );
}

Future<ImportedSchema> _importCatalog(
  Database<Backend> db,
  List<String>? requested,
) async {
  final issues = <SchemaImportIssue>[];
  final schema = db.dialect == SqlDialect.sqlite
      ? 'main'
      : (await db.execute(SqlCommand('SELECT current_schema()')))
                .rows
                .single
                .single
            as String?;
  if (schema == null) {
    throw const OrmException(
      'IMPORT.SCHEMA',
      'Select an existing PostgreSQL schema.',
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
          : '''SELECT c.relname, c.relkind::text,
        CASE WHEN c.relkind IN ('v', 'm') THEN pg_get_viewdef(c.oid) ELSE '' END
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = current_schema() AND c.relkind IN ('r', 'p', 'v', 'm', 'f') ORDER BY c.relname''',
    ),
  );
  final objects = {for (final row in inventory.rows) row[0] as String: row};
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
    if (!{'r', 'table'}.contains(kind)) {
      issues.add(
        SchemaImportIssue(
          'IMPORT.OBJECT',
          name,
          '$kind: ${object[2] ?? ''}',
          blocking:
              requested != null || !{'v', 'm', 'view', 'shadow'}.contains(kind),
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
    } else {
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
          blocking: false,
        ),
      );
    }
    final identities = <String>{};
    final before = issues.where((i) => i.blocking).length;
    if (info.columns.isEmpty) {
      issues.add(
        SchemaImportIssue(
          'IMPORT.EMPTY',
          name,
          'A Record model requires at least one column.',
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
      if (_importType(column, db.dialect) == null) {
        issues.add(
          SchemaImportIssue(
            'IMPORT.TYPE',
            path,
            'No exact declaration mapping for ${column.storageType}. No data values were sampled.',
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
      if (column.generated) {
        if (db.dialect == SqlDialect.postgres &&
            modes[column.name]![1] == 'd' &&
            modes[column.name]![2] == '' &&
            {'SMALLINT', 'INTEGER', 'BIGINT'}.contains(column.storageType) &&
            !column.nullable &&
            _same(info.primaryKey, [column.name])) {
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
(String, String?)? _importType(ColumnInfo column, SqlDialect dialect) =>
    switch ((dialect, column.storageType)) {
      (SqlDialect.sqlite, 'TEXT')
          when column.collation?.toLowerCase() == 'orm_decimal_v1' =>
        ('Decimal', null),
      (SqlDialect.postgres, 'NUMERIC') => ('Decimal', null),
      (SqlDialect.postgres, _) when column.decimalPrecision != null => (
        'Decimal',
        null,
      ),
      (SqlDialect.sqlite, 'INTEGER') ||
      (
        SqlDialect.postgres,
        'SMALLINT' || 'INTEGER' || 'BIGINT',
      ) => ('int', null),
      (SqlDialect.sqlite, 'TEXT')
          when column.collation?.toLowerCase() == 'orm_date_v1' =>
        ('LocalDate', null),
      (SqlDialect.sqlite, 'TEXT')
          when column.collation?.toLowerCase() == 'orm_time_v1' =>
        ('LocalTime', null),
      (SqlDialect.sqlite, 'TEXT')
          when column.collation?.toLowerCase() == 'orm_local_datetime_v1' =>
        ('LocalDateTime', null),
      (SqlDialect.sqlite, 'TEXT')
          when column.collation?.toLowerCase() == 'orm_instant_v1' =>
        ('DateTime', null),
      (_, 'TEXT') => ('String', null),
      (SqlDialect.sqlite, 'REAL') ||
      (SqlDialect.postgres, 'DOUBLE PRECISION') => ('double', null),
      (SqlDialect.sqlite, 'BLOB') ||
      (SqlDialect.postgres, 'BYTEA') => ('Uint8List', null),
      (SqlDialect.postgres, 'BOOLEAN') => ('bool', null),
      (SqlDialect.postgres, 'TIMESTAMPTZ') => ('DateTime', null),
      (SqlDialect.postgres, 'DATE') => ('LocalDate', null),
      (SqlDialect.postgres, 'TIME WITHOUT TIME ZONE') => ('LocalTime', null),
      (SqlDialect.postgres, 'TIMESTAMP WITHOUT TIME ZONE') => (
        'LocalDateTime',
        null,
      ),
      (SqlDialect.postgres, 'JSONB') => ('SqlJson', 'Codecs.jsonDocument'),
      _ => null,
    };

String _importQuote(String name) => '"${name.replaceAll('"', '""')}"';
String _importCap(String name) => name[0].toUpperCase() + name.substring(1);

final class _ImportNames {
  final used = <String>{
    ...Keyword.keywords.keys,
    'table',
    'column',
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
    'driver',
    'capabilities',
    'dialect',
    'inTransaction',
    'inSession',
    'execute',
    'session',
    'transaction',
    'savepoint',
    'discard',
    'close',
    'registerSchema',
    'invalidate',
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
    'DecimalDigits',
    'entity',
    'Id',
    'Unique',
    'ColumnName',
    'Default',
    'UseCodec',
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
        '${_importCap(v)}Row',
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
  final b = StringBuffer(
    '// Imported catalog draft. Review the import report before baselining.\n\n',
  )..writeln("import 'package:orm/schema.dart';");
  if (infos.values.any(
    (t) => t.columns.any((c) => _importType(c, dialect)?.$1 == 'Uint8List'),
  )) {
    b.writeln("import 'dart:typed_data';");
  }
  for (final info in infos.values) {
    final entity = entities[info.name]!;
    b.writeln('\ntypedef ${_importCap(entity)}Row = ({');
    for (final c in info.columns) {
      final type = _importType(c, dialect)!;
      b.writeln('@ColumnName(${_literal(c.name)})');
      if (c.integerBits != null && c.integerBits != 64) {
        b.writeln('@IntegerBits(${c.integerBits})');
      }
      if (c.decimalPrecision != null) {
        b.writeln(
          '@DecimalDigits(${c.decimalPrecision}, ${c.decimalScale ?? 0})',
        );
      }
      if (generated[info.name]!.contains(c.name)) b.writeln('@Id.generated()');
      if (c.declarationDefaultSql != null) {
        b.writeln('@Default.sql(${_literal(c.declarationDefaultSql!)})');
      }
      if (type.$2 != null) b.writeln('@UseCodec(${type.$2})');
      b.writeln(
        '${type.$1}${c.nullable ? '?' : ''} ${fields[info.name]![c.name]},',
      );
    }
    b.writeln(
      '});\nfinal $entity = entity<${_importCap(entity)}Row>(table: ${_literal(info.name)});',
    );
  }
  String selector(String table, List<String> columns) {
    final values = columns.map((c) => 'row.${fields[table]![c]}').toList();
    return '(row) => ${values.length == 1 ? values.single : '(${values.join(', ')})'}';
  }

  for (final info in infos.values) {
    final entity = entities[info.name]!;
    void constraint(String kind, List<String> columns, {String extra = ''}) {
      final symbol = names.take('$entity${_importCap(kind)}');
      b.writeln(
        'final $symbol = $entity.$kind(${selector(info.name, columns)}$extra);',
      );
    }

    if (info.primaryKey.isNotEmpty && generated[info.name]!.isEmpty) {
      constraint('primaryKey', info.primaryKey);
    }
    final unique = info.uniqueKeys.toList()
      ..sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    for (final key in unique) {
      constraint('unique', key);
    }
    final indexes = info.indexes.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final index in indexes) {
      constraint(
        'index',
        index.columns,
        extra: ', name: ${_literal(index.name)}, unique: ${index.unique}',
      );
    }
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
          ].any((k) => _same(k, key.targetColumns)) ||
          key.columns.asMap().entries.any(
            (entry) =>
                _importType(
                  info.columns.singleWhere((c) => c.name == entry.value),
                  dialect,
                )?.$1 !=
                _importType(
                  target.columns.singleWhere(
                    (c) => c.name == key.targetColumns[entry.key],
                  ),
                  dialect,
                )?.$1,
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
      b.writeln(
        'final $relation = $entity.key(${selector(info.name, key.columns)}).references(${entities[key.target]}.key(${selector(key.target, key.targetColumns)}), inverse: ${_literal(inverse)}, onDelete: .$action);',
      );
    }
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
