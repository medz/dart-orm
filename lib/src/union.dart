part of '../sql.dart';

/// SQL records have no Dart mapping step. Set operations compare their stored
/// columns before any subsequent Record/DTO mapping.
final class _SqlRow<R>(
  final List<Expr<Object?>> columns,
  final R Function(List<Object?>) assemble,
) extends Selection<R> {
  @override
  _Decoder<R> _bind(_SelectionPlan plan) {
    final readers = [for (final column in columns) column._bind(plan)];
    return (row) => assemble([for (final read in readers) read(row)]);
  }
}

extension SqlRow2<A, B> on (Expr<A>, Expr<B>) {
  Selection<(A, B)> get row => _SqlRow([$1, $2], (v) => (v[0] as A, v[1] as B));
}

extension SqlRow3<A, B, C> on (Expr<A>, Expr<B>, Expr<C>) {
  Selection<(A, B, C)> get row =>
      _SqlRow([$1, $2, $3], (v) => (v[0] as A, v[1] as B, v[2] as C));
}

extension SqlRow4<A, B, C, D> on (Expr<A>, Expr<B>, Expr<C>, Expr<D>) {
  Selection<(A, B, C, D)> get row => _SqlRow([
    $1,
    $2,
    $3,
    $4,
  ], (v) => (v[0] as A, v[1] as B, v[2] as C, v[3] as D));
}

extension SqlRow5<A, B, C, D, E>
    on (Expr<A>, Expr<B>, Expr<C>, Expr<D>, Expr<E>) {
  Selection<(A, B, C, D, E)> get row => _SqlRow([
    $1,
    $2,
    $3,
    $4,
    $5,
  ], (v) => (v[0] as A, v[1] as B, v[2] as C, v[3] as D, v[4] as E));
}

extension SqlRow6<A, B, C, D, E, F>
    on (Expr<A>, Expr<B>, Expr<C>, Expr<D>, Expr<E>, Expr<F>) {
  Selection<(A, B, C, D, E, F)> get row => _SqlRow([
    $1,
    $2,
    $3,
    $4,
    $5,
    $6,
  ], (v) => (v[0] as A, v[1] as B, v[2] as C, v[3] as D, v[4] as E, v[5] as F));
}

extension SetQueries<R, F extends Fields> on Query<R, F> {
  /// Combines SQL scalars or `.row` projections. Both operands must use this
  /// database/session and the same codecs, column types and nullability.
  Query<R, UnionFields<F>> union<G extends Fields>(Query<R, G> other) =>
      _union(other, all: false);

  /// Keeps duplicate SQL rows. Row order requires an explicit final orderBy.
  Query<R, UnionFields<F>> unionAll<G extends Fields>(Query<R, G> other) =>
      _union(other, all: true);

  Query<R, UnionFields<F>> _union<G extends Fields>(
    Query<R, G> other, {
    required bool all,
  }) {
    if (!identical(database, other.database)) {
      throw const OrmException(
        'QUERY.UNION_SESSION',
        'UNION operands must use the same database/session.',
      );
    }
    final shape = _sqlRowShape(_selection);
    if (shape == null || shape != _sqlRowShape(other._selection)) {
      throw const OrmException(
        'QUERY.UNION_SELECTION',
        'Select SQL expressions or matching .row records. Map after UNION.',
      );
    }
    // SQL set columns are positional: selecting (id, id) still exports two.
    final (left, decode) = _plan(deduplicate: false);
    if ((database.dialect == SqlDialect.mysql ||
            database.dialect == SqlDialect.mariadb) &&
        left.columns.any((e) => e.codec.sqlType == 'decimal')) {
      throw const OrmException(
        'CAPABILITY.DECIMAL_PRECISION',
        'MySQL/MariaDB decimal UNION may silently narrow mixed precision; use explicit native SQL when its precision is acceptable.',
      );
    }
    final (right, _) = other._plan(deduplicate: false);
    if (left.columns.length != right.columns.length ||
        left.relations.isNotEmpty ||
        right.relations.isNotEmpty) {
      throw const OrmException(
        'QUERY.UNION_SELECTION',
        'UNION requires matching SQL columns.',
      );
    }
    for (var i = 0; i < left.columns.length; i++) {
      final a = left.columns[i].codec;
      final b = right.columns[i].codec;
      if (!a.sameStorageAs(b) || a.acceptsNull != b.acceptsNull) {
        throw OrmException(
          'QUERY.UNION_CODEC',
          'UNION column ${i + 1} requires the same codec and nullability.',
        );
      }
    }
    final table = TableRef(
      TableSchema(
        '_orm_union',
        columns: [
          for (var i = 0; i < left.columns.length; i++)
            Column(
              'c$i',
              left.columns[i].codec,
              nullable: left.columns[i].codec.acceptsNull,
            ),
        ],
      ),
    );
    final fields = UnionFields._(table, _fields, left);
    final columns = [
      for (var i = 0; i < left.columns.length; i++)
        Expr._(_ColumnNode(table, 'c$i'), left.columns[i].codec),
    ];
    // A scalar remains an Expr, so scalar()/isInQuery() compose unchanged.
    final Selection<R> selection = shape == 0
        ? Expr._(columns.single._node, left.columns.single.codec as Codec<R>)
        : _ReboundSelection(decode, columns, source: _selection);
    return Query._(
      database,
      fields,
      _QueryState(table, union: _UnionSource(this, left, other, right, all)),
      selection,
    );
  }
}

int? _sqlRowShape(Selection<Object?> selection) => switch (selection) {
  Expr() => 0,
  _SqlRow(:final columns) => columns.length,
  _ReboundSelection(:final source?) => _sqlRowShape(source),
  _ => null,
};

/// References refer to the left operand's exported SQL expressions.
final class UnionFields<F extends Fields> extends Fields {
  final F _original;
  final _SelectionPlan _plan;
  UnionFields._(super.table, this._original, this._plan);

  Expr<T> ref<T>(Expr<T> Function(F) expression) {
    final original = expression(_original);
    final index = _plan.columns.indexWhere(
      (e) => _sameSqlNode(e._node, original._node),
    );
    if (index < 0) {
      throw const OrmException(
        'QUERY.UNION_COLUMN',
        'UNION did not export this SQL expression.',
      );
    }
    if (_plan.columns[index].codec.acceptsNull && !original.codec.acceptsNull) {
      throw const OrmException(
        'QUERY.NULLABILITY',
        'Reference this UNION column with a nullable expression.',
      );
    }
    if (!_plan.columns[index].codec.sameStorageAs(original.codec)) {
      throw const OrmException(
        'QUERY.UNION_CODEC',
        'Reference the exported UNION codec.',
      );
    }
    return Expr._(_ColumnNode(table, 'c$index'), original.codec);
  }
}

final class _UnionSource(
  final Query<Object?, Fields> left,
  final _SelectionPlan leftPlan,
  final Query<Object?, Fields> right,
  final _SelectionPlan rightPlan,
  final bool all,
) {
  String write(_Writer w) =>
      'SELECT * FROM (${left._write(w, leftPlan, aliasColumns: true)}) AS ${w.quote('_union_left')} '
      'UNION${all ? ' ALL' : ''} '
      'SELECT * FROM (${right._write(w, rightPlan, aliasColumns: true)}) AS ${w.quote('_union_right')}';
}
