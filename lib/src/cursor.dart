part of '../orm.dart';

enum NullOrder { first, last }

final class CursorTerm {
  final OrderTerm order;
  final Object? _value;
  const CursorTerm._(this.order, this._value);
}

extension KeysetQuery<R, F extends Fields> on Query<R, F> {
  Query<R, F> seekAfter(List<CursorTerm> Function(F) cursor) {
    final terms = List<CursorTerm>.unmodifiable(cursor(_fields));
    _validateCursor(terms.map((t) => t.order).toList());
    _Node? predicate;
    _Node? prefix;
    for (final term in terms) {
      final node = term.order.expression._node;
      final last = term._value;
      final isNull = _Unary('IS NULL', node, postfix: true);
      _Node comparison;
      if (last == null) {
        comparison = term.order.nulls == NullOrder.first
            ? _Unary('IS NOT NULL', node, postfix: true)
            : _Raw(const ['FALSE'], const []);
      } else {
        comparison = _Binary(
          node,
          term.order.descending ? '<' : '>',
          _Parameter(last),
        );
        if (term.order.nulls == NullOrder.last) {
          comparison = _Binary(comparison, 'OR', isNull);
        }
      }
      final branch = prefix == null
          ? comparison
          : _Binary(prefix, 'AND', comparison);
      predicate = predicate == null ? branch : _Binary(predicate, 'OR', branch);
      final equal = last == null
          ? isNull
          : _Binary(node, '=', _Parameter(last));
      prefix = prefix == null ? equal : _Binary(prefix, 'AND', equal);
    }
    final next = Expr<bool?>._(predicate!, Codecs.boolean.nullable());
    return _copy(
      _state.copy(
        predicate: _state.predicate?.and(next) ?? next,
        order: [for (final term in terms) term.order],
      ),
    );
  }

  /// Versioned, lossless cursor transport. This is pagination input, not an
  /// authorization token. The next query still applies its own WHERE policies.
  String cursorToken(List<CursorTerm> Function(F) cursor) {
    final terms = cursor(_fields);
    _validateCursor(terms.map((t) => t.order).toList());
    final payload = {
      'version': 1,
      'table': _state.source.schema.name,
      'order': _cursorShape(terms.map((t) => t.order).toList()),
      'values': [for (final term in terms) _encodeCursorValue(term._value)],
    };
    return base64Url.encode(utf8.encode(jsonEncode(payload)));
  }

  Query<R, F> seekToken(
    String token, {
    required List<OrderTerm> Function(F) orderBy,
  }) {
    final order = orderBy(_fields);
    _validateCursor(order);
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(token)),
      ) as Map<String, Object?>;
      if (payload['version'] != 1 ||
          payload['table'] != _state.source.schema.name ||
          jsonEncode(payload['order']) != jsonEncode(_cursorShape(order))) {
        throw const FormatException(
          'Cursor belongs to another schema or sort order.',
        );
      }
      final values = payload['values'] as List<Object?>;
      if (values.length != order.length) {
        throw const FormatException('Cursor arity differs.');
      }
      final terms = <CursorTerm>[];
      for (var i = 0; i < order.length; i++) {
        final codec = order[i].expression.codec;
        final decoded = codec.decode(_decodeCursorValue(values[i]));
        terms.add(CursorTerm._(order[i], codec.encode(decoded)));
      }
      return seekAfter((_) => terms);
    } catch (e) {
      throw OrmException(
        'QUERY.CURSOR',
        'Invalid cursor for this query.',
        cause: e,
      );
    }
  }

  void _validateCursor(List<OrderTerm> order) {
    if (order.isEmpty ||
        _state.joins.isNotEmpty ||
        _state.group.isNotEmpty ||
        _state.distinct ||
        _state.offset != null ||
        _state.ctes.isNotEmpty) {
      throw const OrmException(
        'QUERY.CURSOR',
        'Keyset pagination requires an ungrouped table query without joins, DISTINCT or offset.',
      );
    }
    final names = <String>{};
    for (final term in order) {
      final node = term.expression._node;
      if (node is! _ColumnNode ||
          node.table != _state.source ||
          !names.add(node.name)) {
        throw const OrmException(
          'QUERY.CURSOR',
          'Order by distinct columns belonging to this table.',
        );
      }
      if (term.expression.codec.acceptsNull && term.nulls == null) {
        throw const OrmException(
          'QUERY.CURSOR',
          'Nullable cursor columns require explicit NULLS FIRST or LAST.',
        );
      }
    }
    final schema = _state.source.schema;
    final keys = [
      schema.primaryKey,
      ...schema.uniqueKeys,
      for (final index in schema.indexes)
        if (index.unique) index.columns,
    ];
    if (!keys.any(
      (key) =>
          key.isNotEmpty &&
          key.every(
            (name) =>
                names.contains(name) &&
                !schema.columns.firstWhere((c) => c.name == name).nullable,
          ),
    )) {
      throw const OrmException(
        'QUERY.CURSOR',
        'Include a non-null primary or unique key as the stable tie breaker.',
      );
    }
  }

  List<Object?> _cursorShape(List<OrderTerm> order) => [
    for (final o in order)
      [
        (o.expression._node as _ColumnNode).name,
        o.expression.codec.sqlType,
        o.expression.codec.acceptsNull,
        o.descending,
        o.nulls?.name,
      ],
  ];
}

Object? _encodeCursorValue(Object? value) => switch (value) {
  null || String() || bool() => value,
  int v => ['int', v.toString()],
  double v when v.isFinite => ['double', v.toString()],
  DateTime v => ['time', v.toUtc().toIso8601String()],
  Uint8List v => ['bytes', base64Encode(v)],
  _ => throw const OrmException(
    'QUERY.CURSOR',
    'Codec storage value is not supported in cursors.',
  ),
};
Object? _decodeCursorValue(Object? value) => switch (value) {
  null || String() || bool() => value,
  ['int', String v] => _cursorInt(v),
  ['double', String v] => _cursorDouble(v),
  ['time', String v] => DateTime.parse(v).toUtc(),
  ['bytes', String v] => base64Decode(v),
  _ => throw const FormatException('Invalid cursor value.'),
};

int _cursorInt(String value) {
  final parsed = int.parse(value);
  if (parsed.toString() != value) {
    throw const FormatException(
      'Cursor integer cannot be represented exactly.',
    );
  }
  return parsed;
}

double _cursorDouble(String value) {
  final parsed = double.parse(value);
  if (!parsed.isFinite) {
    throw const FormatException('Cursor numbers must be finite.');
  }
  return parsed;
}
