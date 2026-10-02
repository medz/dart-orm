import '../schema/model.dart';
import 'model.dart';
import 'source.dart';
import 'types.dart';

String emitSchema(
  List<ModelEntity> schema,
  DartNames names, {
  List<ModelProjection> projections = const [],
}) {
  final b = StringBuffer('// GENERATED CODE - DO NOT MODIFY BY HAND.\n\n')
    ..writeln("import 'package:orm/sql.dart';")
    ..writeln("import 'package:orm/schema_model.dart';");
  final generatedNames = {
    for (final model in schema) ...modelGeneratedSymbols(model),
    for (final projection in projections) ...[
      projection.binding,
      projection.fieldsType,
      projection.descriptor,
    ],
  };
  names.reserveNames(generatedNames);
  final modelPrefix = names.allocatePrefix('orm_model');
  if (schema.isNotEmpty) {
    b.writeln(
      "import 'package:orm/orm.dart' as $modelPrefix show ModelTable, ModelQuery;",
    );
  }
  final projectionPrefix = names.allocatePrefix('orm_projection');
  if (projections.isNotEmpty) {
    b.writeln(
      "import 'package:orm/sql.dart' as $projectionPrefix show Slot, ProjectionType, ProjectionOutput, ProjectionFields, Projection;",
    );
  }
  if (schema.isNotEmpty) {}
  if (names.usesValues ||
      schema.any((e) => e.fields.any((f) => f.codec.startsWith('Codecs.')))) {
    b.writeln("import 'package:orm/values.dart';");
  }
  final groupsPrefix = names.allocatePrefix('orm');
  if (schema.any((entity) => entity.primaryKey.length > 1)) {
    b.writeln("import 'package:orm/sql.dart' as $groupsPrefix show allOf;");
  }
  if (names.usesSource) {
    // Original DTOs must have one library identity across imports and exports.
    // A file-relative source import cannot be mixed with a package export.
    final source = names.importUri(names.source);
    b.writeln("import ${dartLiteral(source)} as ${names.sourcePrefix};");
  }
  for (final (uri, symbols) in names.exports) {
    b.writeln('export ${dartLiteral(uri)} show ${symbols.join(', ')};');
  }
  if (names.typedData) {
    b.writeln("import 'dart:typed_data';");
  }
  for (final (uri, prefix) in names.imports) {
    b.writeln('import ${dartLiteral(uri)} as $prefix;');
  }
  for (final directive in names.factoryImports.directives) {
    b.writeln(directive);
  }
  b.writeln('');
  if (schema.isNotEmpty) {
    var absentType = '_OrmWriteAbsent';
    for (var suffix = 2; generatedNames.contains(absentType); suffix++) {
      absentType = '_OrmWriteAbsent$suffix';
    }
    b.writeln('''
final class $absentType {
const $absentType();
}
const _writeAbsent = $absentType();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);
''');
  }
  for (final entity in schema) {
    for (final f in entity.fields) {
      b.writeln(
        'final ${columnSymbol(entity, f)} = Column<${f.type}>(${dartLiteral(f.column)}, ${f.codec}, '
        'nullable: ${f.nullable}, generated: ${f.generated}${f.defaultSql == null ? '' : ', defaultSql: ${dartLiteral(f.defaultSql!)}'}${f.clientDefault == null ? '' : ', clientDefault: ${f.clientDefault}'}${f.computed == null ? '' : ', computed: ${_computedLiteral(f.computed!)}'}${f.integerBits == null || f.integerBits == 64 ? '' : ', integerBits: ${f.integerBits}'}${f.temporalPrecision == null || f.temporalPrecision == 6 ? '' : ', temporalPrecision: ${f.temporalPrecision}'}${f.decimalPrecision == null ? '' : ', decimalPrecision: ${f.decimalPrecision}'}${f.decimalScale == null || f.decimalScale == 0 ? '' : ', decimalScale: ${f.decimalScale}'});',
      );
    }
    b.writeln(
      'final ${entity.binding}Schema = TableSchema(${dartLiteral(entity.table)}, '
      '${entity.namespace == null ? '' : 'namespace: ${dartLiteral(entity.namespace!)}, '}'
      'columns: [${entity.fields.map((f) => columnSymbol(entity, f)).join(', ')}], '
      'primaryKey: ${dartStringList(entity.columns(entity.primaryKey))}, '
      'uniqueKeys: [${entity.uniqueKeys.map((k) => dartStringList(entity.columns(k))).join(', ')}], '
      'indexes: [${entity.indexes.map((i) => 'IndexSchema(${dartLiteral(i.name)}, ${dartStringList(entity.columns(i.keys))}, unique: ${i.unique})').join(', ')}], '
      '${entity.checks.isEmpty ? '' : 'checks: [${entity.checks.map((c) => 'CheckSchema.forDialects(${c.name == null ? 'null' : dartLiteral(c.name!)}, sqlite: ${dartLiteral(c.sqlite)}, postgres: ${dartLiteral(c.postgres)}, mysql: ${c.mysql == null ? 'null' : dartLiteral(c.mysql!)}, mariadb: ${c.mariadb == null ? 'null' : dartLiteral(c.mariadb!)})').join(', ')}], '}'
      'foreignKeys: [${entity.edges.where((e) => e.isForeignKey).map((e) => 'ForeignKey(${dartStringList(entity.columns(e.parentKeys))}, ${dartLiteral(e.target.table)}, ${dartStringList(e.target.columns(e.childKeys))}, onDelete: ${dartLiteral(e.onDelete!)}${e.target.namespace == null ? '' : ', targetNamespace: ${dartLiteral(e.target.namespace!)}'})').join(', ')}]);',
    );
    b.writeln(
      'final class ${entity.fieldsType} extends Fields {\n ${entity.fieldsType}(super.table);',
    );
    for (final f in entity.fields) {
      b.writeln(
        'late final ${f.name} = ${f.computed == null ? 'column' : 'readColumn'}(${columnSymbol(entity, f)});',
      );
    }
    for (final edge in entity.edges) {
      if (edge.onDelete == null) {
        b.writeln(
          '/// Read-only navigation; no database foreign key or write effects.',
        );
      }
      b.writeln(
        'Relation<${edge.target.rowType}, ${edge.target.fieldsType}> get ${edge.name} => '
        'Relation(${edge.target.binding}Table, parent: [${edge.parentKeys.join(', ')}], '
        'child: (row) => [${edge.childKeys.map((k) => 'row.$k').join(', ')}]);',
      );
    }
    b.writeln('}');
    final selection = modelSelection(entity, 'row');
    b.writeln(
      'final ${entity.binding}Table = Table<${entity.rowType}, ${entity.fieldsType}>('
      '${entity.binding}Schema, ${entity.fieldsType}.new, (row) => $selection);',
    );
    _emitWriteInputs(b, entity);
    _emitCreator(b, entity);
    _emitPatcher(b, entity, modelPrefix);
    b.writeln('''
/// The generated root; all read composition uses the common Query core.
final class ${entity.setType} extends $modelPrefix.ModelTable<${entity.rowType}, ${entity.fieldsType}, ${entity.symbol}Insert, ${entity.symbol}Patch> {
${entity.setType}(QueryContext db) : super(db, ${entity.binding}Table,
  (fields,input) => input._assignments(fields),
  (fields,input) => input._assignments(fields)) { db.registerSchema(appSchema); }
late final ${entity.symbol}Creator create = _${entity.symbol}Creator(this);
''');
    if (entity.primaryKey.isNotEmpty) {
      final positional = entity.primaryKey.length == 1;
      final params = entity.primaryKey
          .map(
            (k) => '${positional ? '' : 'required '}${entity.field(k).type} $k',
          )
          .join(', ');
      var input = 'row';
      for (
        var suffix = 2;
        entity.fields.any((f) => f.name == input);
        suffix++
      ) {
        input = 'row$suffix';
      }
      final terms = entity.primaryKey
          .map((k) => '$input.$k.eq(.value($k))')
          .toList();
      final predicate = positional
          ? terms.single
          : '$groupsPrefix.allOf([${terms.join(', ')}])';
      final where = entity.primaryKey.contains('where')
          ? 'this.where'
          : 'where';
      b.writeln(
        '$modelPrefix.ModelQuery<${entity.rowType}, ${entity.fieldsType}, ${entity.symbol}Patch> byId(${positional ? params : '{$params}'}) => $where(($input) => $predicate);',
      );
    }
    b.writeln('}');
  }
  for (final projection in projections) {
    _emitProjection(b, projection, projectionPrefix);
  }
  b.writeln(
    'final appSchema = List<TableSchema>.unmodifiable([${schema.map((e) => '${e.binding}Schema').join(', ')}]);',
  );
  if (schema.isNotEmpty) {
    b.writeln('extension AppTables on QueryContext {');
    for (final e in schema) {
      b.writeln('${e.setType} get ${e.name} => ${e.setType}(this);');
    }
    b.writeln('}');
  }
  return b.toString();
}

void _emitCreator(StringBuffer b, ModelEntity entity) {
  final values = entity.fields.where((f) => f.computed == null).toList();
  bool requiredValue(ModelField f) =>
      !f.nullable &&
      !f.generated &&
      f.defaultSql == null &&
      f.clientDefault == null;
  String named(Iterable<String> parameters) {
    final values = parameters.toList();
    return values.isEmpty ? '' : '{${values.join(', ')}}';
  }

  b.writeln('''
/// Creates a complete ${entity.rowType} from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class ${entity.symbol}Creator {
Future<${entity.rowType}> call(${named(values.map((f) => '${requiredValue(f) ? 'required ' : ''}${f.type} ${f.name}'))});
}
final class _${entity.symbol}Creator implements ${entity.symbol}Creator {
final ${entity.setType} _table;
const _${entity.symbol}Creator(this._table);
@override
Future<${entity.rowType}> call(${named(values.map((f) => requiredValue(f) ? 'required ${f.type} ${f.name}' : 'Object? ${f.name} = _writeAbsent'))}) async =>
_table.plan.insert(${entity.symbol}Insert._(
${values.map((f) => '${f.name}: ${requiredValue(f) ? '.set(${f.name})' : '_writeLiteral<${f.type}, ${entity.fieldsType}>(${f.name})'},').join('\n')}
)).row();
}
''');
}

void _emitPatcher(StringBuffer b, ModelEntity entity, String modelPrefix) {
  final fields = entity.fields
      .where((f) => f.computed == null && !f.generated)
      .toList();
  String named(Iterable<String> parameters) =>
      parameters.isEmpty ? '' : '{${parameters.join(', ')}}';
  final query =
      '$modelPrefix.ModelQuery<${entity.rowType}, ${entity.fieldsType}, ${entity.symbol}Patch>';
  b.writeln('''
/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class ${entity.symbol}Patcher {
Future<int> call(${named(fields.map((f) => '${f.type} ${f.name}'))});
}
final class _${entity.symbol}Patcher implements ${entity.symbol}Patcher {
final $query _query;
const _${entity.symbol}Patcher(this._query);
@override
Future<int> call(${named(fields.map((f) => 'Object? ${f.name} = _writeAbsent'))}) =>
_query.update(${entity.symbol}Patch._(
${fields.map((f) => '${f.name}: _writeLiteral<${f.type}, ${entity.fieldsType}>(${f.name}),').join('\n')}
));
}
/// Named literal updates on a complete ${entity.rowType} query.
extension ${entity.symbol}Writes on $query {
/// Executes one update; omitted fields remain unchanged.
${entity.symbol}Patcher get patch => _${entity.symbol}Patcher(this);
}
''');
}

void _emitProjection(
  StringBuffer b,
  ModelProjection projection,
  String prefix,
) {
  for (final member in projection.members) {
    b.writeln(
      'final ${projection.slot(member)} = $prefix.Slot<${member.type}>(${dartLiteral(member.name)});',
    );
  }
  b.writeln('''
final class ${projection.fieldsType} extends $prefix.ProjectionOutput {
${projection.fieldsType}._($prefix.ProjectionFields fields) :
${projection.members.map((m) => '${m.name} = fields.read(${projection.slot(m)})').join(', ')},
super(fields.table);
${projection.members.map((m) => 'final Expr<${m.type}> ${m.name};').join('\n')}
}
''');
  final args = projection.members.indexed
      .map((e) => '${e.$2.name}: values[${e.$1}] as ${e.$2.type}')
      .join(', ');
  final assemble = projection.record
      ? '($args,)'
      : '${projection.rowType}($args)';
  b.writeln('''
final ${projection.descriptor} = $prefix.ProjectionType<${projection.rowType}, ${projection.fieldsType}>(
  slots: [${projection.members.map(projection.slot).join(', ')}],
  assemble: (values) => $assemble,
  fields: ${projection.fieldsType}._,
);
const ${projection.binding} = _${projection.symbol}SelectionFactory();
/// Named result binding; .sql explicitly requires scalar SQL expressions.
final class _${projection.symbol}SelectionFactory {
  const _${projection.symbol}SelectionFactory();
  Selection<${projection.rowType}> call({
    ${projection.members.map((m) => 'required Selection<${m.type}> ${m.name}').join(', ')}
  }) => ${_resultSelection(projection)};
  $prefix.Projection<${projection.rowType}, ${projection.fieldsType}> sql({
    ${projection.members.map((m) => 'required Expr<${m.type}> ${m.name}').join(', ')}
  }) => ${projection.descriptor}.bind([
    ${projection.members.map((m) => '${projection.slot(m)}.bind(${m.name}),').join('\n')}
  ]);
}
''');
}

String _resultSelection(ModelProjection projection) {
  String grouped(List<ProjectionMember> members) {
    if (members.length <= 6) {
      final source = members.length == 1
          ? members.single.name
          : '(${members.map((m) => m.name).join(', ')})';
      final args = List.generate(members.length, (i) => 'v$i').join(', ');
      final record = members.indexed
          .map((e) => '${e.$2.name}: v${e.$1}')
          .join(', ');
      return '$source.map(($args) => ($record,))';
    }
    final left = members.take(5).toList(), right = members.skip(5).toList();
    final names = left.map((m) => m.name).toSet();
    final record = members
        .map(
          (m) =>
              '${m.name}: ${names.contains(m.name) ? 'left' : 'right'}.${m.name}',
        )
        .join(', ');
    return '(${grouped(left)}, ${grouped(right)}).map((left, right) => ($record,))';
  }

  final args = projection.members
      .map((m) => '${m.name}: result.${m.name}')
      .join(', ');
  final result = projection.record
      ? '($args,)'
      : '${projection.rowType}($args)';
  return '${grouped(projection.members)}.map((result) => $result)';
}

void _emitWriteInputs(StringBuffer b, ModelEntity entity) {
  final insertFields = entity.fields.where((f) => f.computed == null).toList();
  final patchFields = insertFields.where((f) => !f.generated).toList();
  final patch = '${entity.symbol}Patch',
      insert = '${entity.symbol}Insert',
      fields = entity.fieldsType;
  String intent(ModelField f) => 'WriteValue<${f.type}, $fields>';
  String named(Iterable<String> p) => p.isEmpty ? '' : '{${p.join(', ')}}';
  bool requiredInsert(ModelField f) =>
      !f.nullable &&
      !f.generated &&
      f.defaultSql == null &&
      f.clientDefault == null;
  void emit(
    String result,
    String function,
    List<ModelField> values,
    bool inserting,
  ) {
    final type = '${result}Factory';
    final validatesRequired = inserting && values.any(requiredInsert);
    final params = named(
      values.map(
        (f) =>
            '${inserting && requiredInsert(f) ? 'required ' : ''}${f.type} ${f.name}',
      ),
    );
    final valueParams = named(
      values.map(
        (f) =>
            '${inserting && requiredInsert(f) ? 'required ' : ''}${intent(f)} ${f.name}${inserting && requiredInsert(f) ? '' : ' = const .keep()'}',
      ),
    );
    b.writeln('''
/// Immutable input data; composition belongs to [$function], not field names.
final class $result {
${values.map((f) => 'final ${intent(f)} ${f.name};').join('\n')}
$result._(${named(values.map((f) => 'required this.${f.name}'))})${validatesRequired ? ' {' : ';'}
''');
    if (validatesRequired) {
      for (final f in values.where(requiredInsert)) {
        b.writeln(
          "if (${f.name}.isMissing) { throw ArgumentError.value(${f.name}, '${f.name}', 'Must be supplied.'); }",
        );
      }
      b.writeln('}');
    }
    b.writeln('''
List<Assignment> _assignments($fields fields) => [
${values.map((f) => '...fields.${f.name}.write(${f.name == 'fields' ? 'this.' : ''}${f.name}, fields),').join('\n')}
];
}
/// Literal and intent input construction share the same immutable representation.
abstract interface class $type {
$result call($params);
$result values($valueParams);
$result overlay(${inserting ? '$result earlier, ' : ''}Iterable<$patch> layers);
${inserting ? '' : 'bool isEmpty($result input);'}
}
const $type $function = _$type();
final class _$type implements $type {
const _$type();
@override
$result call(${named(values.map((f) => inserting && requiredInsert(f) ? 'required ${f.type} ${f.name}' : 'Object? ${f.name} = _writeAbsent'))}) => $result._(
${values.map((f) => '${f.name}: ${inserting && requiredInsert(f) ? '.set(${f.name})' : '_writeLiteral<${f.type}, $fields>(${f.name})'},').join('\n')}
);
@override
$result values($valueParams) => $result._(${values.map((f) => '${f.name}: ${f.name}').join(', ')});
@override
$result overlay(${inserting ? '$result earlier, ' : ''}Iterable<$patch> layers) {
${inserting ? '' : 'var earlier = call();'}
for (final ${values.any((f) => !f.generated) ? 'later' : '_'} in layers) {
earlier = $result._(
${values.map((f) => '${f.name}: ${f.generated ? 'earlier.${f.name}' : 'WriteValue.overlay(earlier.${f.name}, later.${f.name})'},').join('\n')}
);
}
return earlier;
}
${inserting ? '' : '@override\nbool isEmpty($result input) => ${values.isEmpty ? 'true' : values.map((f) => 'input.${f.name}.isMissing').join(' && ')};'}
}
''');
  }

  emit(patch, '${entity.binding}Patch', patchFields, false);
  emit(insert, '${entity.binding}Insert', insertFields, true);
}

String modelSelection(ModelEntity entity, String row) {
  String construct(String Function(ModelField) value) =>
      '${entity.rowType}(${entity.fields.map((f) => '${f.name}: ${value(f)}').join(', ')})';
  final fields = entity.fields;
  if (fields.length == 1) {
    return '$row.${fields.single.name}.map((value) => ${construct((_) => 'value')})';
  }
  if (fields.length <= 6) {
    return '(${fields.map((f) => '$row.${f.name}').join(', ')})'
        '.map((${List.generate(fields.length, (i) => 'v$i').join(', ')}) => '
        '${construct((f) => 'v${fields.indexOf(f)}')})';
  }
  final left = fields.take(5).toList(), right = fields.skip(5).toList();
  final leftNames = left.map((f) => f.name).toSet();
  return '(${recordSelection(left, row)}, ${recordSelection(right, row)})'
      '.map((left, right) => '
      '${construct((f) => '${leftNames.contains(f.name) ? 'left' : 'right'}.${f.name}')})';
}

String recordSelection(List<ModelField> fields, String row) {
  if (fields.length == 1) {
    final f = fields.single;
    return '$row.${f.name}.map((v) => (${f.name}: v,))';
  }
  if (fields.length <= 6) {
    return '(${fields.map((f) => '$row.${f.name}').join(', ')})'
        '.map((${fields.map((f) => f.name).join(', ')}) => '
        '(${fields.map((f) => '${f.name}: ${f.name}').join(', ')}))';
  }
  // Nested typed composition avoids a combinatorial number of arity helpers.
  final left = fields.take(5).toList(), right = fields.skip(5).toList();
  return '(${recordSelection(left, row)}, ${recordSelection(right, row)})'
      '.map((left, right) => (${[...left.map((f) => '${f.name}: left.${f.name}'), ...right.map((f) => '${f.name}: right.${f.name}')].join(', ')}))';
}

String _computedLiteral(ComputedColumn value) =>
    'ComputedColumn.forDialects(sqlite: ${dartLiteral(value.sqlite)}, postgres: ${dartLiteral(value.postgres)}, mysql: ${value.mysql == null ? 'null' : dartLiteral(value.mysql!)}, mariadb: ${value.mariadb == null ? 'null' : dartLiteral(value.mariadb!)}, storage: ComputedStorage.${value.storage.name})';
