import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../exception.dart';
import 'syntax.dart' show isModel;

Iterable<VariableDeclaration> topLevelVariables(CompilationUnit unit) sync* {
  for (final declaration
      in unit.declarations.whereType<TopLevelVariableDeclaration>()) {
    yield* declaration.variables.variables;
  }
}

VariableElement? modelVariable(Element? element) {
  final variable = element is PropertyAccessorElement
      ? element.variable
      : element;
  return variable is VariableElement && isModel(variable.type)
      ? variable
      : null;
}

/// Starts at public exports and local declarations, then follows model identity
/// references. Unrelated imports and unexported models in other files are not
/// schema roots. The resolver is supplied by the CLI or build asset owner.
Future<List<VariableDeclaration>> schemaSources(
  CompilationUnit root,
  LibraryElement library,
  Future<CompilationUnit> Function(LibraryElement) resolve,
) async {
  final units = <LibraryElement, CompilationUnit>{library: root};
  final result = <VariableElement, VariableDeclaration>{};
  final exports = library.exportNamespace.definedNames2.values
      .map(modelVariable)
      .whereType<VariableElement>()
      .toSet();
  final pending = <VariableElement>[
    for (final variable in topLevelVariables(root))
      if (isModel(variable.declaredFragment!.element.type))
        variable.declaredFragment!.element,
    ...exports,
  ];
  for (var i = 0; i < pending.length; i++) {
    final element = pending[i];
    if (result.containsKey(element)) continue;
    final owner = element.library!;
    final unit = units[owner] ??= await resolve(owner);
    final variable = topLevelVariables(unit)
        .where((v) => v.declaredFragment!.element == element)
        .firstOrNull;
    if (variable == null) {
      throw GenerationException(
        'Cannot resolve model ${element.name}. Declare models in independent Dart libraries.',
      );
    }
    result[element] = variable;
    variable.initializer?.accept(
      _ModelReferences((dependency) {
        if (!result.containsKey(dependency)) pending.add(dependency);
      }),
    );
  }
  return result.values.toList();
}

final class _ModelReferences(final void Function(VariableElement) found)
    extends RecursiveAstVisitor<void> {
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final variable = modelVariable(node.element);
    if (variable != null) found(variable);
    super.visitSimpleIdentifier(node);
  }
}
