part of '../sql.dart';

typedef _Decoder<T> = T Function(List<Object?> row);

abstract class Selection<T> {
  const Selection();
  _Decoder<T> _bind(_SelectionPlan plan);
  Selection<R> map<R>(R Function(T) mapper) => _Mapped(this, mapper);
}

final class _SelectionPlan {
  final bool deduplicate;
  _SelectionPlan({this.deduplicate = true});
  final List<Expr<Object?>> columns = [];
  final List<_RelationBinding> relations = [];
  final List<_Join> joins = [];
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

  _Decoder<T> optional<T>(TableRef table, Selection<T> selection) {
    final saved = _present;
    _present = {...saved, table};
    try {
      return selection._bind(this);
    } finally {
      _present = saved;
    }
  }

  final Map<_Node, int> _indices = {};
  int column(Expr<Object?> expression) {
    if (!deduplicate) {
      columns.add(expression);
      return columns.length - 1;
    }
    return _indices.putIfAbsent(expression._node, () {
      columns.add(expression);
      return columns.length - 1;
    });
  }
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
  final _Decoder<T> Function(List<_Decoder<Object?>>) combine,
) extends Selection<T> {
  @override
  _Decoder<T> _bind(_SelectionPlan plan) => combine(
    List.generate(
      sources.length,
      (i) => sources[i]._bind(plan),
      growable: false,
    ),
  );
}

extension Selection2<A, B> on (Selection<A>, Selection<B>) {
  Selection<R> map<R>(R Function(A, B) mapper) => _Combined(
    [$1, $2],
    (read) =>
        (row) => mapper(read[0](row) as A, read[1](row) as B),
  );
}

extension Selection3<A, B, C> on (Selection<A>, Selection<B>, Selection<C>) {
  Selection<R> map<R>(R Function(A, B, C) mapper) => _Combined(
    [$1, $2, $3],
    (read) =>
        (row) =>
            mapper(read[0](row) as A, read[1](row) as B, read[2](row) as C),
  );
}

extension Selection4<A, B, C, D>
    on (Selection<A>, Selection<B>, Selection<C>, Selection<D>) {
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

extension Selection5<A, B, C, D, E>
    on (Selection<A>, Selection<B>, Selection<C>, Selection<D>, Selection<E>) {
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
