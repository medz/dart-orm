import '../../schema_model.dart';
import 'model.dart';
import 'source.dart';
import 'types.dart';

String emitSchema(List<ModelEntity> schema, String import, DartNames names) {
  final b = StringBuffer('// GENERATED CODE - DO NOT MODIFY BY HAND.\n\n')
    ..writeln("import 'package:orm/sql.dart';")
    ..writeln("import ${dartLiteral(import)} as models;")
    ..writeln(
      "export ${dartLiteral(import)} show ${schema.map((e) => e.row).toSet().join(', ')};",
    );
  if (names.typedData) {
    b.writeln("import 'dart:typed_data';");
  }
  for (final (uri, prefix) in names.imports) {
    b.writeln('import ${dartLiteral(uri)} as $prefix;');
  }
  b.writeln('');
  for (final entity in schema) {
    for (final f in entity.fields) {
      b.writeln(
        'final ${columnSymbol(entity, f)} = Column<${f.type}>(${dartLiteral(f.column)}, ${f.codec}, '
        'nullable: ${f.nullable}, generated: ${f.generated}${f.defaultSql == null ? '' : ', defaultSql: ${dartLiteral(f.defaultSql!)}'}${f.clientDefault == null ? '' : ', clientDefault: ${f.clientDefault}'}${f.computed == null ? '' : ', computed: ${_computedLiteral(f.computed!)}'}${f.integerBits == null || f.integerBits == 64 ? '' : ', integerBits: ${f.integerBits}'}${f.temporalPrecision == null || f.temporalPrecision == 6 ? '' : ', temporalPrecision: ${f.temporalPrecision}'}${f.decimalPrecision == null ? '' : ', decimalPrecision: ${f.decimalPrecision}'}${f.decimalScale == null || f.decimalScale == 0 ? '' : ', decimalScale: ${f.decimalScale}'});',
      );
    }
    b.writeln(
      'final ${entity.name}Schema = TableSchema(${dartLiteral(entity.table)}, '
      'columns: [${entity.fields.map((f) => columnSymbol(entity, f)).join(', ')}], '
      'primaryKey: ${dartStringList(entity.columns(entity.primaryKey))}, '
      'uniqueKeys: [${entity.uniqueKeys.map((k) => dartStringList(entity.columns(k))).join(', ')}], '
      'indexes: [${entity.indexes.map((i) => 'IndexSchema(${dartLiteral(i.name)}, ${dartStringList(entity.columns(i.keys))}, unique: ${i.unique})').join(', ')}], '
      '${entity.checks.isEmpty ? '' : 'checks: [${entity.checks.map((c) => 'CheckSchema.forDialects(${c.name == null ? 'null' : dartLiteral(c.name!)}, sqlite: ${dartLiteral(c.sqlite)}, postgres: ${dartLiteral(c.postgres)}, mysql: ${c.mysql == null ? 'null' : dartLiteral(c.mysql!)}, mariadb: ${c.mariadb == null ? 'null' : dartLiteral(c.mariadb!)})').join(', ')}], '}'
      'foreignKeys: [${entity.edges.where((e) => e.isForeignKey).map((e) => 'ForeignKey(${dartStringList(entity.columns(e.parentKeys))}, ${dartLiteral(e.target.table)}, ${dartStringList(e.target.columns(e.childKeys))}, onDelete: ${dartLiteral(e.onDelete!)})').join(', ')}]);',
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
        'Relation(${edge.target.name}Table, parent: [${edge.parentKeys.join(', ')}], '
        'child: (row) => [${edge.childKeys.map((k) => 'row.$k').join(', ')}]);',
      );
    }
    b.writeln('}');
    final selection = _modelSelection(entity, 'row');
    b.writeln(
      'final ${entity.name}Table = Table<${entity.rowType}, ${entity.fieldsType}>('
      '${entity.name}Schema, ${entity.fieldsType}.new, (row) => $selection);',
    );
    b.writeln(
      'final class ${entity.setType} extends TableSet<${entity.rowType}, ${entity.fieldsType}> {'
      '${entity.setType}(QueryContext db) : super(db, ${entity.name}Table) { db.registerSchema(appSchema); }',
    );
    final parameters = <String>[];
    final assignments = <String>[];
    for (final f in entity.fields) {
      if (f.computed != null) continue;
      if (f.generated || f.defaultSql != null || f.clientDefault != null) {
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
    if (entity.fields.any((f) => !f.generated && f.computed == null)) {
      b.writeln(
        'extension ${entity.symbol}Updates on Query<${entity.rowType}, ${entity.fieldsType}> {'
        'Future<int> patch({${entity.fields.where((f) => !f.generated && f.computed == null).map((f) => 'Change<${f.type}> ${f.name} = const Change.keep()').join(', ')}}) => '
        'update((row) => [${entity.fields.where((f) => !f.generated && f.computed == null).map((f) => '...row.${f.name}.change(${f.name})').join(', ')}]).execute(); }',
      );
    }
  }
  b.writeln(
    'final appSchema = List<TableSchema>.unmodifiable([${schema.map((e) => '${e.name}Schema').join(', ')}]);',
  );
  b.writeln('extension AppTables on QueryContext {');
  for (final e in schema) {
    b.writeln('${e.setType} get ${e.name} => ${e.setType}(this);');
  }
  b.writeln('}');
  return b.toString();
}

String _modelSelection(ModelEntity entity, String row) {
  final named = entity.constructorNamedFields;
  if (named == null) return recordSelection(entity.fields, row);
  String construct(String Function(ModelField) value) =>
      '${entity.rowType}(${entity.fields.map((f) => '${named.contains(f.name) ? '${f.name}: ' : ''}${value(f)}').join(', ')})';
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
