import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;

import '../../runtime.dart';
import '../../sql.dart';
import 'emitter.dart' show modelSelection, rowDeclaration;
import 'exception.dart';
import 'model.dart';
import 'schema/columns.dart';
import 'schema/syntax.dart';
import 'source.dart';
import 'types.dart';

/// Offline generated code and its fixed SQL/codec contracts. Native checks are
/// explicit: generation does not claim that a database has accepted the SQL.
final class GeneratedQueries {
  /// Formatted Dart source for the typed query bindings.
  final String dart;

  /// Resolved SQL and codec metadata used by database validation.
  ///
  /// This is an in-memory report, not a persisted schema or migration format.
  final Map<String, Object?> manifest;

  /// Combines generated [dart] source with its validation [manifest].
  const GeneratedQueries(this.dart, this.manifest);
}

/// Analyzes named SQL declarations and reads their SQL files without writing.
///
/// [outputPath] determines relative Dart imports and defaults to the source
/// basename with a `.queries.dart` extension. Generation validates declarations;
/// use [checkSqlQueries] to ask a selected database to validate the SQL itself.
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
    return await generateResolvedQueries(
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

/// Replaces the generated query bindings only after source validation succeeds.
///
/// [output] defaults to [source] with a `.queries.dart` extension.
Future<void> writeGeneratedQueries(String source, {String? output}) async {
  output ??= p.setExtension(source, '.queries.dart');
  final result = await generateQueries(source, outputPath: output);
  final file = File(output);
  await file.parent.create(recursive: true);
  await file.writeAsString(result.dart);
}

/// Regenerates [source] in memory and rejects a stale generated [output] file.
///
/// Returns the current SQL and codec metadata for [checkSqlQueries]. Throws
/// [GenerationException] when the saved bindings differ from current sources.
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
  final ModelEntity result,
  final List<ModelField> parameters,
  final Map<SqlDialect, String> sql,
);

Future<GeneratedQueries> generateResolvedQueries(
  CompilationUnit unit,
  LibraryElement library,
  String sourceImport,
  String Function(Uri) importUri,
  Future<String> Function(String) readSql,
) async {
  final names = DartNames(library.uri, importUri);
  final queries = <_NamedQuery>[];
  final symbols = {...generatedTypeNames};
  List<ModelField> fields(Expression? expression, {required bool parameters}) {
    if (expression == null && parameters) return [];
    if (expression is! RecordLiteral ||
        expression.fields.any((f) => f is! RecordLiteralNamedField)) {
      throw const GenerationException(
        'Named SQL requires a named Record of column declarations.',
      );
    }
    final fields = [
      for (final f in expression.fields.cast<RecordLiteralNamedField>())
        readColumn(f, library.typeSystem, names).$1,
    ];
    for (final f in fields) {
      if (f.id ||
          f.generated ||
          f.unique ||
          f.defaultSql != null ||
          f.clientDefault != null ||
          f.computed != null ||
          f.temporalPrecision != null ||
          f.integerBits != null ||
          f.decimalPrecision != null) {
        throw const GenerationException(
          'Query columns declare value types and SQL names, without table constraints or defaults.',
        );
      }
      if (parameters && f.column != snakeCase(f.name)) {
        throw const GenerationException(
          'SQL parameters use Dart field names, without a name override.',
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
              'package:orm/src/schema/queries.dart') {
        continue;
      }
      final name = variable.name.lexeme;
      if (!declaration.variables.isFinal || name.startsWith('_')) {
        throw const GenerationException('Named queries must be public.');
      }
      if (databaseMembers.contains(name)) {
        throw GenerationException('$name conflicts with a Database member.');
      }
      final symbol = name[0].toUpperCase() + name.substring(1);
      for (final generated in [symbol, '${symbol}Fields', '${symbol}Sql']) {
        if (!symbols.add(generated)) {
          throw GenerationException(
            'Generated symbol $generated is ambiguous. Rename the Dart query.',
          );
        }
      }
      final resultFields = fields(
        namedArgument(call, 'result'),
        parameters: false,
      );
      final parameterFields = fields(
        namedArgument(call, 'parameters'),
        parameters: true,
      );
      final sql = <SqlDialect, String>{};
      for (final dialect in SqlDialect.values) {
        final path = namedString(call, dialect.name);
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
      if (queries.any((q) => snakeCase(q.result.name) == snakeCase(name))) {
        throw GenerationException('Conflicting query name $name.');
      }
      queries.add(
        _NamedQuery(
          ModelEntity(
            name,
            '_orm_sql_${snakeCase(name)}',
            symbol,
            resultFields,
          ),
          parameterFields,
          sql,
        ),
      );
    }
  }
  if (queries.isEmpty) {
    throw const GenerationException('No sqlQuery(...) declarations found.');
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
  DartNames names,
) {
  final b = StringBuffer('// GENERATED CODE - DO NOT MODIFY BY HAND.\n\n')
    ..writeln("import 'package:orm/sql.dart';");
  if (names.usesSource) {
    b.writeln('import ${dartLiteral(sourceImport)} as models;');
  }
  for (final (uri, symbols) in names.exports) {
    b.writeln('export ${dartLiteral(uri)} show ${symbols.join(', ')};');
  }
  if (names.typedData) b.writeln("import 'dart:typed_data';");
  for (final (uri, prefix) in names.imports) {
    b.writeln('import ${dartLiteral(uri)} as $prefix;');
  }
  if (queries.any((q) => q.parameters.isNotEmpty)) {
    b.writeln(
      'Expr<T> _bindSqlParameter<T>(T input, Codec<T> codec) => value(input, codec);',
    );
  }
  for (final query in queries) {
    final entity = query.result;
    b.writeln(rowDeclaration(entity));
    for (final f in entity.fields) {
      b.writeln(
        'final ${_queryColumn(entity, f)} = Column<${f.type}>(${dartLiteral(f.column)}, ${f.codec}, nullable: ${f.nullable});',
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
      'Table(TableSchema(${dartLiteral(entity.table)}, columns: [${entity.fields.map((f) => _queryColumn(entity, f)).join(', ')}]), '
      '${entity.fieldsType}.new, (row) => ${modelSelection(entity, 'row')}), {'
      '${query.sql.entries.map((entry) => 'SqlDialect.${entry.key.name}: SqlTemplate(${dartLiteral(entry.value)}, dialect: SqlDialect.${entry.key.name})').join(', ')}'
      '});',
    );
    b.writeln(
      'extension ${entity.symbol}Sql on QueryContext {'
      'Query<${entity.rowType}, ${entity.fieldsType}> ${entity.name}('
      '${query.parameters.isEmpty ? '' : '{${query.parameters.map((f) => '${f.nullable ? '' : 'required '}${f.type} ${f.name}').join(', ')}}'}'
      ') => _sqlDefinition${entity.symbol}.bind(this, {'
      '${query.parameters.map((f) => '${dartLiteral(f.name)}: _bindSqlParameter(${f.name}, ${f.codec})').join(', ')}'
      '}); }',
    );
  }
  return b.toString();
}

String _queryColumn(ModelEntity entity, ModelField field) =>
    '_sqlColumn${entity.symbol}_${entity.fields.indexOf(field)}';

var _queryCheckSerial = 0;

/// Compile each declared query on one backend, without executing its SELECT.
/// SQLite, MySQL and MariaDB report structure only. PostgreSQL additionally
/// checks native storage families. These checks do not prove expression
/// nullability or custom codecs.
Future<List<Map<String, Object?>>> checkSqlQueries(
  SqlDatabase<Backend> db,
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
    String quote(String name) => isMysqlDialect(db.dialect)
        ? '`${name.replaceAll('`', '``')}`'
        : '"${name.replaceAll('"', '""')}"';
    final alias = quote('_orm_check');
    final projected =
        'SELECT ${columns.map((c) => '$alias.${quote(c['name']! as String)}').join(', ')} '
        'FROM (\n${command.sql}\n) AS $alias';
    List<String>? nativeTypes;
    try {
      if (isMysqlDialect(db.dialect)) {
        final name =
            '_orm_check_${DateTime.now().microsecondsSinceEpoch}_${_queryCheckSerial++}';
        var prepared = false;
        await session.execute(SqlCommand('SET @$name = ?', [projected]));
        try {
          // EXPLAIN can execute stored functions while planning a derived
          // table (verified on MariaDB 11.8). PREPARE resolves the projection
          // and placeholders without executing the application statement.
          await session.execute(
            SqlCommand('PREPARE ${quote(name)} FROM @$name'),
          );
          prepared = true;
        } finally {
          try {
            if (prepared) {
              await session.execute(
                SqlCommand('DEALLOCATE PREPARE ${quote(name)}'),
              );
            }
            await session.execute(SqlCommand('SET @$name = NULL'));
          } catch (_) {
            // A failed cleanup must not leave a prepared statement or query
            // text attached to a connection returned to another borrower.
            await session.discard();
            rethrow;
          }
        }
      } else if (db.dialect == SqlDialect.sqlite) {
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
      'storageTypesChecked': nativeTypes != null,
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
