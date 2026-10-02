import 'package:meta/meta.dart';

import '../values/codec.dart';
import 'context.dart';
import 'cte.dart';
import 'expression.dart';
import 'joins.dart';
import 'nodes.dart';
import 'query.dart';
import 'selection.dart';
import 'table.dart';
import 'union.dart';

/// A typed field collection exported by a flat SQL projection.
///
/// Generated or handwritten field classes receive [ProjectionFields] and pass
/// its [ProjectionFields.table] to this constructor. Each CTE or UNION occurrence
/// creates fresh expressions for that occurrence.
abstract class ProjectionOutput extends Fields {
  const ProjectionOutput(super.table);
}

/// A nominal output slot, independent of the expression bound to it.
///
/// Create one stable slot per projection declaration. Equal source expressions
/// can occupy distinct slots; each binding occurrence owns its physical output.
final class Slot<T> {
  /// Logical name for diagnostics and static field generation.
  final String name;

  /// Creates a fresh identity. SQL output uses its position, not this name.
  Slot(this.name) {
    if (name.isEmpty || name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name', 'Invalid projection slot name.');
    }
  }

  /// Binds an expression with its actual codec to this output slot.
  ///
  /// Dart covariance can widen `Expr<int>` to `Expr<num>`; it cannot widen that
  /// expression's `Codec<int>` encoder. Such mismatches are rejected here. Supply
  /// an expression with an explicit target-type codec and SQL semantics instead.
  SlotBinding<T> bind(Expr<T> expression) {
    final codec = expression.codec;
    if (codec.valueType != T) {
      throw const OrmException(
        'PROJECTION.CODEC_TYPE',
        'The expression codec must have the exact slot value type. Use an explicit target-type codec or SQL conversion.',
      );
    }
    return SlotBinding._(
      this,
      Expr<T>.internal(expression.expressionNode, codec),
    );
  }
}

/// One immutable association between a declared slot and its source expression.
final class SlotBinding<T> {
  final Slot<T> slot;
  final Expr<T> expression;
  const SlotBinding._(this.slot, this.expression);
}

/// A fixed flat SQL layout, result assembler, and typed output field factory.
///
/// This object's identity defines UNION compatibility. The assembler receives
/// values already decoded by the binding's expression codecs. Callbacks must be
/// deterministic; closure purity cannot be proven by the ORM. Per-binding Dart
/// mappings belong after SQL set operations.
final class ProjectionType<R, O extends ProjectionOutput> {
  final List<Slot<Object?>> slots;
  final R Function(List<Object?> values) assemble;
  final O Function(ProjectionFields fields) fields;

  ProjectionType({
    required List<Slot<Object?>> slots,
    required this.assemble,
    required this.fields,
  }) : slots = List.unmodifiable(slots) {
    if (this.slots.isEmpty) {
      throw const OrmException(
        'PROJECTION.EMPTY',
        'Declare at least one slot.',
      );
    }
    final keys = Set<Slot<Object?>>.identity();
    final names = <String>{};
    for (final slot in this.slots) {
      if (!keys.add(slot) || !names.add(slot.name)) {
        throw const OrmException(
          'PROJECTION.SLOT',
          'Projection slots must have distinct identities and names.',
        );
      }
    }
  }

  /// Captures one complete binding in the descriptor's declared order.
  Projection<R, O> bind(List<SlotBinding<Object?>> bindings) {
    final frozen = List<SlotBinding<Object?>>.unmodifiable(bindings);
    if (frozen.length != slots.length ||
        frozen.indexed.any((e) => !identical(e.$2.slot, slots[e.$1]))) {
      throw const OrmException(
        'PROJECTION.BINDING',
        'Bind every declared slot once, in declaration order.',
      );
    }
    return Projection._(this, frozen);
  }
}

/// Access to validated output slots on a fresh derived SQL occurrence.
///
/// A field factory can only obtain exported slots with their stored codecs.
/// It cannot replace an output codec or invent a SQL column name.
final class ProjectionFields {
  /// The fresh derived SQL occurrence that owns these output slots.
  final TableRef table;
  final Map<Slot<Object?>, int> _indices;
  final List<Expr<Object?>> _columns;
  ProjectionFields._(this.table, List<Slot<Object?>> slots, this._columns)
    : _indices = Map<Slot<Object?>, int>.identity() {
    for (var i = 0; i < slots.length; i++) {
      _indices[slots[i]] = i;
    }
  }

  /// Resolves this declaration's slot without comparing source expressions.
  Expr<T> read<T>(Slot<T> slot) {
    final index = _indices[slot];
    if (index == null) {
      throw const OrmException(
        'PROJECTION.SLOT',
        'This projection did not export that slot.',
      );
    }
    final expression = _columns[index];
    if (expression.codec.valueType != T) {
      throw const OrmException(
        'PROJECTION.CODEC_TYPE',
        'Read the declared slot type; broadening it does not broaden its codec.',
      );
    }
    return Expr<T>.internal(
      expression.expressionNode,
      expression.codec as Codec<T>,
    );
  }
}

/// A flat SQL selection with stable, independently registered output slots.
///
/// This also composes inside ordinary Selection maps and relationship child
/// selections. Its codec decoding receives only its own captured physical cells.
final class Projection<R, O extends ProjectionOutput> extends Selection<R> {
  final ProjectionType<R, O> type;
  final List<SlotBinding<Object?>> bindings;
  const Projection._(this.type, this.bindings);

  @override
  RowDecoder<R> bindSelection(SelectionPlan plan) {
    final indices = [
      for (final binding in bindings) plan.appendSlot(binding.expression),
    ];
    return (row) => type.assemble([
      for (var i = 0; i < indices.length; i++)
        bindings[i].expression.codec.decode(row[indices[i]]),
    ]);
  }

  /// @nodoc
  @internal
  O bindOutput(TableRef table) {
    if (table.schema.columns.length != bindings.length) {
      throw const OrmException(
        'PROJECTION.SHAPE',
        'Derived output width differs from its projection.',
      );
    }
    for (var i = 0; i < bindings.length; i++) {
      final original = bindings[i].expression.codec;
      final exported = table.schema.columns[i].codec;
      if (original.acceptsNull != exported.acceptsNull) {
        throw const OrmException(
          'QUERY.NULLABILITY',
          'Derived slots require an explicit nullable source expression.',
        );
      }
      if (!original.sameStorageAs(exported)) {
        throw const OrmException(
          'PROJECTION.CODEC',
          'A derived slot must preserve its bound decoding codec.',
        );
      }
    }
    final columns = [
      for (var i = 0; i < bindings.length; i++)
        Expr<Object?>.internal(
          ColumnNode(table, 'c$i'),
          table.schema.columns[i].codec,
        ),
    ];
    final output = type.fields(ProjectionFields._(table, type.slots, columns));
    if (!identical(output.table, table)) {
      throw const OrmException(
        'PROJECTION.SCOPE',
        'Create output fields for the supplied projection occurrence.',
      );
    }
    return output;
  }
}

/// A selected result that retains both source fields and declared output fields.
///
/// Filters, joins, ordering, and grouping keep using [F]. A flat projection's
/// explicit `asCte` or set operation establishes its declared output scope. [S]
/// preserves that concrete selection type across query composition. Ordinary
/// result mappings and relation loading do not declare named SQL fields.
base class SelectedQuery<R, F extends Fields, S extends Selection<R>>
    extends Query<R, F> {
  final S _output;

  /// @nodoc
  @internal
  SelectedQuery.internal(Query<R, F> source, this._output)
    : super.internal(
        source.database,
        source.queryFields,
        source.queryState,
        source.querySelection,
      );

  @override
  SelectedQuery<R, F, S> copyQuery(QueryState state) =>
      SelectedQuery.internal(super.copyQuery(state), _output);

  @override
  SelectedQuery<R, F, S> where(Expr<bool?> Function(F) condition) =>
      super.where(condition) as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> orderBy(List<OrderTerm> Function(F) order) =>
      super.orderBy(order) as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> groupBy(List<Expr<Object?>> Function(F) group) =>
      super.groupBy(group) as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> having(Expr<bool?> Function(F) condition) =>
      super.having(condition) as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> take(int count) =>
      super.take(count) as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> skip(int count) =>
      super.skip(count) as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> distinct() =>
      super.distinct() as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> join<T, G extends Fields>(
    TableAlias<T, G> alias, {
    required Expr<bool?> Function(F, G) on,
  }) => super.join(alias, on: on) as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> leftJoin<T, G extends Fields>(
    TableAlias<T, G> alias, {
    required Expr<bool?> Function(F, G) on,
  }) => super.leftJoin(alias, on: on) as SelectedQuery<R, F, S>;

  @override
  SelectedQuery<R, F, S> bind(QueryContext context) =>
      SelectedQuery.internal(super.bind(context), _output);
}

/// SQL composition that preserves a flat projection's named output fields.
///
/// Ordinary [Query] composition remains available. The source scope changes
/// only at the explicit CTE or UNION boundary, never merely at `select`.
extension ProjectedSql<R, F extends Fields, O extends ProjectionOutput>
    on SelectedQuery<R, F, Projection<R, O>> {
  /// Exports named output slots into a fresh SQL scope.
  ///
  /// The resulting callback fields are [O]; the preceding source [F] is no
  /// longer in scope. This describes SQL and performs no I/O.
  DerivedQuery<R, O, Projection<R, O>> asCte(String name) =>
      Cte.internal(this, name).queryWithOutput(_output);

  /// Combines rows from the same projection declaration, removing duplicates.
  ///
  /// Slot codecs and nullability must match, and both queries must belong to the
  /// same database or transaction. Set equality uses exported SQL cells.
  SelectedQuery<R, O, Projection<R, O>> union<G extends Fields>(
    SelectedQuery<R, G, Projection<R, O>> other,
  ) => _derived(SetQueries<R, F>(this).union(other));

  /// Combines matching SQL rows, preserving duplicates.
  ///
  /// Ordering is unspecified until `orderBy` is supplied on the resulting query.
  SelectedQuery<R, O, Projection<R, O>> unionAll<G extends Fields>(
    SelectedQuery<R, G, Projection<R, O>> other,
  ) => _derived(SetQueries<R, F>(this).unionAll(other));

  SelectedQuery<R, O, Projection<R, O>> _derived(Query<R, Fields> source) {
    final output = _output.bindOutput(source.queryFields.table);
    return SelectedQuery.internal(
      Query.internal(
        source.database,
        output,
        source.queryState,
        source.querySelection,
      ),
      _output,
    );
  }
}

/// Internal nominal contract lookup survives CTE/UNION rebindings.
Object? projectionTypeOf(Selection<Object?> selection) => switch (selection) {
  Projection(:final type) => type,
  ReboundSelection(:final source?) => projectionTypeOf(source),
  _ => null,
};
