part of '../orm.dart';

typedef _Decoder<T> = T Function(List<Object?> row);

abstract class Selection<T> {
  const Selection();
  _Decoder<T> _bind(_SelectionPlan plan);
  Selection<R> map<R>(R Function(T) mapper) => _Mapped(this, mapper);
}

final class _SelectionPlan {
  final List<Expr<Object?>> columns = [];
  final Map<_Node, int> _indices = {};
  int column(Expr<Object?> expression) =>
      _indices.putIfAbsent(expression._node, () {
        columns.add(expression);
        return columns.length - 1;
      });
}

final class _Mapped<T, R>(final Selection<T> source, final R Function(T) mapper)
    extends Selection<R> {
  @override
  _Decoder<R> _bind(_SelectionPlan plan) {
    final decode = source._bind(plan);
    return (row) => mapper(decode(row));
  }
}

final class _Combined<T>(
  final List<Selection<Object?>> sources,
  final T Function(List<Object?>) mapper,
) extends Selection<T> {
  @override
  _Decoder<T> _bind(_SelectionPlan plan) {
    final readers = [for (final source in sources) source._bind(plan)];
    return (row) => mapper([for (final read in readers) read(row)]);
  }
}

extension Selection2<A, B> on (Selection<A>, Selection<B>) {
  Selection<R> map<R>(R Function(A, B) mapper) =>
      _Combined([$1, $2], (v) => mapper(v[0] as A, v[1] as B));
}

extension Selection3<A, B, C> on (Selection<A>, Selection<B>, Selection<C>) {
  Selection<R> map<R>(R Function(A, B, C) mapper) =>
      _Combined([$1, $2, $3], (v) => mapper(v[0] as A, v[1] as B, v[2] as C));
}

extension Selection4<A, B, C, D>
    on (Selection<A>, Selection<B>, Selection<C>, Selection<D>) {
  Selection<R> map<R>(R Function(A, B, C, D) mapper) => _Combined([
    $1,
    $2,
    $3,
    $4,
  ], (v) => mapper(v[0] as A, v[1] as B, v[2] as C, v[3] as D));
}

extension Selection5<A, B, C, D, E>
    on (Selection<A>, Selection<B>, Selection<C>, Selection<D>, Selection<E>) {
  Selection<R> map<R>(R Function(A, B, C, D, E) mapper) => _Combined([
    $1,
    $2,
    $3,
    $4,
    $5,
  ], (v) => mapper(v[0] as A, v[1] as B, v[2] as C, v[3] as D, v[4] as E));
}

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
  Selection<R> map<R>(R Function(A, B, C, D, E, F) mapper) => _Combined(
    [$1, $2, $3, $4, $5, $6],
    (v) => mapper(
      v[0] as A,
      v[1] as B,
      v[2] as C,
      v[3] as D,
      v[4] as E,
      v[5] as F,
    ),
  );
}

/// Runtime field selection deliberately returns dynamic values.
Selection<Map<String, Object?>> fields(
  Map<String, Selection<Object?>> selected,
) {
  final entries = selected.entries.toList(growable: false);
  return _Combined(
    [for (final e in entries) e.value],
    (values) => {
      for (var i = 0; i < entries.length; i++) entries[i].key: values[i],
    },
  );
}
