import 'package:meta/meta.dart';

import '../../driver.dart';
import '../../schema_model.dart';
import 'cte.dart';
import 'expression.dart';
import 'nodes.dart';
import 'query.dart';
import 'selection.dart';
import 'table.dart';

/// Explicit aliases support self joins and any number of joins without adding
/// a growing number of generic join-result types.
final class TableAlias<R, F extends Fields> {
  /// Physical table and row decoder represented by this occurrence.
  final Table<R, F> definition;

  /// Fields scoped to this occurrence, independent of another alias of the table.
  final F fields;

  /// @nodoc
  @internal
  final CteDefinition? cteDefinition;

  /// @nodoc
  @internal
  late final String presenceMarker = _presenceName();

  /// @nodoc
  @internal
  TableAlias.internal(this.definition, [this.cteDefinition])
    : fields = definition.createFields(TableRef(definition.schema));
  String _presenceName() {
    var name = '_orm_present';
    while (definition.schema.columns.any((c) => c.name.toLowerCase() == name)) {
      name += '_';
    }
    return name;
  }

  /// Decodes [selection] only when this alias is present in a joined row.
  ///
  /// A missing left-joined row produces null. This guard establishes presence
  /// only for this alias; independently optional aliases need their own guards.
  Selection<T?> optional<T>(Selection<T> selection) =>
      _OptionalJoin(this, selection);

  /// Selects the complete model row, or null when this alias is absent.
  Selection<R?> get row => optional(definition.selectRow(fields));

  /// Decodes a SQL expression as nullable, including an absent left-join value.
  ///
  /// This changes the result codec without adding an SQL presence test.
  Expr<T?> nullable<T>(Expr<T> expression) =>
      Expr.internal(expression.expressionNode, expression.codec.nullable());

  /// SQL expression testing whether this joined occurrence has a row.
  Expr<bool> get isPresent =>
      Expr.internal(PresenceNode(this), Codecs.integer.nullable()).isNotNull();
}

/// @nodoc
@internal
final class Join(
  final TableAlias<Object?, Fields> alias,
  final Expr<bool?> on,
  final bool left,
);

final class _OptionalJoin<T>(
  final TableAlias<Object?, Fields> alias,
  final Selection<T> selection,
) extends Selection<T?> {
  /// @nodoc
  @internal
  @override
  RowDecoder<T?> bindSelection(SelectionPlan plan) {
    final marker = plan.column(
      Expr.internal(PresenceNode(alias), Codecs.integer.nullable()),
    );
    final decode = plan.optional(alias.fields.table, selection);
    return (row) => row[marker] == null ? null : decode(row);
  }
}

/// Frame used by a window aggregate.
///
/// [rowsToCurrent] includes rows from the partition's start through this row;
/// [rowsAll] includes the whole partition. [rangeToCurrent] also includes peers
/// equal under the window ordering.
enum WindowFrame { rowsToCurrent, rowsAll, rangeToCurrent }

/// Builds a one-based SQL row number within each partition.
///
/// Supply [orderBy] for deterministic numbering; this does not order the final
/// query result unless that query also declares its own ordering.
Expr<int> rowNumber({
  List<Expr<Object?>> partitionBy = const [],
  List<OrderTerm> orderBy = const [],
}) => Expr.internal(
  WindowNode(
    FunctionNode('ROW_NUMBER', const []),
    List.unmodifiable(partitionBy),
    List.unmodifiable(orderBy),
    null,
  ),
  Codecs.integer,
);

/// Builds one-based SQL rank, with ties sharing a rank and leaving later gaps.
///
/// Partition and ordering expressions belong to the surrounding query scope.
Expr<int> rank({
  List<Expr<Object?>> partitionBy = const [],
  required List<OrderTerm> orderBy,
}) => Expr.internal(
  WindowNode(
    FunctionNode('RANK', const []),
    List.unmodifiable(partitionBy),
    List.unmodifiable(orderBy),
    null,
  ),
  Codecs.integer,
);

/// @nodoc
@internal
bool aggregate(SqlNode node) => switch (node) {
  WindowNode() || SubqueryNode() || RelationSubqueryNode() => false,
  DecimalAverage() => true,
  FunctionNode(:final name)
      when {'COUNT', 'SUM', 'MIN', 'MAX', 'AVG'}.contains(name) =>
    true,
  _ => children(node).any(aggregate),
};

/// @nodoc
@internal
bool window(SqlNode node) => node is WindowNode || children(node).any(window);

/// @nodoc
@internal
List<SqlNode> children(SqlNode node) => switch (node) {
  TemporalNode(:final child) || TemporalCast(:final child) => [child],
  DecimalAverage(:final child) || AverageInput(:final child) => [child],
  DecimalRatio(:final numerator, :final divisor) => [numerator, ?divisor],
  DecimalNode(:final child) => [child],
  DecimalCast(:final child) => [child],
  DecimalArithmetic(:final left, :final right) => [left, right],
  BinaryNode(:final left, :final right) => [left, right],
  UnaryNode(:final child) => [child],
  FunctionNode(:final arguments) => arguments,
  InNode(:final expression, :final values) => [expression, ...values],
  RawNode(:final values) => values,
  WindowNode(:final function, :final partition, :final order) => [
    function,
    ...partition.map((e) => e.expressionNode),
    ...order.map((e) => e.expression.expressionNode),
  ],
  RelationSubqueryNode(:final relation) => [
    for (final p in relation.parentFields) p.expressionNode,
  ],
  _ => [],
};

/// @nodoc
@internal
void validateGrouping(QueryState state, SelectionPlan plan) {
  final optional = {
    for (final join in state.joins)
      if (join.left) join.alias.fields.table,
  };
  bool unguarded(MapEntry<Set<TableRef>, List<Expr<Object?>>> entry) {
    final absent = optional.difference(entry.key);
    return entry.value.any((e) => outerNullable(e.expressionNode, absent));
  }

  if (plan.required.any((e) => outerNullable(e.expressionNode, optional)) ||
      plan.guarded.entries.any(unguarded)) {
    throw const OrmException(
      'QUERY.NULLABILITY',
      'Use alias.optional(selection) or alias.nullable(expression) for outer-joined fields.',
    );
  }
  final predicates = [
    if (state.predicate case final p?) p.expressionNode,
    for (final j in state.joins) j.on.expressionNode,
  ];
  if (predicates.any((p) => aggregate(p) || window(p))) {
    throw const OrmException(
      'QUERY.AGGREGATE',
      'WHERE and JOIN predicates cannot contain aggregate or window functions.',
    );
  }
  if (state.group.any(
        (e) => aggregate(e.expressionNode) || window(e.expressionNode),
      ) ||
      (state.having != null && window(state.having!.expressionNode))) {
    throw const OrmException(
      'QUERY.AGGREGATE',
      'Invalid aggregate/window placement.',
    );
  }
  final checked = [
    for (final e in plan.columns) e.expressionNode,
    for (final o in state.order) o.expression.expressionNode,
    if (state.having case final h?) h.expressionNode,
  ];
  if (state.group.isEmpty && !checked.any(aggregate)) {
    if (state.having != null) {
      throw const OrmException(
        'QUERY.AGGREGATE',
        'HAVING requires grouping or aggregation.',
      );
    }
    return;
  }
  bool grouped(SqlNode node) {
    if (state.group.any((g) => sameSqlNode(g.expressionNode, node))) {
      return true;
    }
    if (node is DecimalAverage) return true;
    if (node is FunctionNode &&
        {'COUNT', 'SUM', 'MIN', 'MAX', 'AVG'}.contains(node.name)) {
      return true;
    }
    if (node is ColumnNode || node is PresenceNode) return false;
    if (node is WindowNode) {
      return [
        ...children(node.function),
        ...node.partition.map((e) => e.expressionNode),
        ...node.order.map((e) => e.expression.expressionNode),
      ].every(grouped);
    }
    return children(node).every(grouped);
  }

  if (!checked.every(grouped)) {
    throw const OrmException(
      'QUERY.GROUPING',
      'Select grouped expressions or aggregates; ungrouped columns are ambiguous.',
    );
  }
}

/// @nodoc
@internal
bool outerNullable(SqlNode node, Set<TableRef> optional) => switch (node) {
  ColumnNode(:final table) => optional.contains(table),
  WindowNode() || RawNode() => false,
  FunctionNode(name: 'COUNT') => false,
  UnaryNode(op: 'IS NULL' || 'IS NOT NULL') => false,
  _ => children(node).any((child) => outerNullable(child, optional)),
};

/// @nodoc
@internal
bool sameSqlNode(SqlNode a, SqlNode b) {
  if (identical(a, b)) return true;
  if (a is WindowNode && b is WindowNode) {
    return a.frame == b.frame &&
        sameSqlNode(a.function, b.function) &&
        a.partition.length == b.partition.length &&
        a.partition.indexed.every(
          (e) => sameSqlNode(
            e.$2.expressionNode,
            b.partition[e.$1].expressionNode,
          ),
        ) &&
        a.order.length == b.order.length &&
        a.order.indexed.every((e) {
          final other = b.order[e.$1];
          return e.$2.descending == other.descending &&
              e.$2.nulls == other.nulls &&
              sameSqlNode(
                e.$2.expression.expressionNode,
                other.expression.expressionNode,
              );
        });
  }
  return switch ((a, b)) {
    (
      TemporalNode(child: final ac, kind: final ak),
      TemporalNode(child: final bc, kind: final bk),
    ) =>
      ak == bk && sameSqlNode(ac, bc),
    (
      DecimalAverage(child: final ac, scale: final ax, rounding: final ar),
      DecimalAverage(child: final bc, scale: final bx, rounding: final br),
    ) =>
      ax == bx && ar == br && sameSqlNode(ac, bc),
    (
      DecimalRatio(
        numerator: final an,
        divisor: final ad,
        scale: final ax,
        rounding: final ar,
      ),
      DecimalRatio(
        numerator: final bn,
        divisor: final bd,
        scale: final bx,
        rounding: final br,
      ),
    ) =>
      ax == bx &&
          ar == br &&
          sameSqlNode(an, bn) &&
          (ad == null ? bd == null : bd != null && sameSqlNode(ad, bd)),
    (
      DecimalCast(child: final ac, precision: final ap, scale: final asc),
      DecimalCast(child: final bc, precision: final bp, scale: final bs),
    ) =>
      ap == bp && asc == bs && sameSqlNode(ac, bc),
    (
      TemporalCast(child: final ac, kind: final ak, digits: final ap),
      TemporalCast(child: final bc, kind: final bk, digits: final bp),
    ) =>
      ak == bk && ap == bp && sameSqlNode(ac, bc),
    (DecimalNode(child: final ac), DecimalNode(child: final bc)) => sameSqlNode(
      ac,
      bc,
    ),
    (
      DecimalArithmetic(left: final al, op: final ao, right: final ar),
      DecimalArithmetic(left: final bl, op: final bo, right: final br),
    ) =>
      ao == bo && sameSqlNode(al, bl) && sameSqlNode(ar, br),
    (
      ColumnNode(table: final at, name: final an),
      ColumnNode(table: final bt, name: final bn),
    ) =>
      at == bt && an == bn,
    (
      ParameterNode(value: final av, sqlType: final at),
      ParameterNode(value: final bv, sqlType: final bt),
    ) =>
      av == bv && at == bt,
    (
      FunctionNode(
        name: final an,
        arguments: final aa,
        distinct: final ad,
        decimal: final ax,
      ),
      FunctionNode(
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
          aa.indexed.every((e) => sameSqlNode(e.$2, ba[e.$1])),
    (
      BinaryNode(left: final al, op: final ao, right: final ar),
      BinaryNode(left: final bl, op: final bo, right: final br),
    ) =>
      ao == bo && sameSqlNode(al, bl) && sameSqlNode(ar, br),
    _ => false,
  };
}
