import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';

/// Experiment-only declaration normalization. Does not run constructors or
/// selectors, add production authoring APIs, or preserve class runtime behavior.
Future<AuthoringSource> normalizeAuthoring(String path, String form) async {
  path = File(path).absolute.path;
  final contexts = AnalysisContextCollection(includedPaths: [path]);
  try {
    final result = await contexts
        .contextFor(path)
        .currentSession
        .getResolvedUnit(path);
    if (result is! ResolvedUnitResult) throw StateError('Cannot resolve $path');
    final errors = result.diagnostics.where(
      (e) => e.severity.name.toLowerCase() == 'error',
    );
    if (errors.isNotEmpty) {
      final e = errors.first;
      throw AuthoringFailure(
        'dart',
        e.diagnosticCode.lowerCaseName,
        e.message,
        e.offset,
        e.length,
      );
    }
    final output = AuthoringSource(result.content);
    output.add("import 'package:orm/schema.dart';\n", 0);
    for (final declaration in result.unit.declarations) {
      if (declaration is TopLevelVariableDeclaration) continue;
      if (form == 'record' && declaration is GenericTypeAlias) {
        final type = declaration.type as RecordTypeAnnotation;
        output.add(
          'typedef ${declaration.name.lexeme} = ({\n',
          declaration.offset,
        );
        for (final field in type.namedFields!.fields) {
          output.field(
            field.name.lexeme,
            field.type.type!,
            field.metadata,
            field.name.offset,
          );
        }
        output.add('});\n', declaration.end - 1);
      } else if (form == 'primary' && declaration is ClassDeclaration) {
        final primary = declaration.namePart;
        if (primary is! PrimaryConstructorDeclaration ||
            declaration.body.members.isNotEmpty ||
            declaration.extendsClause != null ||
            declaration.implementsClause != null ||
            declaration.withClause != null ||
            primary.typeParameters != null ||
            primary.constructorName != null) {
          throw AuthoringFailure(
            'authoring',
            'unsupported_class',
            'Use an unmodified primary constructor with declaring fields only.',
            declaration.offset,
            declaration.length,
          );
        }
        output.add(
          'typedef ${primary.typeName.lexeme} = ({\n',
          declaration.offset,
        );
        for (final parameter in primary.formalParameters.parameters) {
          if (!parameter.isFinal ||
              parameter.defaultClause != null ||
              parameter.type == null ||
              parameter.name == null) {
            throw AuthoringFailure(
              'authoring',
              'unsupported_parameter',
              'Use typed final declaring parameters without constructor defaults.',
              parameter.offset,
              parameter.length,
            );
          }
          output.field(
            parameter.name!.lexeme,
            parameter.type!.type!,
            parameter.metadata,
            parameter.name!.offset,
          );
        }
        output.add('});\n', declaration.end - 1);
      } else if (form == 'table' && declaration is ClassDeclaration) {
        if (declaration.extendsClause?.superclass.name.lexeme != 'Fields' ||
            declaration.implementsClause != null ||
            declaration.withClause != null ||
            declaration.namePart.typeParameters != null) {
          throw AuthoringFailure(
            'authoring',
            'unsupported_table',
            'Use a Fields class with column members only.',
            declaration.offset,
            declaration.length,
          );
        }
        output.add(
          'typedef ${declaration.namePart.typeName.lexeme} = ({\n',
          declaration.offset,
        );
        for (final member in declaration.body.members) {
          if (member is ConstructorDeclaration &&
              member.toSource() ==
                  '${declaration.namePart.typeName.lexeme}(super.table);') {
            continue;
          }
          if (member is! FieldDeclaration ||
              !member.fields.isFinal ||
              member.fields.variables.length != 1) {
            throw AuthoringFailure(
              'authoring',
              'unsupported_member',
              'Use one final column field per declaration.',
              member.offset,
              member.length,
            );
          }
          final variable = member.fields.variables.single;
          final initializer = variable.initializer;
          final type = variable.declaredFragment!.element.type;
          if (initializer is! MethodInvocation ||
              initializer.methodName.name != 'column' ||
              initializer.argumentList.arguments.length != 1 ||
              type is! InterfaceType ||
              type.element.name != 'Field') {
            throw AuthoringFailure(
              'authoring',
              'unsupported_column',
              'Use column(Column(...)) with a statically resolved Field type.',
              variable.offset,
              variable.length,
            );
          }
          final column =
              initializer.argumentList.arguments.single.argumentExpression;
          if (column is! InstanceCreationExpression ||
              column.constructorName.type.name.lexeme != 'Column') {
            throw AuthoringFailure(
              'authoring',
              'unsupported_column',
              'Use a Column constructor.',
              initializer.offset,
              initializer.length,
            );
          }
          final args = column.argumentList.arguments;
          if (args.length < 2 ||
              args.first is! SimpleStringLiteral ||
              args
                  .skip(2)
                  .any(
                    (a) => a is! NamedArgument || a.name.lexeme != 'nullable',
                  )) {
            throw AuthoringFailure(
              'authoring',
              'unsupported_column_options',
              'Use literal physical names and annotations for schema metadata.',
              column.offset,
              column.length,
            );
          }
          final fieldType = type.typeArguments.single;
          final baseType = fieldType.getDisplayString().replaceAll('?', '');
          final codec = switch (baseType) {
            'int' => 'Codecs.integer',
            'String' => 'Codecs.text',
            'bool' => 'Codecs.boolean',
            'DateTime' => 'Codecs.dateTime',
            _ => '',
          };
          final nullable = fieldType.getDisplayString().endsWith('?');
          final codecSource = '$codec${nullable ? '.nullable()' : ''}';
          final nullableSource =
              args
                  .whereType<NamedArgument>()
                  .firstOrNull
                  ?.argumentExpression
                  .toSource() ??
              'false';
          if (codec.isEmpty ||
              args[1].toSource() != codecSource ||
              nullableSource != '$nullable') {
            throw AuthoringFailure(
              'authoring',
              'unsupported_codec',
              'Use the matching built-in codec and explicit SQL nullability; custom conversions cannot be discarded.',
              args[1].offset,
              args[1].length,
            );
          }
          output.field(
            variable.name.lexeme,
            fieldType,
            member.metadata,
            variable.name.offset,
            physical: (args.first as SimpleStringLiteral).value,
          );
        }
        output.add('});\n', declaration.end - 1);
      } else {
        throw AuthoringFailure(
          'authoring',
          'unsupported_declaration',
          'Only the selected model declaration form is accepted by this experiment.',
          declaration.offset,
          declaration.length,
        );
      }
    }
    for (final declaration
        in result.unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      output.copy(declaration);
      output.add('\n', declaration.end);
    }
    return output;
  } finally {
    await contexts.dispose();
  }
}

final class AuthoringSource(final String original) {
  final _text = StringBuffer();
  final _spans = <({int start, int end, int source, bool exact})>[];
  String get text => _text.toString();

  void add(String value, int offset, {bool exact = false}) {
    _spans.add((
      start: _text.length,
      end: _text.length + value.length,
      source: offset,
      exact: exact,
    ));
    _text.write(value);
  }

  void copy(AstNode node) =>
      add(original.substring(node.offset, node.end), node.offset, exact: true);

  void field(
    String name,
    DartType type,
    Iterable<Annotation> annotations,
    int offset, {
    String? physical,
  }) {
    final display = type.getDisplayString();
    if (!{
      'int',
      'String',
      'bool',
      'DateTime',
      'int?',
      'String?',
      'bool?',
      'DateTime?',
    }.contains(display)) {
      throw AuthoringFailure(
        'authoring',
        'unsupported_type',
        'The controlled experiment supports int, String, bool and DateTime only.',
        offset,
        name.length,
      );
    }
    final metadata = annotations.toList();
    for (final annotation in metadata) {
      if (annotation.name.name == 'ColumnName') {
        final arg = annotation.arguments!.arguments.single;
        if (arg is! SimpleStringLiteral || physical != null) {
          throw AuthoringFailure(
            'authoring',
            'physical_name',
            'Use one literal physical column name.',
            annotation.offset,
            annotation.length,
          );
        }
        physical = arg.value;
      } else {
        copy(annotation);
        add(' ', annotation.end);
      }
    }
    physical ??= name.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '_${m[0]!.toLowerCase()}',
    );
    add('@ColumnName(${jsonEncode(physical)}) $display $name,\n', offset);
  }

  int originalOffset(int offset) {
    final span = _spans.lastWhere((s) => offset >= s.start && offset < s.end);
    return span.source + (span.exact ? offset - span.start : 0);
  }
}

final class AuthoringFailure(
  final String phase,
  final String code,
  final String message,
  final int offset,
  final int length,
) implements Exception {
  Map<String, Object?> toJson(String source) {
    final before = source.substring(0, offset);
    return {
      'phase': phase,
      'code': code,
      'message': message,
      'offset': offset,
      'length': length,
      'line': '\n'.allMatches(before).length + 1,
      'column': offset - before.lastIndexOf('\n'),
      'sourceLine': source.split('\n')['\n'.allMatches(before).length],
    };
  }

  @override
  String toString() => '$phase/$code at $offset: $message';
}
