import 'package:meta/meta.dart';

import 'dart:convert';
import 'dart:typed_data';

import '../../driver.dart';
import '../../schema_model.dart';
import 'expression.dart';
import 'nodes.dart';
import 'query.dart';
import 'table.dart';

/// Explicit placement of SQL NULL relative to non-null sort values.
enum NullOrder { first, last }

/// One ordering expression paired with its last-seen, encoded cursor value.
///
/// Create terms with a typed expression's `cursor` method. Nullable expressions
/// require an explicit [NullOrder] when used for keyset pagination.
final class CursorTerm {
  /// SQL ordering whose value is carried by this cursor term.
  final OrderTerm order;

  /// @nodoc
  @internal
  final Object? assignedValue;

  /// @nodoc
  @internal
  const CursorTerm.internal(this.order, this.assignedValue);
}

/// Stable keyset pagination for a filtered table query.
///
/// Sort columns must include a non-null declared primary or unique key. Joins,
/// grouping, DISTINCT, offsets, CTEs, and UNION queries cannot use this pagination.
extension KeysetQuery<R, F extends Fields> on Query<R, F> {
  /// Adds a lexicographic boundary after [cursor] and replaces query ordering.
  ///
  /// Existing WHERE filters remain in effect. Cursor terms must use distinct
  /// columns from this table, with explicit NULL ordering for nullable columns.
  Query<R, F> seekAfter(List<CursorTerm> Function(F) cursor) {
    final terms = List<CursorTerm>.unmodifiable(cursor(queryFields));
    _validateCursor(terms.map((t) => t.order).toList());
    SqlNode? predicate;
    SqlNode? prefix;
    for (final term in terms) {
      final node = term.order.expression.expressionNode;
      final last = term.assignedValue;
      final isNull = UnaryNode('IS NULL', node, postfix: true);
      SqlNode comparison;
      if (last == null) {
        comparison = term.order.nulls == NullOrder.first
            ? UnaryNode('IS NOT NULL', node, postfix: true)
            : RawNode(const ['FALSE'], const []);
      } else {
        comparison = BinaryNode(
          node,
          term.order.descending ? '<' : '>',
          ParameterNode(last, storageType: term.order.expression.codec.sqlType),
        );
        if (term.order.nulls == NullOrder.last) {
          comparison = BinaryNode(comparison, 'OR', isNull);
        }
      }
      final branch = prefix == null
          ? comparison
          : BinaryNode(prefix, 'AND', comparison);
      predicate = predicate == null
          ? branch
          : BinaryNode(predicate, 'OR', branch);
      final equal = last == null
          ? isNull
          : BinaryNode(
              node,
              '=',
              ParameterNode(
                last,
                storageType: term.order.expression.codec.sqlType,
              ),
            );
      prefix = prefix == null ? equal : BinaryNode(prefix, 'AND', equal);
    }
    final next = Expr<bool?>.internal(predicate!, Codecs.boolean.nullable());
    return copyQuery(
      queryState.copy(
        predicate: queryState.predicate?.and(next) ?? next,
        order: [for (final term in terms) term.order],
      ),
    );
  }

  /// Versioned, lossless cursor transport. This is pagination input, not an
  /// authorization token. The next query still applies its own WHERE policies.
  String cursorToken(List<CursorTerm> Function(F) cursor) {
    final terms = cursor(queryFields);
    _validateCursor(terms.map((t) => t.order).toList());
    final payload = {
      'version': 1,
      'table': queryState.source.schema.name,
      'order': _cursorShape(terms.map((t) => t.order).toList()),
      'values': [
        for (final term in terms) _encodeCursorValue(term.assignedValue),
      ],
    };
    return base64Url.encode(utf8.encode(jsonEncode(payload)));
  }

  /// Restores a [cursorToken] using the expected table and complete sort order.
  ///
  /// Rejects malformed tokens or mismatched columns, codecs, directions, and
  /// nullability with `QUERY.CURSOR`. Existing filters still apply; the token
  /// is neither signed authorization nor a database snapshot.
  Query<R, F> seekToken(
    String token, {
    required List<OrderTerm> Function(F) orderBy,
  }) {
    final order = orderBy(queryFields);
    _validateCursor(order);
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(token)),
      ) as Map<String, Object?>;
      if (payload['version'] != 1 ||
          payload['table'] != queryState.source.schema.name ||
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
        terms.add(CursorTerm.internal(order[i], codec.encode(decoded)));
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
        queryState.joins.isNotEmpty ||
        queryState.group.isNotEmpty ||
        queryState.distinct ||
        queryState.offset != null ||
        queryState.union != null ||
        queryState.ctes.isNotEmpty) {
      throw const OrmException(
        'QUERY.CURSOR',
        'Keyset pagination requires an ungrouped table query without joins, DISTINCT or offset.',
      );
    }
    final names = <String>{};
    for (final term in order) {
      final node = unwrapStorage(term.expression.expressionNode);
      if (node is! ColumnNode ||
          node.table != queryState.source ||
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
    final schema = queryState.source.schema;
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
        (unwrapStorage(o.expression.expressionNode) as ColumnNode).name,
        o.expression.codec.sqlType,
        o.expression.codec.acceptsNull,
        o.descending,
        o.nulls?.name,
      ],
  ];
}

Object? _encodeCursorValue(Object? value) => switch (value) {
  null || String() || bool() => value,
  SqlReal(:final value) when value.isFinite => ['double', value.toString()],
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
