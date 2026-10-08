import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:orm/database.dart' show Engine;
import 'package:orm/schema.dart';
import 'package:path/path.dart' as p;

import 'model.dart';

String _physicalIdentity(Engine engine, String name) => engine == Engine.sqlite
    ? String.fromCharCodes(
        name.codeUnits.map(
          (unit) => unit >= 65 && unit <= 90 ? unit + 32 : unit,
        ),
      )
    : name;

Future<SchemaModel> readSchema(String file, {required Engine engine}) async {
  final collection = AnalysisContextCollection(
    includedPaths: [file],
    sdkPath: p.dirname(p.dirname(Platform.resolvedExecutable)),
  );
  try {
    final result = await collection
        .contextFor(file)
        .currentSession
        .getResolvedLibrary(file);
    if (result is! ResolvedLibraryResult) {
      throw FormatException('Cannot resolve schema $file: $result');
    }
    final errors = result.units
        .expand((unit) => unit.diagnostics)
        .where((error) => error.severity.name == 'error');
    if (errors.isNotEmpty) {
      throw FormatException(
        'Schema analysis failed:\n${errors.map((error) => error.toString()).join('\n')}',
      );
    }
    if (result.units.length != 1) {
      throw const FormatException(
        'Schema must be one independent library; part directives are unsupported.',
      );
    }
    final tables = <TableModel>[];
    final rowTypes = <ClassElement, TableModel>{};
    for (final element in result.element.classes) {
      final annotation = _annotation(element, 'Table');
      if (annotation == null) continue;
      final name = annotation.getField('name')?.toStringValue();
      if (name == null || name.isEmpty || name.contains('\u0000')) {
        throw FormatException(
          '${element.name}: Table needs a nonempty physical name.',
        );
      }
      if (element.name == null ||
          element.name!.startsWith('_') ||
          element.typeParameters.isNotEmpty ||
          element.isAbstract ||
          !element.isConstructable) {
        throw FormatException(
          '$name: table row must be a public, concrete, nongeneric class.',
        );
      }
      if (element.supertype?.element.name != 'Object' ||
          element.mixins.isNotEmpty) {
        throw FormatException(
          '$name: row classes cannot inherit fields or use mixins.',
        );
      }
      final constructor = element.unnamedConstructor;
      if (constructor == null || constructor.isFactory) {
        throw FormatException(
          '$name: provide an unnamed generative constructor.',
        );
      }
      final fields = <FieldModel>[];
      for (final field in element.fields.where(
        (field) => !field.isStatic && !field.isOriginGetterSetter,
      )) {
        if (!field.isFinal ||
            field.name == null ||
            field.name!.startsWith('_')) {
          throw FormatException('$name: row fields must be public and final.');
        }
        final type = field.type;
        final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
        final scalar = _scalar(type, '$name.${field.name}');
        final column = _annotation(field, 'Column');
        final primary = _annotation(field, 'PrimaryKey');
        final reference = _annotation(field, 'References');
        final identity =
            primary?.getField('autoIncrement')?.toBoolValue() ?? false;
        if (primary != null && nullable) {
          throw FormatException(
            '$name.${field.name}: primary keys cannot be nullable.',
          );
        }
        if (identity && scalar != ScalarType.integer) {
          throw FormatException(
            '$name.${field.name}: autoIncrement requires int.',
          );
        }
        final sqlName =
            column?.getField('name')?.toStringValue() ?? field.name!;
        if (sqlName.isEmpty || sqlName.contains('\u0000')) {
          throw FormatException(
            '$name.${field.name}: column name cannot be empty.',
          );
        }
        final defaultValue = _defaultValue(
          column?.getField('defaultValue'),
          scalar,
          '$name.${field.name}',
        );
        if (identity && defaultValue != null) {
          throw FormatException(
            '$name.${field.name}: identity columns cannot have a default.',
          );
        }
        final onDelete =
            reference?.getField('onDelete')?.toStringValue() ?? 'restrict';
        if (!{
          'restrict',
          'cascade',
          'set null',
          'no action',
        }.contains(onDelete)) {
          throw FormatException(
            '$name.${field.name}: unsupported onDelete $onDelete.',
          );
        }
        if (reference != null && onDelete == 'set null' && !nullable) {
          throw FormatException(
            '$name.${field.name}: SET NULL needs a nullable field.',
          );
        }
        fields.add(
          FieldModel(
            type.getDisplayString(),
            ColumnDefinition(
              name: sqlName,
              field: field.name!,
              type: scalar,
              nullable: nullable,
              primaryKey: primary != null,
              identity: identity,
              unique: _annotation(field, 'Unique') != null,
              defaultValue: defaultValue,
              references: reference == null
                  ? null
                  : ForeignKey(
                      reference.getField('table')!.toStringValue()!,
                      reference.getField('column')!.toStringValue()!,
                      onDelete: onDelete,
                    ),
            ),
          ),
        );
      }
      if (fields.isEmpty ||
          fields.where((field) => field.column.primaryKey).length != 1) {
        throw FormatException('$name: exactly one primary key is required.');
      }
      if (fields.map((field) => field.column.name).toSet().length !=
          fields.length) {
        throw FormatException('$name: duplicate physical column names.');
      }
      final parameters = constructor.formalParameters;
      if (parameters.length != fields.length ||
          parameters.any(
            (parameter) => !fields.any(
              (field) =>
                  field.name == parameter.name &&
                  field.type == parameter.type.getDisplayString(),
            ),
          )) {
        throw FormatException(
          '$name: constructor parameters must match every row field by name and exact type.',
        );
      }
      final declaration = result.units.single.unit.declarations
          .whereType<ClassDeclaration>()
          .singleWhere((node) => node.declaredFragment?.element == element);
      _validateConstructor(name, declaration, constructor);
      final table = TableModel(name, element.name!, fields, [
        for (final parameter in parameters)
          ConstructorParameter(parameter.name!, named: parameter.isNamed),
      ]);
      tables.add(table);
      rowTypes[element] = table;
    }
    if (tables.isEmpty) {
      throw const FormatException('Schema contains no @Table declarations.');
    }
    if (tables.map((table) => table.name).toSet().length != tables.length ||
        tables.map((table) => table.getterName).toSet().length !=
            tables.length) {
      throw const FormatException(
        'Duplicate table identity or generated table getter.',
      );
    }
    const reserved = {
      'transaction',
      'close',
      'database',
      'session',
      'engine',
      'capabilities',
      'inTransaction',
      'run',
      'hashCode',
      'runtimeType',
      'toString',
      'noSuchMethod',
    };
    for (final table in tables) {
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$').hasMatch(table.getterName) ||
          (Keyword.keywords[table.getterName]?.isReservedWord ?? false) ||
          reserved.contains(table.getterName)) {
        throw FormatException(
          '${table.name}: physical table name does not produce a valid table getter.',
        );
      }
      for (final field in table.fields) {
        final reference = field.column.references;
        if (reference == null) continue;
        final targets = tables.where(
          (target) =>
              _physicalIdentity(engine, target.name) ==
              _physicalIdentity(engine, reference.table),
        );
        if (targets.length != 1) {
          throw FormatException(
            '${table.name}.${field.name}: referenced table ${reference.table} is missing.',
          );
        }
        final columns = targets.single.fields.where(
          (target) =>
              _physicalIdentity(engine, target.column.name) ==
              _physicalIdentity(engine, reference.column),
        );
        if (columns.length != 1 ||
            !(columns.single.column.primaryKey ||
                columns.single.column.unique) ||
            columns.single.column.type != field.column.type) {
          throw FormatException(
            '${table.name}.${field.name}: reference requires an existing unique column with the same scalar type.',
          );
        }
      }
    }
    final selections = <SelectionModel>[];
    for (final alias in result.element.typeAliases) {
      final annotation = _annotation(alias, 'SelectFrom');
      if (annotation == null) continue;
      final target = annotation.getField('rowType')?.toTypeValue()?.element;
      final table = rowTypes[target];
      if (table == null ||
          alias.typeParameters.isNotEmpty ||
          alias.name == null ||
          alias.name!.startsWith('_')) {
        throw FormatException(
          '${alias.name}: SelectFrom requires a declared row type and a public nongeneric typedef.',
        );
      }
      final type = alias.aliasedType;
      if (type is! RecordType ||
          type.positionalFields.isNotEmpty ||
          type.namedFields.isEmpty ||
          type.nullabilitySuffix != NullabilitySuffix.none) {
        throw FormatException(
          '${alias.name}: selections must be nonnullable records with named fields.',
        );
      }
      final fields = <FieldModel>[];
      for (final selected in type.namedFields) {
        final matching = table.fields.where(
          (field) =>
              field.name == selected.name &&
              field.type == selected.type.getDisplayString(),
        );
        if (matching.length != 1) {
          throw FormatException(
            '${alias.name}.${selected.name}: selection must match a row field by name, type and nullability.',
          );
        }
        fields.add(matching.single);
      }
      final shape = fields
          .map((field) => '${field.name}:${field.type}')
          .join(',');
      selections.add(SelectionModel(alias.name!, table, fields, shape));
    }
    return SchemaModel(tables, selections);
  } finally {
    await collection.dispose();
  }
}

void _validateConstructor(
  String table,
  ClassDeclaration declaration,
  ConstructorElement constructor,
) {
  FunctionBody? body;
  Iterable<ConstructorInitializer> initializers;
  if (constructor.isPrimary) {
    final node = declaration.namePart as PrimaryConstructorDeclaration;
    body = node.body?.body;
    initializers = node.body?.initializers ?? const [];
  } else {
    final node = declaration.body.members
        .whereType<ConstructorDeclaration>()
        .singleWhere((node) => node.declaredFragment?.element == constructor);
    if (node.externalKeyword != null) {
      throw FormatException(
        '$table: external row constructors are unsupported.',
      );
    }
    body = node.body;
    initializers = node.initializers;
  }
  if (body != null &&
      body is! EmptyFunctionBody &&
      !(body is BlockFunctionBody && body.block.statements.isEmpty)) {
    throw FormatException(
      '$table: row constructors must assign fields directly without executing a body.',
    );
  }
  final assigned = <String>{};
  for (final parameter in constructor.formalParameters) {
    if (parameter is FieldFormalParameterElement) {
      if (parameter.field?.name != parameter.name) {
        throw FormatException(
          '$table: constructor parameter must initialize its own field.',
        );
      }
      assigned.add(parameter.name!);
    }
  }
  for (final initializer in initializers) {
    if (initializer is! ConstructorFieldInitializer) {
      throw FormatException(
        '$table: row constructors cannot contain assertions or other initializers.',
      );
    }
    Expression expression = initializer.expression;
    while (expression is ParenthesizedExpression) {
      expression = expression.expression;
    }
    final field = initializer.fieldName.name;
    if (expression is! SimpleIdentifier ||
        expression.element is! FormalParameterElement ||
        expression.element?.enclosingElement != constructor ||
        expression.element?.name != field ||
        !assigned.add(field)) {
      throw FormatException(
        '$table: each initializer must assign a field from its matching constructor parameter.',
      );
    }
  }
  if (assigned.length != constructor.formalParameters.length) {
    throw FormatException(
      '$table: constructor must directly initialize every row field.',
    );
  }
}

DartObject? _annotation(Element element, String name) {
  final values = element.metadata.annotations
      .map((annotation) => annotation.computeConstantValue())
      .whereType<DartObject>()
      .where(
        (value) =>
            value.type?.element?.name == name &&
            value.type?.element?.library?.uri.toString() ==
                'package:orm/src/schema/annotations.dart',
      )
      .toList();
  if (values.length > 1) {
    throw FormatException('${element.name}: duplicate @$name.');
  }
  return values.singleOrNull;
}

ScalarType _scalar(DartType type, String location) {
  if (type is! InterfaceType || type.typeArguments.isNotEmpty) {
    throw FormatException(
      '$location: unsupported type ${type.getDisplayString()}.',
    );
  }
  final library = type.element.library.uri.toString();
  final scalar = switch ((library, type.element.name)) {
    ('dart:core', 'int') => ScalarType.integer,
    ('dart:core', 'String') => ScalarType.text,
    ('dart:core', 'bool') => ScalarType.boolean,
    ('dart:core', 'double') => ScalarType.real,
    ('dart:core', 'DateTime') => ScalarType.dateTime,
    ('dart:typed_data', 'Uint8List') => ScalarType.bytes,
    _ => null,
  };
  if (scalar == null) {
    throw FormatException(
      '$location: unsupported type ${type.getDisplayString()}.',
    );
  }
  return scalar;
}

Object? _defaultValue(DartObject? value, ScalarType type, String location) {
  if (value == null || value.isNull) return null;
  final decoded = switch (type) {
    ScalarType.integer => value.toIntValue(),
    ScalarType.text => value.toStringValue(),
    ScalarType.boolean => value.toBoolValue(),
    ScalarType.real => value.toDoubleValue(),
    ScalarType.dateTime || ScalarType.bytes => null,
  };
  if (decoded == null || (decoded is double && !decoded.isFinite)) {
    throw FormatException(
      '$location: default must be a literal matching its scalar type.',
    );
  }
  return decoded;
}
