import 'package:analyzer/dart/ast/ast.dart';

import '../exception.dart';

/// Validates selected roots and the libraries owning discovered model classes.
void validateModelLibrary(CompilationUnit unit, {Uri? source}) {
  final directive = unit.directives
      .where((node) => node is PartDirective || node is PartOfDirective)
      .firstOrNull;
  if (directive == null) return;
  final location = unit.lineInfo.getLocation(directive.offset);
  throw GenerationException(
    'Use independent Dart model libraries without part or part of directives.',
    code: 'SCHEMA.LIBRARY',
    source: source ?? unit.declaredFragment!.source.uri,
    line: location.lineNumber,
    column: location.columnNumber,
  );
}

Never failAt(AstNode node, String code, String message) {
  final sourceUnit = node.root as CompilationUnit;
  final location = sourceUnit.lineInfo.getLocation(node.offset);
  throw GenerationException(
    message,
    code: 'SCHEMA.$code',
    source: sourceUnit.declaredFragment!.element.uri,
    line: location.lineNumber,
    column: location.columnNumber,
  );
}
