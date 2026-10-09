import 'dart:convert';

import 'package:orm/database.dart';
import 'package:orm/schema.dart';

import 'model.dart';

String emitSnapshot(SchemaModel model, {required Engine engine}) =>
    '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Frozen physical schema. Independent of current application models.
import 'package:orm/database.dart';
import 'package:orm/schema.dart';

/// Reviewed schema state for this database engine.
const frozenSchema = SchemaSnapshot(
  engine: Engine.${engine.name},
  tables: [${model.tables.map(_tableDefinition).join(',')}],
);
''';

String emitDatabase(
  SchemaModel model, {
  required String modelImport,
  required String databaseName,
}) {
  final sessionName =
      '${databaseName.endsWith('Database') ? databaseName.substring(0, databaseName.length - 8) : databaseName}Session';
  final importedTypes = {...model.tables.map((table) => table.dartName)};
  final scopedNames = {
    for (final table in model.tables) ...[
      table.getterName,
      for (final field in table.fields) field.name,
      for (final parameter in table.parameters) parameter.name,
    ],
  };
  var modelPrefix = 'models';
  for (var suffix = 2; scopedNames.contains(modelPrefix); suffix++) {
    modelPrefix = 'models$suffix';
  }
  final shapes = <String>{};
  for (final selection in model.selections) {
    if (shapes.add('${selection.table.name}:${selection.shape}')) {
      importedTypes.add(selection.name);
    }
  }
  final buffer = StringBuffer('''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Regenerate with dart run bin/orm.dart generate.
${model.tables.any((table) => table.fields.any((field) => field.column.type == ScalarType.bytes)) ? "import 'dart:typed_data';" : ''}
import 'package:orm/database.dart';
import 'package:orm/migration.dart' show freezeSnapshot;
import 'package:orm/query.dart';
import 'package:orm/schema.dart';
import ${_literal(modelImport)} as $modelPrefix show ${importedTypes.join(', ')};

${model.tables.any((table) => table.insertableFields.isNotEmpty) ? '''const _absent = Object();
bool _provided(Object? value) => !identical(value, _absent);''' : ''}
${model.tables.any((table) => table.numericFields.isNotEmpty) ? 'num _number(Object? value) => value as num;' : ''}

Database _openDatabase(Driver driver, {DatabaseObserver? onEvent}) {
  freezeSnapshot(SchemaSnapshot(
    engine: driver.engine,
    tables: const [${model.tables.map((table) => table.definitionName).join(',')}],
  ));
  return openDatabase(driver, observer: onEvent);
}

/// Owns the supplied driver. Close it after completing all database work.
///
/// Validates every model against the driver's engine before taking ownership.
/// If construction fails, the caller retains the driver; no SQL is executed.
final class $databaseName {
  $databaseName(Driver driver, {DatabaseObserver? onEvent})
      : _database = _openDatabase(driver, onEvent: onEvent);
  final Database _database;
  /// The owned runtime for migrations and raw database operations.
  ///
  /// This shares the supplied driver and lifecycle with the generated client.
  /// Close the generated client after all work; do not wrap its driver again.
  Database get database => _database;
  /// Raw execution and generated tables in the database's root scope.
  late final $sessionName session = $sessionName._(_database.session);
  ${model.tables.map((table) => '/// Typed access to ${_comment(table.name)}.\n${table.dartName}Table get ${table.getterName} => session.${table.getterName};').join('\n')}
  /// Commits successful work and rolls back callback or SQL failures.
  ///
  /// A caught SQL failure still rolls back. The callback scope expires on return.
  Future<T> transaction<T>(Future<T> Function($sessionName session) action, {
    Isolation isolation = Isolation.serializable,
    bool readOnly = false,
  }) => _database.transaction((session) => action($sessionName._(session)), isolation: isolation, readOnly: readOnly);
  /// Waits for active work and releases the owned driver.
  Future<void> close() => _database.close();
}

/// Generated tables share one explicit raw execution scope.
final class $sessionName implements Session {
  $sessionName._(this._session);
  final Session _session;
  ${model.tables.map((table) => '/// Typed access to ${_comment(table.name)} in this scope.\nlate final ${table.dartName}Table ${table.getterName} = ${table.dartName}Table._(TableQuery<$modelPrefix.${table.dartName}>(_session, ${table.definitionName}, _decode${table.dartName}));').join('\n')}
  @override
  Engine get engine => _session.engine;
  @override
  String get schema => _session.schema;
  @override
  Capabilities get capabilities => _session.capabilities;
  @override
  bool get inTransaction => _session.inTransaction;
  @override
  Future<QueryResult> run(String sql, {List<Object?> parameters = const []}) => _session.run(sql, parameters: parameters);
}
''');
  for (final table in model.tables) {
    buffer.writeln(
      'const ${table.definitionName} = ${_tableDefinition(table)};',
    );
    buffer.writeln(
      '$modelPrefix.${table.dartName} _decode${table.dartName}(List<Object?> row) => $modelPrefix.${table.dartName}(${table.parameters.map((parameter) {
        final index = table.fields.indexWhere((field) => field.name == parameter.name);
        return '${parameter.named ? '${parameter.name}: ' : ''}${_decode(table.fields[index], 'row[$index]')}';
      }).join(',')});',
    );
    _emitTable(
      buffer,
      table,
      model.selections.where((selection) => selection.table == table).toList(),
      modelPrefix: modelPrefix,
    );
  }
  return buffer.toString();
}

void _emitTable(
  StringBuffer buffer,
  TableModel table,
  List<SelectionModel> selections, {
  required String modelPrefix,
}) {
  final row = '$modelPrefix.${table.dartName}';
  final name = table.dartName;
  final fields = table.fields;
  final mutable = table.mutableFields;
  final numeric = table.numericFields;
  final keyName = _keyParameter(numeric);
  buffer.writeln('''
/// An immutable query over the ${_comment(table.name)} table.
final class ${name}Table {
  ${name}Table._(this._query);
  final TableQuery<$row> _query;
  /// Creates one row. Omitted fields use database defaults; null is retained.
  ///
  /// Requires an unfiltered, unordered query without pagination. SQL errors
  /// propagate and roll back an enclosing explicit transaction.
  ${name}Create get create => _${name}Create(_query);
  ${table.uniqueFields.isEmpty ? '' : '''/// Creates one row, or returns null on a conflict with the selected unique field.
  ///
  /// The conflict value must be supplied and non-null. Other constraint errors
  /// propagate. Query filters, ordering and pagination are rejected.
  ${name}CreateIfAbsent get createIfAbsent => _${name}CreateIfAbsent(_query);'''}
  /// Updates supplied fields by primary key and the current where scope.
  ///
  /// Omitted fields are unchanged. Returns null when the key and where scope do
  /// not match. Empty updates, ordering and pagination fail before SQL.
  ${name}Update get update => _${name}Update(_query);
  /// Fetches a row by its primary key.
  Future<$row?> get(${table.primaryKey.type} id) => _query.get(id);
  /// Deletes a row by primary key and returns its affected row count.
  Future<int> delete(${table.primaryKey.type} id) => _query.deleteById(id);
  /// Fetches all matching full model rows.
  Future<List<$row>> all() => _query.all();
  /// Reads bounded batches within an active transaction scope.
  Stream<$row> stream({int fetchSize = 500}) => _query.stream(fetchSize: fetchSize);
  /// Adds field predicates joined by AND.
  ${name}Table where({${fields.map((field) => 'Filter<${field.type}>? ${field.name}').join(',')}}) => ${name}Table._(_query.whereFields({${fields.map((field) => "${_literal(field.name)}: ?${field.name}").join(',')}}));
  /// Adds field predicates joined by OR, combined with earlier filters by AND.
  /// An empty group fails before SQL. Field types and nullability are retained.
  ${name}Table whereAny({${fields.map((field) => 'Filter<${field.type}>? ${field.name}').join(',')}}) => ${name}Table._(_query.whereAnyFields({${fields.map((field) => "${_literal(field.name)}: ?${field.name}").join(',')}}));
  /// Adds one ordering field. Chain calls for multiple ordering fields.
  ${name}Table orderBy({${fields.map((field) => 'Direction? ${field.name}').join(',')}}) => ${name}Table._(_query.orderByFields({${fields.map((field) => "${_literal(field.name)}: ?${field.name}").join(',')}}));
  /// Limits result rows; negative limits fail before SQL execution.
  ${name}Table limit(int count) => ${name}Table._(_query.limit(count));
  /// Skips result rows; negative offsets fail before SQL execution.
  ${name}Table offset(int count) => ${name}Table._(_query.offset(count));
  /// Executes a statically registered selection; unknown types fail before SQL.
  Future<List<T>> select<T>() {
    if (T == $row) { return _query.all().then((rows) => rows.cast<T>()); }
''');
  final emittedShapes = <String>{};
  for (final selection in selections) {
    if (!emittedShapes.add(selection.shape)) continue;
    buffer.writeln('''
    if (T == $modelPrefix.${selection.name}) {
      return _query.selectRows<$modelPrefix.${selection.name}>([${selection.fields.map((field) => _literal(field.name)).join(',')}], (row) => (${selection.fields.indexed.map((entry) => '${entry.$2.name}: ${_decode(entry.$2, 'row[${entry.$1}]')}').join(',')},)).then((rows) => rows.cast<T>());
    }
''');
  }
  buffer.writeln('''
    throw ArgumentError('Unregistered selection type \$T for ' ${_literal('${table.name}.')});
  }
''');
  if (numeric.isNotEmpty) {
    for (final operation in ['increment', 'decrement']) {
      final operationName =
          '$name${operation[0].toUpperCase()}${operation.substring(1)}';
      buffer.writeln('''
  /// Atomically $operation supplied fields by key, retaining the where scope.
  $operationName get $operation => _$operationName(_query);
''');
    }
  }
  buffer.writeln('}');
  _emitCallable(
    buffer,
    table,
    '${name}Create',
    table.insertableFields,
    create: true,
    modelPrefix: modelPrefix,
  );
  _emitCallable(
    buffer,
    table,
    '${name}Update',
    mutable,
    create: false,
    modelPrefix: modelPrefix,
  );
  if (table.uniqueFields.isNotEmpty) {
    _emitCreateIfAbsent(buffer, table, modelPrefix: modelPrefix);
  }
  if (numeric.isNotEmpty) {
    for (final operation in ['increment', 'decrement']) {
      final operationName =
          '$name${operation[0].toUpperCase()}${operation.substring(1)}';
      buffer.writeln('''
/// Typed atomic arithmetic arguments for ${_comment(table.name)}.
abstract interface class $operationName {
  /// Returns the changed row, or null when the key, filters or integer bounds
  /// do not match. Integer arithmetic stays within signed 64-bit bounds.
  /// SQLite REAL bounds also return null; PostgreSQL REAL overflow is a SQL error.
  Future<$row?> call(${table.primaryKey.type} $keyName, {${numeric.map((field) => '${field.baseType} ${field.name}').join(',')}});
}
final class _$operationName implements $operationName {
  _$operationName(this._query);
  final TableQuery<$row> _query;
  @override
  Future<$row?> call(${table.primaryKey.type} $keyName, {${numeric.map((field) => 'Object? ${field.name} = _absent').join(',')}}) => _query.${operation}ById($keyName, {${numeric.map((field) => "if (_provided(${field.name})) ${_literal(field.name)}: _number(${field.name})").join(',')}});
}
''');
    }
  }
}

void _emitCallable(
  StringBuffer buffer,
  TableModel table,
  String name,
  List<FieldModel> fields, {
  required bool create,
  required String modelPrefix,
}) {
  final key = _keyParameter(fields);
  final id = create ? '' : '${table.primaryKey.type} $key';
  final named = fields.isEmpty
      ? ''
      : '{${fields.map((field) => '${create && !field.column.nullable && !field.column.identity && field.column.defaultValue == null ? 'required ' : ''}${field.type} ${field.name}').join(',')}}';
  final arguments = [
    if (id.isNotEmpty) id,
    if (named.isNotEmpty) named,
  ].join(',');
  final result = '$modelPrefix.${table.dartName}${create ? '' : '?'}';
  final implementationNamed = fields.isEmpty
      ? ''
      : '{${fields.map((field) => 'Object? ${field.name} = _absent').join(',')}}';
  buffer.writeln('''
/// Typed ${create ? 'creation' : 'partial update'} arguments for ${_comment(table.name)}.
abstract interface class $name {
  /// ${create ? 'Returns the single inserted row; SQL failures propagate.' : 'Returns the updated row, or null when key and where scope do not match.'}
  Future<$result> call($arguments);
}
final class _$name implements $name {
  _$name(this._query);
  final TableQuery<$modelPrefix.${table.dartName}> _query;
  @override
  Future<$result> call(${[if (id.isNotEmpty) id, if (implementationNamed.isNotEmpty) implementationNamed].join(',')}) => _query.${create ? 'insert(' : 'updateById($key, '}{${fields.map((field) => "if (_provided(${field.name})) ${_literal(field.name)}: ${field.name}").join(',')}});
}
''');
}

void _emitCreateIfAbsent(
  StringBuffer buffer,
  TableModel table, {
  required String modelPrefix,
}) {
  final fields = table.insertableFields;
  final name = table.dartName;
  final target = _parameterName(fields, 'target');
  final named = fields
      .map(
        (field) =>
            '${!field.column.nullable && field.column.defaultValue == null ? 'required ' : ''}${field.type} ${field.name}',
      )
      .join(',');
  final values = fields
      .map(
        (field) =>
            'if (_provided(${field.name})) ${_literal(field.name)}: ${field.name}',
      )
      .join(',');
  final usedNames = {'hashCode', 'runtimeType', 'toString', 'noSuchMethod'};
  final uniqueFields = <String>[];
  for (final field in table.uniqueFields) {
    var valueName = field.name;
    if (usedNames.contains(valueName)) valueName = '${valueName}Column';
    while (!usedNames.add(valueName)) {
      valueName = '${valueName}Column';
    }
    uniqueFields.add(
      '/// Conflict target: ${_comment(field.name)}.\n'
      'static const $valueName = ${name}Unique._(${_literal(field.name)});',
    );
  }
  buffer.writeln('''
/// Single-column unique constraints that can prevent creation of ${_comment(table.name)}.
final class ${name}Unique {
  const ${name}Unique._(this._field);
  final String _field;
  ${uniqueFields.join('\n')}
}

/// Typed creation arguments with an explicit unique conflict target.
abstract interface class ${name}CreateIfAbsent {
  /// Returns the inserted row, or null for a conflict with the selected target.
  /// The target value must be supplied and non-null; other SQL failures propagate.
  Future<$modelPrefix.$name?> call(${name}Unique $target, {$named});
}
final class _${name}CreateIfAbsent implements ${name}CreateIfAbsent {
  _${name}CreateIfAbsent(this._query);
  final TableQuery<$modelPrefix.$name> _query;
  @override
  Future<$modelPrefix.$name?> call(${name}Unique $target, {${fields.map((field) => 'Object? ${field.name} = _absent').join(',')}}) =>
    _query.insertIfAbsent({$values}, conflictField: $target._field);
}
''');
}

String _decode(FieldModel field, String expression) => field.column.nullable
    ? '$expression == null ? null : decodeValue<${field.baseType}>($expression)'
    : 'decodeValue<${field.type}>($expression)';

String _keyParameter(List<FieldModel> fields) => _parameterName(fields, 'key');

String _parameterName(List<FieldModel> fields, String preferred) {
  var name = preferred;
  while (fields.any((field) => field.name == name)) {
    name = '${name}Value';
  }
  return name;
}

String _tableDefinition(TableModel table) => emitTableDefinition(
  TableDefinition(
    table.name,
    table.fields.map((field) => field.column).toList(),
  ),
);

/// Serializes a physical table without importing application row classes.
String emitTableDefinition(TableDefinition table) =>
    'TableDefinition(${dartLiteral(table.name)}, [${table.columns.map((column) {
      return 'ColumnDefinition(name: ${dartLiteral(column.name)}, field: ${dartLiteral(column.field)}, type: ScalarType.${column.type.name}, nullable: ${column.nullable}, primaryKey: ${column.primaryKey}, identity: ${column.identity}, unique: ${column.unique}${column.defaultValue == null ? '' : ', defaultValue: ${dartLiteral(column.defaultValue)}'}${column.references == null ? '' : ', references: ForeignKey(${dartLiteral(column.references!.table)}, ${dartLiteral(column.references!.column)}, onDelete: ${dartLiteral(column.references!.onDelete)})'})';
    }).join(',')}])';

String _literal(Object? value) => dartLiteral(value);

/// Emits literal values with Dart interpolation escaped.
String dartLiteral(Object? value) {
  if (value is String) return jsonEncode(value).replaceAll(r'$', r'\$');
  return value.toString();
}

String _comment(String value) =>
    value.replaceAll(RegExp(r'[\r\n\u2028\u2029]'), ' ');
