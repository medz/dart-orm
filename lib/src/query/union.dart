import 'package:meta/meta.dart';

import '../../schema_model.dart';
import 'cte.dart';
import 'expression.dart';
import 'joins.dart';
import 'nodes.dart';
import 'query.dart';
import 'selection.dart';
import 'table.dart';

/// SQL records have no Dart mapping step. Set operations compare their stored
/// columns before any subsequent Record/DTO mapping.
final class _SqlRow<R>(
  final List<Expr<Object?>> columns,
  final R Function(List<Object?>) assemble,
) extends Selection<R> {
  /// @nodoc
  @internal
  @override
  RowDecoder<R> bindSelection(SelectionPlan plan) {
    final readers = [for (final column in columns) column.bindSelection(plan)];
    return (row) => assemble([for (final read in readers) read(row)]);
  }
}

/// Projects two SQL expressions as a positional Dart Record.
extension SqlRow2<A, B> on (Expr<A>, Expr<B>) {
  /// Keeps both SQL columns available for DISTINCT, CTEs, and set operations.
  Selection<(A, B)> get row => _SqlRow([$1, $2], (v) => (v[0] as A, v[1] as B));
}

/// Projects three SQL expressions as a positional Dart Record.
extension SqlRow3<A, B, C> on (Expr<A>, Expr<B>, Expr<C>) {
  /// Preserves column positions and individual nullability in the result.
  Selection<(A, B, C)> get row =>
      _SqlRow([$1, $2, $3], (v) => (v[0] as A, v[1] as B, v[2] as C));
}

/// Projects four SQL expressions as a positional Dart Record.
extension SqlRow4<A, B, C, D> on (Expr<A>, Expr<B>, Expr<C>, Expr<D>) {
  /// Preserves column positions and individual nullability in the result.
  Selection<(A, B, C, D)> get row => _SqlRow([
    $1,
    $2,
    $3,
    $4,
  ], (v) => (v[0] as A, v[1] as B, v[2] as C, v[3] as D));
}

/// Projects five SQL expressions as a positional Dart Record.
extension SqlRow5<A, B, C, D, E>
    on (Expr<A>, Expr<B>, Expr<C>, Expr<D>, Expr<E>) {
  /// Preserves column positions and individual nullability in the result.
  Selection<(A, B, C, D, E)> get row => _SqlRow([
    $1,
    $2,
    $3,
    $4,
    $5,
  ], (v) => (v[0] as A, v[1] as B, v[2] as C, v[3] as D, v[4] as E));
}

/// Projects six SQL expressions as a positional Dart Record.
extension SqlRow6<A, B, C, D, E, F>
    on (Expr<A>, Expr<B>, Expr<C>, Expr<D>, Expr<E>, Expr<F>) {
  /// Preserves column positions and individual nullability in the result.
  Selection<(A, B, C, D, E, F)> get row => _SqlRow([
    $1,
    $2,
    $3,
    $4,
    $5,
    $6,
  ], (v) => (v[0] as A, v[1] as B, v[2] as C, v[3] as D, v[4] as E, v[5] as F));
}

/// SQL set operations over matching scalar or positional Record projections.
///
/// Both operands must belong to the same database or transaction context. Apply
/// Dart mapping after combining SQL rows; a DTO mapper does not define SQL set
/// equality. Constructing a set query performs no database I/O.
extension SetQueries<R, F extends Fields> on Query<R, F> {
  /// Combines SQL scalars or `.row` projections. Both operands must use this
  /// database/session and the same codecs, column types and nullability.
  ///
  /// SQL UNION removes duplicate projected rows. Declare ordering on the
  /// resulting query when result order matters.
  Query<R, UnionFields<F>> union<G extends Fields>(Query<R, G> other) =>
      _union(other, all: false);

  /// Keeps duplicate SQL rows. Row order requires an explicit final orderBy.
  ///
  /// The same column, codec, nullability, and context requirements as [union]
  /// apply; this describes one SQL set operation, not two Dart list reads.
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
    final shape = sqlRowShape(querySelection);
    if (shape == null || shape != sqlRowShape(other.querySelection)) {
      throw const OrmException(
        'QUERY.UNION_SELECTION',
        'Select SQL expressions or matching .row records. Map after UNION.',
      );
    }
    // SQL set columns are positional: selecting (id, id) still exports two.
    final (left, decode) = planQuery(deduplicate: false);
    if ((database.dialect == SqlDialect.mysql ||
            database.dialect == SqlDialect.mariadb) &&
        left.columns.any((e) => e.codec.sqlType == 'decimal')) {
      throw const OrmException(
        'CAPABILITY.DECIMAL_PRECISION',
        'MySQL/MariaDB decimal UNION may silently narrow mixed precision; use explicit native SQL when its precision is acceptable.',
      );
    }
    final (right, _) = other.planQuery(deduplicate: false);
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
    final fields = UnionFields.internal(table, queryFields, left);
    final columns = [
      for (var i = 0; i < left.columns.length; i++)
        Expr.internal(ColumnNode(table, 'c$i'), left.columns[i].codec),
    ];
    // A scalar remains an Expr, so scalar()/isInQuery() compose unchanged.
    final Selection<R> selection = shape == 0
        ? Expr.internal(
            columns.single.expressionNode,
            left.columns.single.codec as Codec<R>,
          )
        : ReboundSelection(decode, columns, source: querySelection);
    return Query.internal(
      database,
      fields,
      QueryState(table, union: UnionSource(this, left, other, right, all)),
      selection,
    );
  }
}

/// @nodoc
@internal
int? sqlRowShape(Selection<Object?> selection) => switch (selection) {
  Expr() => 0,
  _SqlRow(:final columns) => columns.length,
  ReboundSelection(:final source?) => sqlRowShape(source),
  _ => null,
};

/// References refer to the left operand's exported SQL expressions.
///
/// Use [ref] when filtering, selecting, or ordering the result of a set operation.
final class UnionFields<F extends Fields> extends Fields {
  /// @nodoc
  @internal
  final F sourceFields;

  /// @nodoc
  @internal
  final SelectionPlan planQuery;

  /// @nodoc
  @internal
  UnionFields.internal(super.table, this.sourceFields, this.planQuery);

  /// References a selected left-operand expression in the combined SQL result.
  ///
  /// The expression must match an exported column with its original codec and
  /// nullability. Expressions omitted by the operand's selection are rejected.
  Expr<T> ref<T>(Expr<T> Function(F) expression) {
    final original = expression(sourceFields);
    final index = planQuery.columns.indexWhere(
      (e) => sameSqlNode(e.expressionNode, original.expressionNode),
    );
    if (index < 0) {
      throw const OrmException(
        'QUERY.UNION_COLUMN',
        'UNION did not export this SQL expression.',
      );
    }
    if (planQuery.columns[index].codec.acceptsNull &&
        !original.codec.acceptsNull) {
      throw const OrmException(
        'QUERY.NULLABILITY',
        'Reference this UNION column with a nullable expression.',
      );
    }
    if (!planQuery.columns[index].codec.sameStorageAs(original.codec)) {
      throw const OrmException(
        'QUERY.UNION_CODEC',
        'Reference the exported UNION codec.',
      );
    }
    return Expr.internal(ColumnNode(table, 'c$index'), original.codec);
  }
}

/// @nodoc
@internal
final class UnionSource(
  final Query<Object?, Fields> left,
  final SelectionPlan leftPlan,
  final Query<Object?, Fields> right,
  final SelectionPlan rightPlan,
  final bool all,
) {
  String write(SqlWriter w) =>
      'SELECT * FROM (${left.writeQuery(w, leftPlan, aliasColumns: true)}) AS ${w.quote('_union_left')} '
      'UNION${all ? ' ALL' : ''} '
      'SELECT * FROM (${right.writeQuery(w, rightPlan, aliasColumns: true)}) AS ${w.quote('_union_right')}';
}
