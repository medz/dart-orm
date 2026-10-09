import 'dart:typed_data';

import 'package:orm/schema.dart' show ScalarType;

/// A parameterized SQL condition on one field. Combine with & / | on that field.
/// SQL null semantics apply; eq(null) and ne(null) use IS NULL / IS NOT NULL.
/// Conditions capture their values when constructed, including byte contents.
sealed class Filter<T> {
  const Filter();
  Filter<T> operator &(Filter<T> other) => _Group(this, other, 'AND');
  Filter<T> operator |(Filter<T> other) => _Group(this, other, 'OR');

  /// Internal compilation contract; only this library can implement filters.
  String compile(String column, String Function(Object?) bind, ScalarType type);
}

final class _Compare<T> extends Filter<T> {
  _Compare(this.operator, T value) : value = _snapshot(value);
  final String operator;
  final Object? value;

  @override
  String compile(
    String column,
    String Function(Object?) bind,
    ScalarType type,
  ) {
    if (value == null) {
      if (operator == '=') return '$column IS NULL';
      if (operator == '<>') return '$column IS NOT NULL';
      throw ArgumentError('Ordered comparison with NULL is undefined');
    }
    if (operator != '=' &&
        operator != '<>' &&
        (type == ScalarType.boolean || type == ScalarType.bytes)) {
      throw ArgumentError('Ordered comparison is unsupported for $type');
    }
    return '$column $operator ${bind(value)}';
  }
}

final class _In<T> extends Filter<T> {
  _In(Iterable<T> values)
    : values = List<Object?>.unmodifiable(values.map(_snapshot));
  final List<Object?> values;
  @override
  String compile(
    String column,
    String Function(Object?) bind,
    ScalarType type,
  ) {
    if (values.isEmpty) return '1 = 0';
    final nonNull = values.where((v) => v != null).toList();
    final parts = <String>[];
    if (nonNull.isNotEmpty) {
      parts.add('$column IN (${nonNull.map(bind).join(', ')})');
    }
    if (nonNull.length != values.length) parts.add('$column IS NULL');
    return '(${parts.join(' OR ')})';
  }
}

final class _Like extends Filter<String> {
  const _Like(this.value, this.contains);
  final String value;
  final bool contains;
  @override
  String compile(
    String column,
    String Function(Object?) bind,
    ScalarType type,
  ) {
    if (type != ScalarType.text) {
      throw ArgumentError('Text filter requires a text column');
    }
    final escaped = value
        .replaceAll('!', '!!')
        .replaceAll('%', '!%')
        .replaceAll('_', '!_');
    return "$column LIKE ${bind('${contains ? '%' : ''}$escaped%')} ESCAPE '!'";
  }
}

final class _Group<T> extends Filter<T> {
  const _Group(this.left, this.right, this.operator);
  final Filter<T> left;
  final Filter<T> right;
  final String operator;
  @override
  String compile(
    String column,
    String Function(Object?) bind,
    ScalarType type,
  ) =>
      '(${left.compile(column, bind, type)} $operator ${right.compile(column, bind, type)})';
}

Object? _snapshot(Object? value) =>
    value is Uint8List ? Uint8List.fromList(value).asUnmodifiableView() : value;

/// Equality; null becomes IS NULL.
Filter<T> eq<T>(T value) => _Compare('=', value);

/// Inequality; null becomes IS NOT NULL.
Filter<T> ne<T>(T value) => _Compare('<>', value);

/// Greater than a non-null ordered scalar.
Filter<T> gt<T>(T value) => _Compare('>', value);

/// Greater than or equal to a non-null ordered scalar.
Filter<T> gte<T>(T value) => _Compare('>=', value);

/// Less than a non-null ordered scalar.
Filter<T> lt<T>(T value) => _Compare('<', value);

/// Less than or equal to a non-null ordered scalar.
Filter<T> lte<T>(T value) => _Compare('<=', value);

/// Membership. Empty input matches nothing; an explicit null matches SQL NULL.
Filter<T> oneOf<T>(Iterable<T> values) => _In(values);

/// Literal prefix matching using native LIKE, escaping SQL wildcard characters.
Filter<String> startsWith(String value) => _Like(value, false);

/// Literal substring matching using native LIKE, escaping SQL wildcards.
Filter<String> containsText(String value) => _Like(value, true);
