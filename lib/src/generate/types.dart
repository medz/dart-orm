import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

import 'exception.dart';

// Match defining libraries, not consumer import text. Reexports retain identity.
const codecLibraryUri = 'package:orm/src/values/codec.dart';
const valueLibraryUris = {
  codecLibraryUri,
  'package:orm/src/values/decimal.dart',
  'package:orm/src/values/temporal.dart',
};

/// Resolve symbols by defining library rather than copying source import text.
final class DartNames(final Uri source, final String Function(Uri) importUri) {
  final Map<Uri, String> _prefixes = {};
  final Map<Uri, Set<String>> _exports = {};
  bool usesSource = false;
  bool typedData = false;
  Iterable<(String, Set<String>)> get exports sync* {
    final counts = <String, int>{};
    for (final symbols in _exports.values) {
      for (final symbol in symbols) {
        counts.update(symbol, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    for (final entry in _exports.entries) {
      final symbols = entry.value.where((name) => counts[name] == 1).toSet();
      if (symbols.isNotEmpty) yield (importUri(entry.key), symbols);
    }
  }

  void exportType(DartType value) {
    final element =
        value.alias?.element ?? (value is InterfaceType ? value.element : null);
    if (element != null) {
      final uri = element.library.uri;
      if (!uri.toString().startsWith('dart:') &&
          !valueLibraryUris.contains(uri.toString())) {
        _exports.putIfAbsent(uri, () => {}).add(element.name!);
      }
    }
    if (value is InterfaceType) {
      for (final argument in value.typeArguments) {
        exportType(argument);
      }
    }
  }

  Iterable<(String, String)> get imports sync* {
    for (final entry in _prefixes.entries) {
      yield (importUri(entry.key), entry.value);
    }
  }

  String name(Element element) {
    final library = element.library;
    if (element.isPrivate || element.name == null || library == null) {
      throw GenerationException(
        'Generated clients require public symbols: ${element.displayName}.',
      );
    }
    final uri = library.uri;
    if (uri == source) usesSource = true;
    if (uri.toString() == 'dart:typed_data') typedData = true;
    if ({
      'dart:core',
      'dart:typed_data',
      ...valueLibraryUris,
      'package:orm/src/schema/model.dart',
    }.contains(uri.toString())) {
      return element.name!;
    }
    final prefix = uri == source
        ? 'models'
        : _prefixes.putIfAbsent(uri, () => 'types${_prefixes.length}');
    return '$prefix.${element.name}';
  }

  String type(DartType value) {
    String arguments(List<DartType> values) =>
        values.isEmpty ? '' : '<${values.map(type).join(', ')}>';
    String suffix(NullabilitySuffix suffix) =>
        suffix == NullabilitySuffix.question ? '?' : '';
    if (value.alias case final alias?) {
      return '${name(alias.element)}${arguments(alias.typeArguments)}${suffix(alias.nullabilitySuffix)}';
    }
    return switch (value) {
      InterfaceType() =>
        '${name(value.element)}${arguments(value.typeArguments)}${suffix(value.nullabilitySuffix)}',
      RecordType() =>
        '(${[for (final field in value.positionalFields) type(field.type), if (value.namedFields.isNotEmpty) '{${value.namedFields.map((f) => '${type(f.type)} ${f.name}').join(', ')}}'].join(', ')}${value.positionalFields.length == 1 && value.namedFields.isEmpty ? ',' : ''})${suffix(value.nullabilitySuffix)}',
      DynamicType() => 'dynamic',
      _ => throw GenerationException(
        'Unsupported persistent value type $value.',
      ),
    };
  }

  String codecReference(Expression expression) {
    final element = switch (expression) {
      Identifier() => expression.element,
      PropertyAccess() => expression.propertyName.element,
      _ => null,
    };
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element;
    if (variable is! VariableElement ||
        !variable.isConst ||
        !variable.isStatic ||
        variable.isPrivate) {
      throw const GenerationException(
        'custom() requires a public const codec variable or static field.',
      );
    }
    if (variable case FieldElement(:final enclosingElement)) {
      return '${name(enclosingElement)}.${variable.name}';
    }
    return name(variable);
  }

  String factoryReference(
    Expression expression,
    ExecutableElement function,
    FunctionType signature,
  ) {
    final element = switch (expression) {
      Identifier() => expression.element,
      PropertyAccess() => expression.propertyName.element,
      _ => null,
    };
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element;
    if (variable is VariableElement) {
      if (!variable.isConst || !variable.isStatic || variable.isPrivate) {
        throw const GenerationException(
          'clientDefault factory variables must be public const references.',
        );
      }
      if (variable case FieldElement(:final enclosingElement)) {
        return '${name(enclosingElement)}.${variable.name}';
      }
      return name(variable);
    }
    if (function.isPrivate) {
      throw const GenerationException(
        'clientDefault requires a public factory.',
      );
    }
    if (function is ConstructorElement) {
      return '${type(signature.returnType)}.${function.name}';
    }
    final arguments = expression is FunctionReference
        ? expression.typeArgumentTypes
        : null;
    if (function.typeParameters.isNotEmpty &&
        (arguments == null || arguments.isEmpty)) {
      throw const GenerationException(
        'Instantiate generic clientDefault factories explicitly.',
      );
    }
    final suffix = arguments == null || arguments.isEmpty
        ? ''
        : '<${arguments.map(type).join(', ')}>';
    if (function is TopLevelFunctionElement) return '${name(function)}$suffix';
    if (function is MethodElement && function.isStatic) {
      return '${name(function.enclosingElement!)}.${function.name}$suffix';
    }
    throw const GenerationException(
      'clientDefault requires a public top-level function, static method or constructor.',
    );
  }
}
