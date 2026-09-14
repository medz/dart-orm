part of '../orm.dart';

/// Explicit aliases support self joins and any number of joins without adding
/// a growing number of generic join-result types.
final class TableAlias<R, F extends Fields> {
  final Table<R, F> definition;
  final F fields;
  final _CteDefinition? _cte;
  late final String _marker = _presenceName();
  TableAlias._(this.definition, [this._cte])
    : fields = definition.createFields(TableRef(definition.schema));
  String _presenceName() {
    var name = '_orm_present';
    while (definition.schema.columns.any((c) => c.name.toLowerCase() == name)) {
      name += '_';
    }
    return name;
  }

  Selection<T?> optional<T>(Selection<T> selection) =>
      _OptionalJoin(this, selection);
  Selection<R?> get row => optional(definition.selectRow(fields));
  Expr<T?> nullable<T>(Expr<T> expression) =>
      Expr._(expression._node, expression.codec.nullable());
  Expr<bool> get isPresent =>
      Expr._(_Presence(this), Codecs.integer.nullable()).isNotNull();
}

final class _Join(
  final TableAlias<Object?, Fields> alias,
  final Expr<bool?> on,
  final bool left,
);

final class _Presence(final TableAlias<Object?, Fields> alias) extends _Node {
  @override
  String write(_Writer w) {
    if (!w.leftJoins.contains(alias.fields.table)) {
      throw const OrmException(
        'QUERY.OUTER_JOIN',
        'Optional projections require this alias to be left joined.',
      );
    }
    return '${w.quote(w.aliases[alias.fields.table]!)}.${w.quote(alias._marker)}';
  }
}

final class _OptionalJoin<T>(
  final TableAlias<Object?, Fields> alias,
  final Selection<T> selection,
) extends Selection<T?> {
  @override
  _Decoder<T?> _bind(_SelectionPlan plan) {
    final marker = plan.column(
      Expr._(_Presence(alias), Codecs.integer.nullable()),
    );
    plan.optionalDepth++;
    late _Decoder<T> decode;
    try {
      decode = selection._bind(plan);
    } finally {
      plan.optionalDepth--;
    }
    return (row) => row[marker] == null ? null : decode(row);
  }
}

final class _Subquery(
  final Query<Object?, Fields> query, {
  final bool exists = false,
}) extends _Node {
  @override
  String write(_Writer w) {
    final (plan, _) = query._plan();
    if (plan.relations.isNotEmpty) {
      throw const OrmException(
        'QUERY.SUBQUERY',
        'SQL subqueries cannot include batch-loaded relations.',
      );
    }
    if (w.dialect != query.database.dialect) {
      throw const OrmException(
        'QUERY.DIALECT',
        'Subqueries must use the enclosing SQL dialect.',
      );
    }
    return '${exists ? 'EXISTS ' : ''}(${query._write(w, plan)})';
  }
}

enum WindowFrame { rowsToCurrent, rowsAll, rangeToCurrent }

Expr<int> rowNumber({
  List<Expr<Object?>> partitionBy = const [],
  List<OrderTerm> orderBy = const [],
}) => Expr._(
  _WindowNode(
    _Function('ROW_NUMBER', const []),
    List.unmodifiable(partitionBy),
    List.unmodifiable(orderBy),
    null,
  ),
  Codecs.integer,
);
Expr<int> rank({
  List<Expr<Object?>> partitionBy = const [],
  required List<OrderTerm> orderBy,
}) => Expr._(
  _WindowNode(
    _Function('RANK', const []),
    List.unmodifiable(partitionBy),
    List.unmodifiable(orderBy),
    null,
  ),
  Codecs.integer,
);

final class _WindowNode(
  final _Node function,
  final List<Expr<Object?>> partition,
  final List<OrderTerm> order,
  final WindowFrame? frame,
) extends _Node {
  @override
  String write(_Writer w) {
    final clauses = <String>[];
    if (partition.isNotEmpty) {
      clauses.add(
        'PARTITION BY ${partition.map((e) => e._node.write(w)).join(', ')}',
      );
    }
    if (order.isNotEmpty) {
      clauses.add('ORDER BY ${order.map((o) => o._write(w)).join(', ')}');
    }
    if (frame != null) {
      clauses.add(switch (frame!) {
        WindowFrame.rowsToCurrent =>
          'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW',
        WindowFrame.rowsAll =>
          'ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING',
        WindowFrame.rangeToCurrent =>
          'RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW',
      });
    }
    return '${function.write(w)} OVER (${clauses.join(' ')})';
  }
}

bool _aggregate(_Node node) => switch (node) {
  _WindowNode() || _Subquery() || _RelationSubquery() => false,
  _Function(:final name)
      when {'COUNT', 'SUM', 'MIN', 'MAX', 'AVG'}.contains(name) =>
    true,
  _ => _children(node).any(_aggregate),
};
bool _window(_Node node) => node is _WindowNode || _children(node).any(_window);
List<_Node> _children(_Node node) => switch (node) {
  _DecimalNode(:final child) => [child],
  _DecimalArithmetic(:final left, :final right) => [left, right],
  _Binary(:final left, :final right) => [left, right],
  _Unary(:final child) => [child],
  _Function(:final arguments) => arguments,
  _In(:final expression, :final values) => [expression, ...values],
  _Raw(:final values) => values,
  _WindowNode(:final function, :final partition, :final order) => [
    function,
    ...partition.map((e) => e._node),
    ...order.map((e) => e.expression._node),
  ],
  _RelationSubquery(:final relation) => [
    for (final p in relation._parent) p._node,
  ],
  _ => [],
};

void _validateGrouping(_QueryState state, _SelectionPlan plan) {
  final optional = {
    for (final join in state.joins)
      if (join.left) join.alias.fields.table,
  };
  if (plan.required.any((e) => _outerNullable(e._node, optional))) {
    throw const OrmException(
      'QUERY.NULLABILITY',
      'Use alias.optional(selection) or alias.nullable(expression) for outer-joined fields.',
    );
  }
  final predicates = [
    if (state.predicate case final p?) p._node,
    for (final j in state.joins) j.on._node,
  ];
  if (predicates.any((p) => _aggregate(p) || _window(p))) {
    throw const OrmException(
      'QUERY.AGGREGATE',
      'WHERE and JOIN predicates cannot contain aggregate or window functions.',
    );
  }
  if (state.group.any((e) => _aggregate(e._node) || _window(e._node)) ||
      (state.having != null && _window(state.having!._node))) {
    throw const OrmException(
      'QUERY.AGGREGATE',
      'Invalid aggregate/window placement.',
    );
  }
  final checked = [
    for (final e in plan.columns) e._node,
    for (final o in state.order) o.expression._node,
    if (state.having case final h?) h._node,
  ];
  if (state.group.isEmpty && !checked.any(_aggregate)) {
    if (state.having != null) {
      throw const OrmException(
        'QUERY.AGGREGATE',
        'HAVING requires grouping or aggregation.',
      );
    }
    return;
  }
  bool grouped(_Node node) {
    if (state.group.any((g) => _sameSqlNode(g._node, node))) return true;
    if (node is _Function &&
        {'COUNT', 'SUM', 'MIN', 'MAX', 'AVG'}.contains(node.name)) {
      return true;
    }
    if (node is _ColumnNode || node is _Presence) return false;
    if (node is _WindowNode) {
      return [
        ..._children(node.function),
        ...node.partition.map((e) => e._node),
        ...node.order.map((e) => e.expression._node),
      ].every(grouped);
    }
    return _children(node).every(grouped);
  }

  if (!checked.every(grouped)) {
    throw const OrmException(
      'QUERY.GROUPING',
      'Select grouped expressions or aggregates; ungrouped columns are ambiguous.',
    );
  }
}

bool _outerNullable(_Node node, Set<TableRef> optional) => switch (node) {
  _ColumnNode(:final table) => optional.contains(table),
  _WindowNode() || _Raw() => false,
  _Function(name: 'COUNT') => false,
  _Unary(op: 'IS NULL' || 'IS NOT NULL') => false,
  _ => _children(node).any((child) => _outerNullable(child, optional)),
};

bool _sameSqlNode(_Node a, _Node b) {
  if (identical(a, b)) return true;
  return switch ((a, b)) {
    (_DecimalNode(child: final ac), _DecimalNode(child: final bc)) =>
      _sameSqlNode(ac, bc),
    (
      _DecimalArithmetic(left: final al, op: final ao, right: final ar),
      _DecimalArithmetic(left: final bl, op: final bo, right: final br),
    ) =>
      ao == bo && _sameSqlNode(al, bl) && _sameSqlNode(ar, br),
    (
      _ColumnNode(table: final at, name: final an),
      _ColumnNode(table: final bt, name: final bn),
    ) =>
      at == bt && an == bn,
    (
      _Parameter(value: final av, sqlType: final at),
      _Parameter(value: final bv, sqlType: final bt),
    ) =>
      av == bv && at == bt,
    (
      _Function(
        name: final an,
        arguments: final aa,
        distinct: final ad,
        decimal: final ax,
      ),
      _Function(
        name: final bn,
        arguments: final ba,
        distinct: final bd,
        decimal: final bx,
      ),
    ) =>
      an == bn &&
          ax == bx &&
          ad == bd &&
          aa.length == ba.length &&
          aa.indexed.every((e) => _sameSqlNode(e.$2, ba[e.$1])),
    (
      _Binary(left: final al, op: final ao, right: final ar),
      _Binary(left: final bl, op: final bo, right: final br),
    ) =>
      ao == bo && _sameSqlNode(al, bl) && _sameSqlNode(ar, br),
    _ => false,
  };
}
