import 'package:meta/meta.dart';

import 'expression.dart';
import 'joins.dart';
import 'nodes.dart';
import 'relation.dart';
import 'table.dart';

/// @nodoc
@internal
typedef RowDecoder<T> = T Function(List<Object?> row);

/// A typed result description decoded when its containing query executes.
///
/// SQL expressions are scalar selections. Record composition and [map] combine
/// decoded values into application results without evaluating Dart code in SQL.
abstract class Selection<T> {
  /// Base constructor for typed projections and their Dart result mappings.
  const Selection();

  /// @nodoc
  @internal
  RowDecoder<T> bindSelection(SelectionPlan plan);

  /// Maps each decoded value in Dart, preserving the source SQL projection.
  ///
  /// The mapper runs during decoding, not during query construction. Its result
  /// does not become a SQL expression for filtering, grouping, or set operations.
  Selection<R> map<R>(R Function(T) mapper) => _Mapped(this, mapper);
}

/// @nodoc
@internal
final class SelectionPlan {
  final bool deduplicate;
  SelectionPlan({this.deduplicate = true});
  final List<Expr<Object?>> columns = [];
  final List<RelationBinding> relations = [];
  final List<Join> joins = [];
  final List<Expr<Object?>> required = [];
  final Map<Set<TableRef>, List<Expr<Object?>>> guarded = {};
  Set<TableRef> _present = const {};
  void require(Expr<Object?> expression) {
    if (expression.codec.acceptsNull) return;
    if (_present.isEmpty) {
      required.add(expression);
    } else {
      (guarded[_present] ??= []).add(expression);
    }
  }

  RowDecoder<T> optional<T>(TableRef table, Selection<T> selection) {
    final saved = _present;
    _present = {...saved, table};
    try {
      return selection.bindSelection(this);
    } finally {
      _present = saved;
    }
  }

  final Map<SqlNode, int> _indices = {};
  int column(Expr<Object?> expression) {
    if (!deduplicate) {
      columns.add(expression);
      return columns.length - 1;
    }
    return _indices.putIfAbsent(expression.expressionNode, () {
      columns.add(expression);
      return columns.length - 1;
    });
  }
}

final class _Mapped<T, R>(final Selection<T> source, final R Function(T) mapper)
    extends Selection<R> {
  /// @nodoc
  @internal
  @override
  RowDecoder<R> bindSelection(SelectionPlan plan) {
    final decode = source.bindSelection(plan);
    return (row) => mapper(decode(row));
  }
}

final class _Combined<T>(
  final List<Selection<Object?>> sources,
  final RowDecoder<T> Function(List<RowDecoder<Object?>>) combine,
) extends Selection<T> {
  /// @nodoc
  @internal
  @override
  RowDecoder<T> bindSelection(SelectionPlan plan) => combine(
    List.generate(
      sources.length,
      (i) => sources[i].bindSelection(plan),
      growable: false,
    ),
  );
}

/// Composes two independently typed selections into one decoded result.
extension Selection2<A, B> on (Selection<A>, Selection<B>) {
  /// Maps the two decoded values in Dart without changing their SQL meaning.
  Selection<R> map<R>(R Function(A, B) mapper) => _Combined(
    [$1, $2],
    (read) =>
        (row) => mapper(read[0](row) as A, read[1](row) as B),
  );
}

/// Composes three independently typed selections into one decoded result.
extension Selection3<A, B, C> on (Selection<A>, Selection<B>, Selection<C>) {
  /// Maps the three decoded values in Dart after the query executes.
  Selection<R> map<R>(R Function(A, B, C) mapper) => _Combined(
    [$1, $2, $3],
    (read) =>
        (row) =>
            mapper(read[0](row) as A, read[1](row) as B, read[2](row) as C),
  );
}

/// Composes four independently typed selections into one decoded result.
extension Selection4<A, B, C, D>
    on (Selection<A>, Selection<B>, Selection<C>, Selection<D>) {
  /// Maps the four decoded values in Dart after the query executes.
  Selection<R> map<R>(R Function(A, B, C, D) mapper) => _Combined(
    [$1, $2, $3, $4],
    (read) =>
        (row) => mapper(
          read[0](row) as A,
          read[1](row) as B,
          read[2](row) as C,
          read[3](row) as D,
        ),
  );
}

/// Composes five independently typed selections into one decoded result.
extension Selection5<A, B, C, D, E>
    on (Selection<A>, Selection<B>, Selection<C>, Selection<D>, Selection<E>) {
  /// Maps the five decoded values in Dart after the query executes.
  Selection<R> map<R>(R Function(A, B, C, D, E) mapper) => _Combined(
    [$1, $2, $3, $4, $5],
    (read) =>
        (row) => mapper(
          read[0](row) as A,
          read[1](row) as B,
          read[2](row) as C,
          read[3](row) as D,
          read[4](row) as E,
        ),
  );
}

/// Composes six independently typed selections into one decoded result.
extension Selection6<A, B, C, D, E, F>
    on
        (
          Selection<A>,
          Selection<B>,
          Selection<C>,
          Selection<D>,
          Selection<E>,
          Selection<F>,
        ) {
  /// Maps the six decoded values in Dart after the query executes.
  Selection<R> map<R>(R Function(A, B, C, D, E, F) mapper) => _Combined(
    [$1, $2, $3, $4, $5, $6],
    (read) =>
        (row) => mapper(
          read[0](row) as A,
          read[1](row) as B,
          read[2](row) as C,
          read[3](row) as D,
          read[4](row) as E,
          read[5](row) as F,
        ),
  );
}

/// Runtime field selection deliberately returns dynamic values.
///
/// Captures the selected names and projections now and builds a map for each
/// decoded row. Use a scalar or Record selection when result fields are known
/// statically and their individual Dart types should be preserved.
Selection<Map<String, Object?>> fields(
  Map<String, Selection<Object?>> selected,
) {
  final entries = selected.entries.toList(growable: false);
  return _Combined(
    [for (final e in entries) e.value],
    (read) =>
        (row) => {
          for (var i = 0; i < entries.length; i++) entries[i].key: read[i](row),
        },
  );
}
