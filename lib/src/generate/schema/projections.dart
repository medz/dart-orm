import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart' show Keyword;
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import '../model.dart';
import '../types.dart';
import 'annotations.dart' show annotationLibrary;
import 'diagnostics.dart';

String? _name(ElementAnnotation annotation) {
  final type = annotation.computeConstantValue()?.type;
  return type is InterfaceType &&
          type.element.library.uri.toString() == annotationLibrary
      ? type.element.name
      : null;
}

bool _isProjection(Element element) =>
    element.metadata.annotations.any((a) => _name(a) == 'Projection');

Element? projectionElement(CompilationUnitMember node) => switch (node) {
  ClassDeclaration() => node.declaredFragment?.element,
  GenericTypeAlias() => node.declaredFragment?.element,
  _ => null,
};

/// Finds explicitly selected projection declarations, without following imports.
Future<List<CompilationUnitMember>> projectionSources(
  List<CompilationUnit> roots,
  Future<CompilationUnit> Function(LibraryElement) resolve,
) async {
  final units = <LibraryElement, CompilationUnit>{
    for (final unit in roots) unit.declaredFragment!.element: unit,
  };
  final pending = <Element>{
    for (final unit in roots)
      for (final declaration in unit.declarations)
        if (projectionElement(declaration) case final element?
            when _isProjection(element))
          element,
    for (final library in units.keys)
      for (final element in library.exportNamespace.definedNames2.values)
        if ((element is ClassElement || element is TypeAliasElement) &&
            _isProjection(element))
          element,
  };
  final result = <CompilationUnitMember>[];
  for (final element in pending) {
    final library = element.library!;
    final unit = units[library] ??= await resolve(library);
    validateModelLibrary(unit);
    final node = unit.declarations
        .where((node) => projectionElement(node) == element)
        .firstOrNull;
    if (node == null) {
      failAt(
        unit,
        'PROJECTION',
        'Projection declarations need independent source libraries.',
      );
    }
    result.add(node);
  }
  return result;
}

/// Reads output layouts without applying physical column or model rules.
List<ModelProjection> readProjections(
  List<CompilationUnitMember> declarations,
  DartNames names,
  List<ModelEntity> models,
) {
  final symbols = <String>{
    'appSchema',
    'AppTables',
    ...generatedTypeNames,
    for (final model in models) ...modelGeneratedSymbols(model),
  };
  final result = <ModelProjection>[];
  for (final node in declarations) {
    final element = projectionElement(node)!;
    final annotations = element.metadata.annotations.where(
      (a) => _name(a) == 'Projection',
    );
    if (annotations.length != 1) {
      failAt(
        node,
        'ANNOTATION',
        'Use one @Projection annotation per declaration.',
      );
    }
    node.accept(_ProjectionAnnotations());
    final symbol = element.name!;
    final binding = '${symbol[0].toLowerCase()}${symbol.substring(1)}';
    if (element.isPrivate ||
        Keyword.keywords[binding]?.isReservedWord == true) {
      failAt(
        node,
        'PROJECTION',
        'Use a public projection name with a valid Dart binding name.',
      );
    }
    final members = <ProjectionMember>[];
    void add(String name, DartType type) {
      if ({
            'table',
            'column',
            'readColumn',
            'hashCode',
            'runtimeType',
            'toString',
            'noSuchMethod',
          }.contains(name) ||
          name.startsWith('_')) {
        failAt(
          node,
          'PROJECTION',
          'Projection field $name conflicts with the derived fields API.',
        );
      }
      if (type is DynamicType ||
          type is VoidType ||
          type is FunctionType ||
          type is TypeParameterType) {
        failAt(
          node,
          'PROJECTION',
          'Projection field $name needs an explicit concrete value type.',
        );
      }
      names.exportType(type);
      members.add(ProjectionMember(name, names.type(type)));
    }

    final bool record;
    if (element is ClassElement) {
      if (element.typeParameters.isNotEmpty) {
        failAt(
          node,
          'PROJECTION',
          'Projection declarations must be nongeneric.',
        );
      }
      final constructor = element.constructors
          .where((c) => c.name == 'new')
          .firstOrNull;
      if (constructor == null ||
          constructor.formalParameters.any((p) => !p.isNamed)) {
        failAt(
          node,
          'PROJECTION',
          'A projection class needs an unnamed constructor with named parameters.',
        );
      }
      if (element.isAbstract && !constructor.isFactory) {
        failAt(
          node,
          'PROJECTION',
          'An abstract projection needs an unnamed factory constructor that returns a concrete implementation.',
        );
      }
      for (final parameter in constructor.formalParameters) {
        add(parameter.name!, parameter.type);
      }
      record = false;
    } else if (element is TypeAliasElement) {
      final type = element.aliasedType;
      if (element.typeParameters.isNotEmpty ||
          type is! RecordType ||
          type.positionalFields.isNotEmpty ||
          type.nullabilitySuffix == NullabilitySuffix.question) {
        failAt(
          node,
          'PROJECTION',
          'A projection typedef must declare a nonnullable named record without type parameters.',
        );
      }
      for (final field in type.namedFields) {
        add(field.name, field.type);
      }
      record = true;
    } else {
      failAt(
        node,
        'PROJECTION',
        'Use a class or named-record typedef for a projection.',
      );
    }
    if (members.isEmpty) {
      failAt(
        node,
        'PROJECTION',
        'A projection needs at least one named output value.',
      );
    }
    names.exportElement(element);
    final projection = ModelProjection(
      symbol,
      names.name(element),
      members,
      record: record,
    );
    for (final generated in [
      symbol,
      projection.binding,
      projection.fieldsType,
      projection.descriptor,
      for (final member in members) projection.slot(member),
    ]) {
      if (!symbols.add(generated)) {
        failAt(
          node,
          'NAME',
          'Generated symbol $generated is ambiguous. Rename the projection or model declaration.',
        );
      }
    }
    result.add(projection);
  }
  return result..sort((a, b) => a.symbol.compareTo(b.symbol));
}

final class _ProjectionAnnotations extends RecursiveAstVisitor<void> {
  @override
  void visitAnnotation(Annotation node) {
    final annotation = node.elementAnnotation;
    final name = annotation == null ? null : _name(annotation);
    if (name != null &&
        (name != 'Projection' || node.parent is! CompilationUnitMember)) {
      failAt(
        node,
        'ANNOTATION',
        'Projection values use their bound expression codecs; @$name does not declare physical storage here.',
      );
    }
    super.visitAnnotation(node);
  }
}
