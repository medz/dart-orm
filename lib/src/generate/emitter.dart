import '../../schema_model.dart';
import 'model.dart';
import 'source.dart';
import 'types.dart';

String emitSchema(List<ModelEntity> schema, String import, DartNames names) {
  final b = StringBuffer('// GENERATED CODE - DO NOT MODIFY BY HAND.\n\n')
    ..writeln("import 'package:orm/sql.dart';");
  if (names.usesSource) {
    b.writeln("import ${dartLiteral(import)} as models;");
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
  b.writeln('');
  for (final entity in schema) {
    b.writeln(
      '/// A complete immutable row from ${dartLiteral(entity.table)}.',
    );
    b.writeln(rowDeclaration(entity));
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
    b.writeln(
      'final class ${entity.setType} extends TableSet<${entity.rowType}, ${entity.fieldsType}> {'
      '${entity.setType}(QueryContext db) : super(db, ${entity.binding}Table) { db.registerSchema(appSchema); }',
    );
    var input = 'row';
    final create =
        entity.fields.any((f) => f.computed == null && f.name == 'createRow')
        ? 'this.createRow'
        : 'createRow';
    final where = entity.primaryKey.contains('where') ? 'this.where' : 'where';
    final update =
        entity.fields.any(
          (f) => !f.generated && f.computed == null && f.name == 'update',
        )
        ? 'this.update'
        : 'update';
    for (var suffix = 2; entity.fields.any((f) => f.name == input); suffix++) {
      input = 'row$suffix';
    }
    final parameters = <String>[];
    final assignments = <String>[];
    for (final f in entity.fields) {
      if (f.computed != null) continue;
      if (f.generated || f.defaultSql != null || f.clientDefault != null) {
        parameters.add('Change<${f.type}> ${f.name} = const Change.keep()');
        assignments.add('...$input.${f.name}.change(${f.name})');
      } else if (f.nullable) {
        parameters.add('${f.type} ${f.name}');
        assignments.add('$input.${f.name}.set(${f.name})');
      } else {
        parameters.add('required ${f.type} ${f.name}');
        assignments.add('$input.${f.name}.set(${f.name})');
      }
    }
    b.writeln(
      'Future<${entity.rowType}> create({${parameters.join(', ')}}) => $create(($input) => [${assignments.join(', ')}]);',
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
        '$where(($input) => ${entity.primaryKey.map((k) => '$input.$k.eq($k)').join('.and(')}${')' * (entity.primaryKey.length - 1)});',
      );
    }
    b.writeln('}');
    if (entity.fields.any((f) => !f.generated && f.computed == null)) {
      b.writeln(
        'extension ${entity.symbol}Updates on Query<${entity.rowType}, ${entity.fieldsType}> {'
        'Future<int> patch({${entity.fields.where((f) => !f.generated && f.computed == null).map((f) => 'Change<${f.type}> ${f.name} = const Change.keep()').join(', ')}}) => '
        '$update(($input) => [${entity.fields.where((f) => !f.generated && f.computed == null).map((f) => '...$input.${f.name}.change(${f.name})').join(', ')}]).execute(); }',
      );
    }
  }
  b.writeln(
    'final appSchema = List<TableSchema>.unmodifiable([${schema.map((e) => '${e.binding}Schema').join(', ')}]);',
  );
  if (schema.first.grouped) {
    final namespaces = schema.map((e) => e.namespace!).toSet().toList()..sort();
    for (final namespace in namespaces) {
      final type =
          '${namespace[0].toUpperCase()}${namespace.substring(1)}Tables';
      b.writeln(
        'final class $type { final QueryContext _context; $type(this._context);',
      );
      for (final e in schema.where((e) => e.namespace == namespace)) {
        b.writeln('${e.setType} get ${e.name} => ${e.setType}(_context);');
      }
      b.writeln('}');
    }
    b.writeln('extension AppTables on QueryContext {');
    for (final namespace in namespaces) {
      final type =
          '${namespace[0].toUpperCase()}${namespace.substring(1)}Tables';
      b.writeln('$type get $namespace => $type(this);');
    }
    b.writeln('}');
  } else {
    b.writeln('extension AppTables on QueryContext {');
    for (final e in schema) {
      b.writeln('${e.setType} get ${e.name} => ${e.setType}(this);');
    }
    b.writeln('}');
  }
  return b.toString();
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

String rowDeclaration(ModelEntity entity) =>
    'final class ${entity.row}({${entity.fields.map((f) => 'required final ${f.type} ${f.name}').join(', ')}});';
