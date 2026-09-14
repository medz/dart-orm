part of '../../generate.dart';

String _emit(List<_Entity> schema, String import, _DartNames names) {
  final b = StringBuffer('// GENERATED CODE - DO NOT MODIFY BY HAND.\n\n')
    ..writeln("import 'package:orm/orm.dart';")
    ..writeln("import ${_literal(import)} as models;");
  if (names.typedData) {
    b.writeln("import 'dart:typed_data';");
  }
  for (final (uri, prefix) in names.imports) {
    b.writeln('import ${_literal(uri)} as $prefix;');
  }
  b.writeln('');
  for (final entity in schema) {
    for (final f in entity.fields) {
      b.writeln(
        'final ${_columnSymbol(entity, f)} = Column<${f.type}>(${_literal(f.column)}, ${f.codec}, '
        'nullable: ${f.nullable}, generated: ${f.generated}${f.defaultSql == null ? '' : ', defaultSql: ${_literal(f.defaultSql!)}'});',
      );
    }
    b.writeln(
      'final ${entity.name}Schema = TableSchema(${_literal(entity.table)}, '
      'columns: [${entity.fields.map((f) => _columnSymbol(entity, f)).join(', ')}], '
      'primaryKey: ${_strings(entity.columns(entity.primaryKey))}, '
      'uniqueKeys: [${entity.uniqueKeys.map((k) => _strings(entity.columns(k))).join(', ')}], '
      'indexes: [${entity.indexes.map((i) => 'IndexSchema(${_literal(i.name)}, ${_strings(entity.columns(i.keys))}, unique: ${i.unique})').join(', ')}], '
      'foreignKeys: [${entity.edges.where((e) => !e.inverse).map((e) => 'ForeignKey(${_strings(entity.columns(e.parentKeys))}, ${_literal(e.target.table)}, ${_strings(e.target.columns(e.childKeys))}, onDelete: ${_literal(e.onDelete)})').join(', ')}]);',
    );
    b.writeln(
      'final class ${entity.fieldsType} extends Fields {\n ${entity.fieldsType}(super.table);',
    );
    for (final f in entity.fields) {
      b.writeln('late final ${f.name} = column(${_columnSymbol(entity, f)});');
    }
    for (final edge in entity.edges) {
      b.writeln(
        'Relation<${edge.target.rowType}, ${edge.target.fieldsType}> get ${edge.name} => '
        'Relation(${edge.target.name}Table, parent: [${edge.parentKeys.join(', ')}], '
        'child: (row) => [${edge.childKeys.map((k) => 'row.$k').join(', ')}]);',
      );
    }
    b.writeln('}');
    final selection = _recordSelection(entity.fields, 'row');
    b.writeln(
      'final ${entity.name}Table = Table<${entity.rowType}, ${entity.fieldsType}>('
      '${entity.name}Schema, ${entity.fieldsType}.new, (row) => $selection);',
    );
    b.writeln(
      'final class ${entity.setType} extends TableSet<${entity.rowType}, ${entity.fieldsType}> {'
      '${entity.setType}(Database<Backend> db) : super(db, ${entity.name}Table);',
    );
    final parameters = <String>[];
    final assignments = <String>[];
    for (final f in entity.fields) {
      if (f.generated || f.defaultSql != null) {
        parameters.add('Change<${f.type}> ${f.name} = const Change.keep()');
        assignments.add('...row.${f.name}.change(${f.name})');
      } else if (f.nullable) {
        parameters.add('${f.type} ${f.name}');
        assignments.add('row.${f.name}.set(${f.name})');
      } else {
        parameters.add('required ${f.type} ${f.name}');
        assignments.add('row.${f.name}.set(${f.name})');
      }
    }
    b.writeln(
      'Future<${entity.rowType}> create({${parameters.join(', ')}}) => createRow((row) => [${assignments.join(', ')}]);',
    );
    if (entity.primaryKey.isNotEmpty) {
      final positional = entity.primaryKey.length == 1;
      final params = entity.primaryKey
          .map(
            (k) => '${positional ? '' : 'required '}${entity.field(k).type} $k',
          )
          .join(', ');
      b.writeln(
        'Query<${entity.rowType}, ${entity.fieldsType}> byId(${positional ? params : '{$params}'}) => '
        'where((row) => ${entity.primaryKey.map((k) => 'row.$k.eq($k)').join('.and(')}${')' * (entity.primaryKey.length - 1)});',
      );
    }
    b.writeln('}');
    b.writeln(
      'extension ${entity.symbol}Updates on Query<${entity.rowType}, ${entity.fieldsType}> {'
      'Future<int> patch({${entity.fields.where((f) => !f.generated).map((f) => 'Change<${f.type}> ${f.name} = const Change.keep()').join(', ')}}) => '
      'update((row) => [${entity.fields.where((f) => !f.generated).map((f) => '...row.${f.name}.change(${f.name})').join(', ')}]).execute(); }',
    );
  }
  b.writeln(
    'final appSchema = <TableSchema>[${schema.map((e) => '${e.name}Schema').join(', ')}];',
  );
  b.writeln('extension AppTables<B extends Backend> on Database<B> {');
  for (final e in schema) {
    b.writeln('${e.setType} get ${e.name} => ${e.setType}(this);');
  }
  b.writeln('}');
  return b.toString();
}

String _recordSelection(List<_Field> fields, String row) {
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
  return '(${_recordSelection(left, row)}, ${_recordSelection(right, row)})'
      '.map((left, right) => (${[...left.map((f) => '${f.name}: left.${f.name}'), ...right.map((f) => '${f.name}: right.${f.name}')].join(', ')}))';
}
