part of '../../generate.dart';

/// Resolve symbols by defining library rather than copying source import text.
final class _DartNames(final Uri source, final String Function(Uri) importUri) {
  final Map<Uri, String> _prefixes = {};
  bool typedData = false;
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
    if (uri.toString() == 'dart:typed_data') typedData = true;
    if ({
      'dart:core',
      'dart:typed_data',
      'package:orm/orm.dart',
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
        'UseCodec requires a public const codec variable or static field.',
      );
    }
    if (variable case FieldElement(:final enclosingElement)) {
      return '${name(enclosingElement)}.${variable.name}';
    }
    return name(variable);
  }

  String enumeration(EnumElement element) {
    final values = <String, String>{};
    final labels = <String>{};
    for (final field in element.fields.where((f) => f.isEnumConstant)) {
      String? label;
      for (final annotation in field.metadata.annotations) {
        final value = annotation.computeConstantValue();
        final type = value?.type;
        if (type is InterfaceType &&
            type.element.name == 'EnumValue' &&
            type.element.library.uri.toString() == 'package:orm/schema.dart') {
          if (label != null) {
            throw GenerationException(
              'EnumValue appears twice on ${field.name}.',
            );
          }
          label = value!.getField('value')!.toStringValue()!;
        }
      }
      label ??= field.name!;
      if (!labels.add(label)) {
        throw GenerationException('Duplicate enum storage label $label.');
      }
      values[field.name!] = label;
    }
    if (values.isEmpty) {
      throw GenerationException('An empty enum cannot be stored.');
    }
    final symbol = name(element);
    return 'Codecs.enumeration<$symbol>({${values.entries.map((e) => '$symbol.${e.key}: ${_literal(e.value)}').join(', ')}})';
  }
}
