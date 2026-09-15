part of '../../generate.dart';

/// Offline generated code and its fixed SQL/codec contracts. Native checks are
/// explicit: generation does not claim that a database has accepted the SQL.
final class GeneratedQueries {
  final String dart;
  final Map<String, Object?> manifest;
  const GeneratedQueries(this.dart, this.manifest);
}

Future<GeneratedQueries> generateQueries(
  String sourcePath, {
  String? outputPath,
}) async {
  final source = p.normalize(p.absolute(sourcePath));
  final output = p.normalize(
    p.absolute(outputPath ?? p.setExtension(source, '.queries.dart')),
  );
  if (source == output || p.extension(output) != '.dart') {
    throw const GenerationException(
      'Query output must be a separate .dart file.',
    );
  }
  final contexts = AnalysisContextCollection(includedPaths: [source]);
  try {
    final resolved = await contexts
        .contextFor(source)
        .currentSession
        .getResolvedUnit(source);
    if (resolved is! ResolvedUnitResult) {
      throw GenerationException('Cannot analyze $source.');
    }
    final errors = resolved.diagnostics.where(
      (e) => e.severity.name.toLowerCase() == 'error',
    );
    if (errors.isNotEmpty) {
      throw GenerationException(errors.map((e) => e.toString()).join('\n'));
    }
    return await _generateQueries(
      resolved.unit,
      resolved.libraryElement,
      p.relative(source, from: p.dirname(output)).replaceAll(r'\', '/'),
      (uri) => uri.scheme == 'file'
          ? p
                .relative(uri.toFilePath(), from: p.dirname(output))
                .replaceAll(r'\', '/')
          : uri.toString(),
      (path) => File(p.join(p.dirname(source), path)).readAsString(),
    );
  } finally {
    await contexts.dispose();
  }
}

Future<void> writeGeneratedQueries(String source, {String? output}) async {
  output ??= p.setExtension(source, '.queries.dart');
  final result = await generateQueries(source, outputPath: output);
  final file = File(output);
  await file.parent.create(recursive: true);
  await file.writeAsString(result.dart);
}

/// Re-analysis prevents checking stale SQL, parameter codecs or generated code.
Future<GeneratedQueries> checkGeneratedQueries(
  String source, {
  String? output,
}) async {
  output ??= p.setExtension(source, '.queries.dart');
  final result = await generateQueries(source, outputPath: output);
  if (await File(output).readAsString() != result.dart) {
    throw const GenerationException(
      'Named SQL output is stale. Run queries generate first.',
    );
  }
  return result;
}

final class _NamedQuery(
  final _Entity result,
  final List<_Field> parameters,
  final Map<SqlDialect, String> sql,
);

Future<GeneratedQueries> _generateQueries(
  CompilationUnit unit,
  LibraryElement library,
  String sourceImport,
  String Function(Uri) importUri,
  Future<String> Function(String) readSql,
) async {
  final names = _DartNames(library.uri, importUri);
  final reader = _SchemaReader(unit, library.typeSystem, names);
  final aliases = {
    for (final alias in unit.declarations.whereType<GenericTypeAlias>())
      alias.name.lexeme: alias,
  };
  final queries = <_NamedQuery>[];
  RecordTypeAnnotation record(TypeAnnotation type) {
    if (type is RecordTypeAnnotation) return type;
    final alias = aliases[type.toSource()];
    if (alias == null ||
        alias.typeParameters != null ||
        alias.type is! RecordTypeAnnotation) {
      throw const GenerationException(
        'Named SQL requires non-generic record typedefs in the source library.',
      );
    }
    return alias.type as RecordTypeAnnotation;
  }

  List<_Field> fields(RecordTypeAnnotation record, {required bool parameters}) {
    if (record.positionalFields.isNotEmpty) {
      throw const GenerationException(
        'Named SQL records require named fields.',
      );
    }
    final fields = [
      for (final f
          in record.namedFields?.fields ?? <RecordTypeAnnotationNamedField>[])
        reader._readField(f),
    ];
    for (final f in fields) {
      if (f.id ||
          f.generated ||
          f.unique ||
          f.defaultSql != null ||
          f.integerBits != null ||
          f.decimalPrecision != null) {
        throw const GenerationException(
          'Query fields accept codec and column-name annotations only.',
        );
      }
      if (parameters && f.column != _snake(f.name)) {
        throw const GenerationException(
          'SQL parameters use Dart field names, without ColumnName.',
        );
      }
    }
    if (!parameters &&
        (fields.isEmpty ||
            fields.map((f) => f.column).toSet().length != fields.length)) {
      throw const GenerationException(
        'Query results require distinct named columns.',
      );
    }
    return fields;
  }

  for (final declaration
      in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
    for (final variable in declaration.variables.variables) {
      final call = variable.initializer;
      if (call is! MethodInvocation ||
          call.methodName.name != 'sqlQuery' ||
          call.methodName.element?.library?.uri.toString() !=
              'package:orm/schema.dart') {
        continue;
      }
      final types = call.typeArguments?.arguments;
      if (types == null ||
          types.length != 2 ||
          types.first is RecordTypeAnnotation) {
        throw const GenerationException(
          'sqlQuery<Result, Parameters> requires an explicit result typedef.',
        );
      }
      final name = variable.name.lexeme;
      if (name.startsWith('_')) {
        throw const GenerationException('Named queries must be public.');
      }
      if ({
        'driver',
        'onQuery',
        'onAcquire',
        'onDecode',
        'capabilities',
        'dialect',
        'inTransaction',
        'inSession',
        'table',
        'registerSchema',
        'invalidate',
        'execute',
        'session',
        'discard',
        'transaction',
        'savepoint',
        'close',
        'hashCode',
        'runtimeType',
        'toString',
        'noSuchMethod',
      }.contains(name)) {
        throw GenerationException('$name conflicts with a Database member.');
      }
      if (types.first.toSource().startsWith('_')) {
        throw const GenerationException(
          'Query result typedefs must be public.',
        );
      }
      final resultFields = fields(record(types.first), parameters: false);
      final parameterFields = fields(record(types.last), parameters: true);
      final sql = <SqlDialect, String>{};
      for (final dialect in SqlDialect.values) {
        final path = reader._namedString(call, dialect.name);
        if (path == null) continue;
        if (path.isEmpty ||
            p.url.isAbsolute(path) ||
            path.contains(r'\') ||
            Uri.parse(path).hasScheme) {
          throw const GenerationException(
            'SQL paths must be relative to the declaring library.',
          );
        }
        final source = await readSql(path);
        final template = SqlTemplate(source, dialect: dialect);
        if (template.parameters.length != parameterFields.length ||
            !parameterFields.every(
              (f) => template.parameters.contains(f.name),
            )) {
          throw GenerationException(
            '$name (${dialect.name}): SQL parameters differ from the record fields.',
          );
        }
        sql[dialect] = source;
      }
      if (sql.isEmpty) {
        throw GenerationException('$name needs at least one SQL file.');
      }
      if (queries.any((q) => _snake(q.result.name) == _snake(name))) {
        throw GenerationException('Conflicting query name $name.');
      }
      queries.add(
        _NamedQuery(
          _Entity(
            name,
            '_orm_sql_${_snake(name)}',
            types.first.toSource(),
            resultFields,
          ),
          parameterFields,
          sql,
        ),
      );
    }
  }
  if (queries.isEmpty) {
    throw const GenerationException(
      'No sqlQuery<Result, Parameters>() declarations found.',
    );
  }
  return GeneratedQueries(
    DartFormatter(languageVersion: library.languageVersion.effective)
        .format(_emitQueries(queries, sourceImport, names)),
    {
      'format': 1,
      'source': sourceImport,
      'queries': [
        for (final query in queries)
          {
            'name': query.result.name,
            'parameters': [
              for (final f in query.parameters)
                {'name': f.name, 'type': f.storage, 'nullable': f.nullable},
            ],
            'columns': [
              for (final f in query.result.fields)
                {'name': f.column, 'type': f.storage, 'nullable': f.nullable},
            ],
            'sql': {
              for (final entry in query.sql.entries)
                entry.key.name: entry.value,
            },
          },
      ],
    },
  );
}

String _emitQueries(
  List<_NamedQuery> queries,
  String sourceImport,
  _DartNames names,
) {
  final b = StringBuffer('// GENERATED CODE - DO NOT MODIFY BY HAND.\n\n')
    ..writeln("import 'package:orm/orm.dart';")
    ..writeln('import ${_literal(sourceImport)} as models;');
  if (names.typedData) b.writeln("import 'dart:typed_data';");
  for (final (uri, prefix) in names.imports) {
    b.writeln('import ${_literal(uri)} as $prefix;');
  }
  if (queries.any((q) => q.parameters.isNotEmpty)) {
    b.writeln(
      'Expr<T> _bindSqlParameter<T>(T input, Codec<T> codec) => value(input, codec);',
    );
  }
  for (final query in queries) {
    final entity = query.result;
    for (final f in entity.fields) {
      b.writeln(
        'final ${_queryColumn(entity, f)} = Column<${f.type}>(${_literal(f.column)}, ${f.codec}, nullable: ${f.nullable});',
      );
    }
    b.writeln(
      'final class ${entity.fieldsType} extends Fields { ${entity.fieldsType}(super.table);',
    );
    for (final f in entity.fields) {
      b.writeln('late final ${f.name} = column(${_queryColumn(entity, f)});');
    }
    b.writeln('}');
    b.writeln(
      'final _sqlDefinition${entity.symbol} = SqlQueryDefinition<${entity.rowType}, ${entity.fieldsType}>('
      'Table(TableSchema(${_literal(entity.table)}, columns: [${entity.fields.map((f) => _queryColumn(entity, f)).join(', ')}]), '
      '${entity.fieldsType}.new, (row) => ${_recordSelection(entity.fields, 'row')}), {'
      '${query.sql.entries.map((entry) => 'SqlDialect.${entry.key.name}: SqlTemplate(${_literal(entry.value)}, dialect: SqlDialect.${entry.key.name})').join(', ')}'
      '});',
    );
    final backend = query.sql.length == 2
        ? 'B'
        : query.sql.keys.single == SqlDialect.sqlite
        ? 'Sqlite'
        : 'Postgres';
    b.writeln(
      'extension ${entity.symbol}Sql${backend == 'B' ? '<B extends Backend>' : ''} on Database<$backend> {'
      'Query<${entity.rowType}, ${entity.fieldsType}> ${entity.name}('
      '${query.parameters.isEmpty ? '' : '{${query.parameters.map((f) => '${f.nullable ? '' : 'required '}${f.type} ${f.name}').join(', ')}}'}'
      ') => _sqlDefinition${entity.symbol}.bind(this, {'
      '${query.parameters.map((f) => '${_literal(f.name)}: _bindSqlParameter(${f.name}, ${f.codec})').join(', ')}'
      '}); }',
    );
  }
  return b.toString();
}

String _queryColumn(_Entity entity, _Field field) =>
    '_sqlColumn${entity.symbol}_${entity.fields.indexOf(field)}';

var _queryCheckSerial = 0;

/// Compile each declared query on one backend, without executing its SELECT.
/// SQLite reports structure only. PostgreSQL additionally checks native storage
/// families. Neither backend proves expression nullability or custom codecs.
Future<List<Map<String, Object?>>> checkSqlQueries(
  Database<Backend> db,
  GeneratedQueries generated,
) => db.session((session) async {
  final reports = <Map<String, Object?>>[];
  for (final query
      in (generated.manifest['queries']! as List)
          .cast<Map<String, Object?>>()) {
    final source = (query['sql']! as Map<String, Object?>)[db.dialect.name];
    if (source == null) continue;
    final parameters = (query['parameters']! as List)
        .cast<Map<String, Object?>>();
    final columns = (query['columns']! as List).cast<Map<String, Object?>>();
    final command = SqlTemplate(source as String, dialect: db.dialect).compile(
      db.capabilities,
      {
        for (final parameter in parameters)
          parameter['name']! as String: value<Object?>(
            null,
            Codec<Object?>(parameter['type']! as String, (v) => v, (v) => v),
          ),
      },
    );
    String quote(String name) => '"${name.replaceAll('"', '""')}"';
    final projected =
        'SELECT ${columns.map((c) => '"_orm_check".${quote(c['name']! as String)}').join(', ')} '
        'FROM (\n${command.sql}\n) AS "_orm_check"';
    List<String>? nativeTypes;
    try {
      if (db.dialect == SqlDialect.sqlite) {
        await session.execute(
          SqlCommand('EXPLAIN $projected', command.parameters),
        );
      } else {
        final name =
            '_orm_check_${DateTime.now().microsecondsSinceEpoch}_${_queryCheckSerial++}';
        await session.execute(
          SqlCommand('PREPARE ${quote(name)} AS $projected'),
        );
        try {
          final result = await session.execute(
            SqlCommand(
              r'SELECT pg_catalog.format_type(t.kind::oid, NULL) '
              r'FROM pg_catalog.pg_prepared_statements p, '
              r'unnest(p.result_types) WITH ORDINALITY AS t(kind, position) '
              r'WHERE p.name = $1 ORDER BY t.position',
              [name],
            ),
          );
          nativeTypes = [for (final row in result.rows) row.single as String];
          if (nativeTypes.length != columns.length) {
            throw const GenerationException(
              'Database returned a different result shape.',
            );
          }
          for (var i = 0; i < columns.length; i++) {
            if (!_queryStorageMatches(
              columns[i]['type']! as String,
              nativeTypes[i],
            )) {
              throw GenerationException(
                '${columns[i]['name']}: declared ${columns[i]['type']}, database returns ${nativeTypes[i]}. Use an explicit SQL cast or matching codec storage.',
              );
            }
          }
        } finally {
          await session.execute(SqlCommand('DEALLOCATE ${quote(name)}'));
        }
      }
    } catch (error) {
      throw GenerationException(
        '${query['name']} (${db.dialect.name}): $error',
      );
    }
    reports.add({
      'name': query['name'],
      'dialect': db.dialect.name,
      'structureChecked': true,
      'nullabilityChecked': false,
      'columns': [
        for (var i = 0; i < columns.length; i++)
          {
            ...columns[i],
            if (nativeTypes != null) 'nativeType': nativeTypes[i],
          },
      ],
    });
  }
  if (reports.isEmpty) {
    throw const GenerationException('No named queries target this database.');
  }
  return reports;
});

bool _queryStorageMatches(String storage, String native) => switch (storage) {
  'integer' ||
  'bigint' ||
  'decimal' => {'smallint', 'integer', 'bigint', 'numeric'}.contains(native),
  'real' => {
    'real',
    'double precision',
    'numeric',
    'smallint',
    'integer',
    'bigint',
  }.contains(native),
  'text' => {'text', 'character varying', 'character', 'name'}.contains(native),
  'boolean' => native == 'boolean',
  'instant' => native == 'timestamp with time zone',
  'date' => native == 'date',
  'time' => native == 'time without time zone',
  'local_datetime' => native == 'timestamp without time zone',
  'json' => {'json', 'jsonb'}.contains(native),
  'blob' => native == 'bytea',
  _ => false,
};
