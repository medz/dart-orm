part of '../orm.dart';

enum SqlDialect { sqlite, postgres }

/// SQL text and separately bound values. Values are never interpolated into SQL.
final class SqlCommand {
  final String sql;
  final List<Object?> parameters;
  SqlCommand(this.sql, [List<Object?> parameters = const []])
    : parameters = List.unmodifiable(parameters);
}

sealed class _Node {
  const _Node();
  String write(_Writer writer);
}

final class _ColumnNode(final TableRef table, final String name) extends _Node {
  @override
  String write(_Writer w) {
    final alias = w.aliases[table];
    if (alias == null) {
      throw const OrmException(
        'QUERY.SCOPE',
        'Column belongs to another query.',
      );
    }
    return w.unqualified ? w.quote(name) : '${w.quote(alias)}.${w.quote(name)}';
  }
}

final class _Parameter(final Object? value, {final String? sqlType})
    extends _Node {
  @override
  String write(_Writer w) {
    final parameter = w.parameter(value);
    // A standalone SELECT parameter has no column context in PostgreSQL and
    // otherwise resolves to text, including inside a UNION operand.
    if (sqlType == null || w.dialect == SqlDialect.sqlite) return parameter;
    final type = switch (sqlType) {
      'integer' => 'BIGINT',
      'bigint' || 'decimal' => 'NUMERIC',
      'text' => 'TEXT',
      'real' => 'DOUBLE PRECISION',
      'boolean' => 'BOOLEAN',
      'timestamp' => 'TIMESTAMPTZ',
      'json' => 'JSONB',
      'blob' => 'BYTEA',
      _ => throw OrmException(
        'QUERY.PARAMETER_TYPE',
        'No PostgreSQL parameter type for $sqlType.',
      ),
    };
    return 'CAST($parameter AS $type)';
  }
}

final class _Binary(final _Node left, final String op, final _Node right)
    extends _Node {
  @override
  String write(_Writer w) => '(${left.write(w)} $op ${right.write(w)})';
}

final class _Unary(
  final String op,
  final _Node child, {
  final bool postfix = false,
}) extends _Node {
  @override
  String write(_Writer w) =>
      postfix ? '(${child.write(w)} $op)' : '($op ${child.write(w)})';
}

final class _Function(
  final String name,
  final List<_Node> arguments, {
  final bool distinct = false,
  final bool decimal = false,
}) extends _Node {
  @override
  String write(_Writer w) =>
      '${decimal && w.dialect == SqlDialect.sqlite ? 'orm_decimal_${name.toLowerCase()}_v1' : name}(${distinct ? 'DISTINCT ' : ''}'
      '${arguments.map((e) => e.write(w)).join(', ')})';
}

final class _In(final _Node expression, final List<_Node> values)
    extends _Node {
  @override
  String write(_Writer w) => values.isEmpty
      ? 'FALSE'
      : '(${expression.write(w)} IN (${values.map((v) => v.write(w)).join(', ')}))';
}

/// Trusted SQL fragments still bind embedded expressions as parameters or ASTs.
final class _Raw(final List<String> parts, final List<_Node> values)
    extends _Node {
  @override
  String write(_Writer w) {
    final result = StringBuffer(parts.first);
    for (var i = 0; i < values.length; i++) {
      result
        ..write(values[i].write(w))
        ..write(parts[i + 1]);
    }
    return result.toString();
  }
}

final class _Writer {
  final SqlDialect dialect;
  final Map<TableRef, String> aliases;
  final List<Object?> parameters = [];
  final Set<TableRef> leftJoins = {};
  final _ReadTables? reads;
  final bool exactDecimal;
  bool unqualified = false;
  _Writer(this.dialect, this.aliases, {this.reads, this.exactDecimal = false});
  String quote(String name) => '"${name.replaceAll('"', '""')}"';
  String parameter(Object? value) {
    parameters.add(switch ((dialect, value)) {
      (SqlDialect.sqlite, bool v) => v ? 1 : 0,
      (SqlDialect.sqlite, DateTime v) => v.toUtc().toIso8601String(),
      _ => value,
    });
    return dialect == SqlDialect.postgres
        ? '\$${parameters.length}'
        : '?${parameters.length}';
  }
}

class Expr<T> extends Selection<T> {
  final _Node _node;
  final Codec<T> codec;
  Expr._(_Node node, this.codec)
    : _node = codec.sqlType == 'decimal' && node is! _DecimalNode
          ? _DecimalNode(node)
          : node;

  Expr<bool?> eq(T value) => value == null
      ? Expr._(
          _Unary('IS NULL', _node, postfix: true),
          Codecs.boolean.nullable(),
        )
      : _compare('=', _Parameter(codec.encode(value)));
  Expr<bool?> ne(T value) => value == null
      ? Expr._(
          _Unary('IS NOT NULL', _node, postfix: true),
          Codecs.boolean.nullable(),
        )
      : _compare('<>', _Parameter(codec.encode(value)));
  Expr<bool?> equals(Expr<T> other) => _compare('=', other._node);
  Expr<bool?> gt(T value) => _compare('>', _Parameter(codec.encode(value)));
  Expr<bool?> gte(T value) => _compare('>=', _Parameter(codec.encode(value)));
  Expr<bool?> lt(T value) => _compare('<', _Parameter(codec.encode(value)));
  Expr<bool?> lte(T value) => _compare('<=', _Parameter(codec.encode(value)));
  Expr<bool?> _compare(String op, _Node right) =>
      Expr._(_Binary(_node, op, right), Codecs.boolean.nullable());
  Expr<bool> isNull() =>
      Expr._(_Unary('IS NULL', _node, postfix: true), Codecs.boolean);
  Expr<bool> isNotNull() =>
      Expr._(_Unary('IS NOT NULL', _node, postfix: true), Codecs.boolean);
  Expr<bool?> isIn(Iterable<T> values) => Expr._(
    _In(_node, [for (final value in values) _Parameter(codec.encode(value))]),
    Codecs.boolean.nullable(),
  );
  Expr<bool?> isInQuery<F extends Fields>(Query<T, F> query) {
    if (query._selection is! Expr<T>) {
      throw const OrmException(
        'QUERY.SCALAR',
        'IN subqueries select one SQL expression.',
      );
    }
    return Expr._(
      _Binary(_node, 'IN', _Subquery(query)),
      Codecs.boolean.nullable(),
    );
  }

  Expr<T> over({
    List<Expr<Object?>> partitionBy = const [],
    List<OrderTerm> orderBy = const [],
    WindowFrame? frame,
  }) {
    final function = _unwrapDecimal(_node);
    if (function is! _Function || !_aggregate(function)) {
      throw const OrmException(
        'QUERY.WINDOW',
        'over() applies to an aggregate expression.',
      );
    }
    return Expr._(
      _WindowNode(
        function,
        List.unmodifiable(partitionBy),
        List.unmodifiable(orderBy),
        frame,
      ),
      codec,
    );
  }

  OrderTerm asc({NullOrder? nulls}) => OrderTerm._(this, false, nulls);
  OrderTerm desc({NullOrder? nulls}) => OrderTerm._(this, true, nulls);
  CursorTerm cursor(T value, {bool descending = false, NullOrder? nulls}) =>
      CursorTerm._(OrderTerm._(this, descending, nulls), codec.encode(value));
  Expr<int> count({bool distinct = false}) =>
      Expr._(_Function('COUNT', [_node], distinct: distinct), Codecs.integer);
  Expr<T?> min() => Expr._(_Function('MIN', [_node]), codec.nullable());
  Expr<T?> max() => Expr._(_Function('MAX', [_node]), codec.nullable());
  @override
  _Decoder<T> _bind(_SelectionPlan plan) {
    if (plan.optionalDepth == 0 && !codec.acceptsNull) plan.required.add(this);
    final index = plan.column(this);
    return (row) => codec.decode(row[index]);
  }
}

Expr<T> value<T>(T value, Codec<T> codec) =>
    Expr._(_Parameter(codec.encode(value), sqlType: codec.sqlType), codec);

/// [parts] are trusted SQL, [values] are expressions. Never put user input in parts.
Expr<T> sql<T>(List<String> parts, List<Expr<Object?>> values, Codec<T> codec) {
  if (parts.length != values.length + 1) {
    throw ArgumentError('SQL needs one more text part than expression.');
  }
  return Expr._(_Raw(List.of(parts), [for (final v in values) v._node]), codec);
}

extension Predicate on Expr<bool?> {
  Expr<bool?> and(Expr<bool?> other) =>
      Expr._(_Binary(_node, 'AND', other._node), Codecs.boolean.nullable());
  Expr<bool?> or(Expr<bool?> other) =>
      Expr._(_Binary(_node, 'OR', other._node), Codecs.boolean.nullable());
  Expr<bool?> not() => Expr._(_Unary('NOT', _node), Codecs.boolean.nullable());
}

extension TextExpression on Expr<String> {
  Expr<bool?> like(String pattern) => _compare('LIKE', _Parameter(pattern));
  Expr<String> lower() => Expr._(_Function('LOWER', [_node]), Codecs.text);
  Expr<String> upper() => Expr._(_Function('UPPER', [_node]), Codecs.text);
}

extension NumericExpression<T extends num> on Expr<T> {
  Expr<T> plus(T n) =>
      Expr._(_Binary(_node, '+', _Parameter(codec.encode(n))), codec);
  Expr<T> minus(T n) =>
      Expr._(_Binary(_node, '-', _Parameter(codec.encode(n))), codec);
  Expr<T> times(T n) =>
      Expr._(_Binary(_node, '*', _Parameter(codec.encode(n))), codec);
  Expr<T?> sum() => Expr._(_Function('SUM', [_node]), codec.nullable());
  Expr<double?> average() =>
      Expr._(_Function('AVG', [_node]), Codecs.real.nullable());
}

final class OrderTerm {
  final Expr<Object?> expression;
  final bool descending;
  final NullOrder? nulls;
  const OrderTerm._(this.expression, this.descending, [this.nulls]);
  String _write(_Writer writer) =>
      '${expression._node.write(writer)} ${descending ? 'DESC' : 'ASC'}'
      '${nulls == null ? '' : ' NULLS ${nulls!.name.toUpperCase()}'}';
}
