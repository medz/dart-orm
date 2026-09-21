import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../exception.dart';

const schemaDeclarationUri = 'package:orm/src/schema/declaration.dart';

bool isModel(DartType? type) =>
    type is InterfaceType &&
    type.element.name == 'Model' &&
    type.element.library.uri.toString() == schemaDeclarationUri;

List<Expression> positionalArguments(InvocationExpression call) => [
  for (final argument in call.argumentList.arguments)
    if (argument is! NamedArgument) argument.argumentExpression,
];
Expression? namedArgument(InvocationExpression call, String name) {
  for (final argument
      in call.argumentList.arguments.whereType<NamedArgument>()) {
    if (argument.name.lexeme == name) {
      final expression = argument.argumentExpression;
      return expression is NullLiteral ||
              constantValue(expression)?.isNull == true
          ? null
          : expression;
    }
  }
  return null;
}

String? namedString(InvocationExpression call, String name) {
  final value = namedArgument(call, name);
  return value == null ? null : stringValue(value);
}

int? namedInteger(InvocationExpression call, String name) {
  final expression = namedArgument(call, name);
  if (expression == null) return null;
  final value = scalarValue(expression);
  return value is int
      ? value
      : failAt(
          expression,
          'CONSTANT',
          'Use an integer literal or const reference.',
        );
}

bool? namedBoolean(InvocationExpression call, String name) {
  final expression = namedArgument(call, name);
  if (expression == null) return null;
  final value = scalarValue(expression);
  return value is bool
      ? value
      : failAt(
          expression,
          'CONSTANT',
          'Use a boolean literal or const reference.',
        );
}

String stringValue(Expression expression) {
  final value = scalarValue(expression);
  return value is String
      ? value
      : failAt(
          expression,
          'CONSTANT',
          'Use a string literal or const reference.',
        );
}

Object? scalarValue(Expression expression) {
  if (expression is SimpleStringLiteral) return expression.value;
  if (expression is BooleanLiteral) return expression.value;
  if (expression is IntegerLiteral) return expression.value;
  if (expression is DoubleLiteral) return expression.value;
  if (expression is PrefixExpression && expression.operator.lexeme == '-') {
    final value = scalarValue(expression.operand);
    if (value is num) return -value;
  }
  final value = constantValue(expression);
  return value?.toStringValue() ??
      value?.toBoolValue() ??
      value?.toIntValue() ??
      value?.toDoubleValue();
}

DartObject? constantValue(Expression expression) {
  final element = resolvedElement(expression);
  return element is VariableElement && element.isConst
      ? element.computeConstantValue()
      : null;
}

String? enumName(Expression? expression) {
  if (expression == null) return null;
  final element = resolvedElement(expression);
  if (element is FieldElement && element.isEnumConstant) return element.name;
  final constant = constantValue(expression);
  final type = constant?.type;
  final index = constant?.getField('index')?.toIntValue();
  if (type is InterfaceType && type.element is EnumElement && index != null) {
    return (type.element as EnumElement).fields
        .where((f) => f.isEnumConstant)
        .elementAt(index)
        .name;
  }
  return failAt(expression, 'CONSTANT', 'Use an enum constant.');
}

Element? resolvedElement(Expression expression) {
  final element = switch (expression) {
    Identifier() => expression.element,
    PropertyAccess() => expression.propertyName.element,
    DotShorthandPropertyAccess() => expression.propertyName.element,
    ConstructorReference() => expression.constructorName.element,
    FunctionReference() => resolvedElement(expression.function),
    _ => null,
  };
  return element is PropertyAccessorElement ? element.variable : element;
}

String callName(InvocationExpression call) {
  if (callElement(call)?.library?.uri.toString() != schemaDeclarationUri) {
    failAt(
      call,
      'DECLARATION',
      'Use the helpers from package:orm/schema.dart.',
    );
  }
  return switch (call) {
    MethodInvocation() => call.methodName.name,
    DotShorthandInvocation() => call.memberName.name,
    _ => failAt(call, 'DECLARATION', 'Unsupported declaration expression.'),
  };
}

Element? callElement(InvocationExpression call) => switch (call) {
  MethodInvocation() => call.methodName.element,
  DotShorthandInvocation() => call.memberName.element,
  _ => null,
};
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
