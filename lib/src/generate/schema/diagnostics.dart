import 'package:analyzer/dart/ast/ast.dart';

import '../exception.dart';

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
