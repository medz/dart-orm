import 'package:meta/meta.dart';

import 'dart:typed_data';

import '../../driver.dart';
import 'context.dart';
import 'expression.dart';
import 'joins.dart';
import 'nodes.dart';
import 'plan.dart';
import 'query.dart';
import 'reads.dart';
import 'selection.dart';
import 'table.dart';

/// How a to-one selection is loaded when its parent query executes.
///
/// [automatic] joins targets covered by a declared primary or unique key and
/// batches other targets. [join] requires such a key; [batch] always uses
/// additional queries limited by the driver's available parameter capacity.
enum ToOneStrategy { automatic, join, batch }

/// A relationship is a query description. Constructing or selecting it performs
/// no I/O. List results are loaded in batches on the root query's connection.
///
/// Filters, ordering, pagination, and selections return new descriptions. Each
/// selected relationship can add queries; batching groups distinct parent keys
/// instead of issuing one query per parent. Use a transaction when the root and
/// its batches must share the database's configured snapshot isolation.
final class Relation<R, F extends Fields> {
  final TableAlias<Object?, F> _alias;

  /// @nodoc
  @internal
  final List<Expr<Object?>> parentFields;

  /// @nodoc
  @internal
  final List<ReadField<Object?>> childFields;

  /// @nodoc
  @internal
  final F queryFields;

  /// @nodoc
  @internal
  final QueryState queryState;

  /// @nodoc
  @internal
  final Selection<R> querySelection;

  /// Describes an equality relationship between parent and target key columns.
  ///
  /// [parent] and [child] must have the same nonzero arity. Child fields must
  /// belong to the supplied [target] occurrence. A null parent key has no match.
  /// Generated relationship getters normally construct this value for you.
  factory Relation(
    Table<R, F> target, {
    required List<Expr<Object?>> parent,
    required List<ReadField<Object?>> Function(F) child,
  }) {
    final alias = target.alias();
    final fields = alias.fields;
    final keys = child(fields);
    if (parent.isEmpty ||
        parent.length != keys.length ||
        keys.any((key) => key.table != fields.table)) {
      throw ArgumentError(
        'Relationship keys need equal non-zero arity and fields from the target occurrence.',
      );
    }
    return Relation.internal(
      alias,
      List.unmodifiable(parent),
      List.unmodifiable(keys),
      fields,
      QueryState(fields.table),
      target.selectRow(fields),
    );
  }

  /// @nodoc
  @internal
  Relation.internal(
    this._alias,
    this.parentFields,
    this.childFields,
    this.queryFields,
    this.queryState,
    this.querySelection,
  );

  /// @nodoc
  @internal
  Relation<R, F> copyQuery(QueryState state) => Relation.internal(
    _alias,
    parentFields,
    childFields,
    queryFields,
    state,
    querySelection,
  );

  /// Adds a SQL predicate to the related rows, combined with earlier filters.
  Relation<R, F> where(Expr<bool?> Function(F) predicate) {
    final next = predicate(queryFields);
    return copyQuery(
      queryState.copy(predicate: queryState.predicate?.and(next) ?? next),
    );
  }

  /// Replaces related-row ordering; include a stable tie breaker for pagination.
  Relation<R, F> orderBy(List<OrderTerm> Function(F) order) =>
      copyQuery(queryState.copy(order: List.unmodifiable(order(queryFields))));

  /// Limits each parent's result to [count] rows; negative counts are rejected.
  ///
  /// Batched per-parent pagination requires explicit [orderBy].
  Relation<R, F> take(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return copyQuery(queryState.copy(limit: count));
  }

  /// Skips [count] rows per parent; batched pagination requires [orderBy].
  Relation<R, F> skip(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return copyQuery(queryState.copy(offset: count));
  }

  /// Replaces each related row's result shape without loading it.
  Relation<S, F> select<S>(Selection<S> Function(F) selection) =>
      Relation.internal(
        _alias,
        parentFields,
        childFields,
        queryFields,
        queryState,
        selection(queryFields),
      );

  /// Selects a list per parent, returning an empty list when no rows match.
  ///
  /// Execution batches distinct non-null parent keys according to the driver's
  /// parameter limit. Nested collections can require further batches.
  Selection<List<R>> many() => _RelationSelection(this);
  bool get _uniqueTarget {
    final names = childFields.map((key) => key.definition.name).toSet();
    final schema = queryFields.table.schema;
    return [
      schema.primaryKey,
      ...schema.uniqueKeys,
      for (final index in schema.indexes)
        if (index.unique) index.columns,
    ].any((key) => key.isNotEmpty && key.every(names.contains));
  }

  bool _useJoin(ToOneStrategy strategy) {
    if (strategy == ToOneStrategy.join && !_uniqueTarget) {
      throw const OrmException(
        'RELATION.JOIN_KEY',
        'A to-one join must cover a declared primary or unique target key.',
      );
    }
    return strategy != ToOneStrategy.batch && _uniqueTarget;
  }

  /// Selects at most one visible row, or null when no row matches.
  ///
  /// A batch with multiple selected rows throws `RELATION.CARDINALITY`.
  /// When `R` is nullable, a present row containing SQL NULL also returns null;
  /// use [required] to require row presence independently of the selected value.
  Selection<R?> one({ToOneStrategy strategy = ToOneStrategy.automatic}) =>
      _useJoin(strategy)
      ? _JoinedRelationSelection<R?, F>(this)
      : _oneBatch().map((rows) => rows.firstOrNull);

  Selection<List<R>> _oneBatch() =>
      copyQuery(
        queryState.copy(
          order: queryState.order.isEmpty
              ? [for (final key in childFields) key.asc()]
              : queryState.order,
          limit: queryState.limit != null && queryState.limit! < 2
              ? queryState.limit
              : 2,
        ),
      ).many().map((rows) {
        if (rows.length > 1) {
          throw const OrmException(
            'RELATION.CARDINALITY',
            'Expected at most one related row.',
          );
        }
        return rows;
      });

  /// Requires one visible row while preserving the selected value's nullability.
  ///
  /// Throws `RELATION.MISSING` for an absent row and `RELATION.CARDINALITY` for
  /// multiple selected rows. This validates row presence during decoding; it
  /// does not turn the parent query into an inner join.
  Selection<R> required({ToOneStrategy strategy = ToOneStrategy.automatic}) =>
      _useJoin(strategy)
      ? _JoinedRelationSelection<R, F>(this, required: true)
      : _oneBatch().map((rows) {
          if (rows.isEmpty) {
            throw const OrmException(
              'RELATION.MISSING',
              'A required related row is not visible.',
            );
          }
          return rows.single;
        });

  /// Builds a correlated SQL EXISTS expression for the filtered relationship.
  ///
  /// Apply it before [take] or [skip]; paginated relationships are rejected.
  Expr<bool> any() =>
      Expr.internal(RelationSubqueryNode(this, false), Codecs.boolean);

  /// Builds the negation of [any], without loading the related rows.
  Expr<bool?> none() => any().not();

  /// Checks that every filtered related row makes [condition] SQL TRUE.
  ///
  /// An empty relationship satisfies this expression. SQL FALSE and SQL NULL
  /// both count as failures of the condition. Apply it before [take] or [skip].
  Expr<bool?> every(Expr<bool?> Function(F) condition) {
    final conditionNode = condition(queryFields).expressionNode;
    return where(
      (_) => Expr.internal(
        UnaryNode('IS NOT TRUE', conditionNode, postfix: true),
        Codecs.boolean,
      ),
    ).none();
  }

  /// Builds a correlated SQL count without fetching related rows into Dart.
  ///
  /// Counts filtered related rows; [take] and [skip] are not supported here.
  Expr<int> count() =>
      Expr.internal(RelationSubqueryNode(this, true), Codecs.integer);
}

final class _JoinedRelationSelection<R, F extends Fields>(
  final Relation<R, F> relation, {
  final bool required = false,
}) extends Selection<R> {
  /// @nodoc
  @internal
  @override
  RowDecoder<R> bindSelection(SelectionPlan plan) {
    Expr<bool?> match(int i) => Expr.internal(
      BinaryNode(
        relation.childFields[i].expressionNode,
        '=',
        relation.parentFields[i].expressionNode,
      ),
      Codecs.boolean.nullable(),
    );
    Expr<bool?> predicate = match(0);
    for (var i = 1; i < relation.childFields.length; i++) {
      predicate = predicate.and(match(i));
    }
    if (relation.queryState.predicate case final filter?) {
      predicate = predicate.and(filter);
    }
    // A proven unique match has at most one row, so skipping it or taking zero
    // must produce an absent relation, without filtering out the root row.
    if (relation.queryState.limit == 0 ||
        (relation.queryState.offset ?? 0) > 0) {
      predicate = predicate.and(value(false, Codecs.boolean));
    }
    final existing = plan.joins
        .where((join) => join.alias.fields.table == relation.queryFields.table)
        .firstOrNull;
    if (existing == null) {
      plan.joins.add(Join(relation._alias, predicate, true));
    } else if (!sameSqlNode(
      existing.on.expressionNode,
      predicate.expressionNode,
    )) {
      throw const OrmException(
        'RELATION.ALIAS',
        'Use a fresh relation getter for differently filtered joins.',
      );
    }
    final marker = plan.column(
      Expr.internal(PresenceNode(relation._alias), Codecs.integer.nullable()),
    );
    final decode = plan.optional(
      relation.queryFields.table,
      relation.querySelection,
    );
    return (row) {
      if (row[marker] != null) return decode(row);
      if (required) {
        throw const OrmException(
          'RELATION.MISSING',
          'A required related row is not visible.',
        );
      }
      // one() instantiates a nullable R. Presence is independent of value nullability.
      return null as R;
    };
  }
}

final class _RelationSelection<R, F extends Fields>(
  final Relation<R, F> relation,
) extends Selection<List<R>> {
  /// @nodoc
  @internal
  @override
  RowDecoder<List<R>> bindSelection(SelectionPlan plan) {
    final index = plan.relations.length;
    final parentIndices = [
      for (final key in relation.parentFields) plan.column(key),
    ];
    plan.relations.add(TypedRelationBinding(relation, parentIndices));
    return (row) => row[plan.columns.length + index] as List<R>;
  }
}

/// @nodoc
@internal
abstract class RelationBinding {
  RelationLoadPlan inspect(QueryContext db);
  void collectReads(QueryContext db, ReadTables reads);
  Future<List<Object?>> load(
    QueryContext db,
    SqlConnection connection,
    List<List<Object?>> parents, {
    ExecutionOptions options = const ExecutionOptions(),
  });
}

/// @nodoc
@internal
final class TypedRelationBinding<R, F extends Fields>(
  final Relation<R, F> relation,
  final List<int> parentIndices,
) extends RelationBinding {
  @override
  RelationLoadPlan inspect(QueryContext db) => inspectRelation(db, this);
  @override
  void collectReads(QueryContext db, ReadTables reads) => reads.query(
    Query.internal(
      db,
      relation.queryFields,
      relation.queryState,
      relation.querySelection,
    ),
  );

  @override
  Future<List<Object?>> load(
    QueryContext db,
    SqlConnection connection,
    List<List<Object?>> parents, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final keys = <RelationKey>{};
    final parentKeys = [
      for (final row in parents)
        RelationKey([
          for (var i = 0; i < parentIndices.length; i++)
            _relationValue(relation.parentFields[i], row[parentIndices[i]]),
        ]),
    ];
    for (final key in parentKeys) {
      if (!key.values.contains(null)) keys.add(key);
    }
    final grouped = <RelationKey, List<R>>{};
    if (keys.isEmpty || relation.queryState.limit == 0) {
      return [for (final _ in parents) <R>[]];
    }
    final plan = SelectionPlan();
    final decode = relation.querySelection.bindSelection(plan);
    final childIndices = [
      for (final key in relation.childFields) plan.column(key),
    ];
    final all = keys.toList();
    final baseCount =
        compileQuery(db, plan, [all.first]).parameters.length -
        relation.childFields.length;
    final chunkSize =
        (db.capabilities.maxParameters - baseCount) ~/
        relation.childFields.length;
    if (chunkSize < 1) {
      throw const OrmException(
        'QUERY.PARAMETERS',
        'No parameter capacity remains for relation keys.',
      );
    }
    for (var offset = 0; offset < all.length; offset += chunkSize) {
      final end = offset + chunkSize < all.length
          ? offset + chunkSize
          : all.length;
      final command = compileQuery(db, plan, all.sublist(offset, end));
      final result = await db.executeOn(connection, command, options: options);
      final rows = await expandRelations(
        db,
        connection,
        plan,
        result.rows,
        options: options,
      );
      db.observeDecode(command.sql, rows.length, () {
        for (final row in rows) {
          final key = RelationKey([
            for (var i = 0; i < childIndices.length; i++)
              _relationValue(relation.childFields[i], row[childIndices[i]]),
          ]);
          (grouped[key] ??= []).add(decode(row));
        }
      });
    }
    return [
      for (final key in parentKeys) List<R>.unmodifiable(grouped[key] ?? <R>[]),
    ];
  }

  SqlCommand compileQuery(
    QueryContext db,
    SelectionPlan plan,
    List<RelationKey> keys, {
    ReadTables? reads,
  }) {
    final state = relation.queryState;
    final w = SqlWriter(
      db.dialect,
      {},
      database: db,
      reads: reads,
      exactDecimal: db.capabilities.exactDecimal,
      temporal: db.capabilities.temporal,
    );
    Expr<bool?> predicate = Expr.internal(
      RelationKeys(relation.childFields, keys),
      Codecs.boolean,
    );
    if (state.predicate case final filter?) predicate = predicate.and(filter);
    final paginated = state.limit != null || state.offset != null;
    final sqlPlan = SelectionPlan()
      ..columns.addAll(plan.columns)
      ..required.addAll(plan.required)
      ..guarded.addAll(plan.guarded)
      ..joins.addAll(plan.joins);
    if (paginated) {
      if (state.order.isEmpty) {
        throw const OrmException(
          'RELATION.ORDER',
          'Per-parent pagination requires explicit ordering.',
        );
      }
      sqlPlan.columns.add(
        rowNumber(partitionBy: relation.childFields, orderBy: state.order),
      );
    }
    final query = Query.internal(
      db,
      relation.queryFields,
      QueryState(
        state.source,
        predicate: predicate,
        order: paginated ? const [] : state.order,
      ),
      relation.querySelection,
    );
    var text = query.writeQuery(
      w,
      sqlPlan,
      aliasColumns: true,
      decodeResult: true,
    );
    if (paginated) {
      final offset = state.offset ?? 0;
      final rank = w.quote('c${plan.columns.length}');
      text =
          'SELECT ${[for (var i = 0; i < plan.columns.length; i++) w.quote('c$i')].join(', ')} '
          'FROM ($text) AS ${w.quote('orm_partition')} WHERE $rank > ${w.parameter(offset)}';
      if (state.limit case final limit?) {
        text += ' AND $rank <= ${w.parameter(offset + limit)}';
      }
      text += ' ORDER BY $rank';
    }
    return w.finish(text);
  }
}

/// @nodoc
@internal
Future<List<List<Object?>>> expandRelations(
  QueryContext db,
  SqlConnection connection,
  SelectionPlan plan,
  List<List<Object?>> source, {
  ExecutionOptions options = const ExecutionOptions(),
}) async {
  if (plan.relations.isEmpty || source.isEmpty) return source;
  final rows = List<List<Object?>>.generate(source.length, (i) {
    final row = source[i];
    final expanded = List<Object?>.filled(
      row.length + plan.relations.length,
      null,
    );
    expanded.setRange(0, row.length, row);
    return expanded;
  }, growable: false);
  for (var i = 0; i < plan.relations.length; i++) {
    final values = await plan.relations[i].load(
      db,
      connection,
      rows,
      options: options,
    );
    for (var row = 0; row < rows.length; row++) {
      rows[row][plan.columns.length + i] = values[row];
    }
  }
  return rows;
}

/// @nodoc
@internal
final class RelationKey(final List<Object?> values) {
  @override
  int get hashCode =>
      Object.hashAll(values.map((v) => v is Uint8List ? Object.hashAll(v) : v));
  @override
  bool operator ==(Object other) {
    if (other is! RelationKey || values.length != other.values.length) {
      return false;
    }
    for (var i = 0; i < values.length; i++) {
      final a = values[i], b = other.values[i];
      if (a is Uint8List && b is Uint8List) {
        if (a.length != b.length) return false;
        for (var j = 0; j < a.length; j++) {
          if (a[j] != b[j]) return false;
        }
      } else if (a != b) {
        return false;
      }
    }
    return true;
  }
}

Object? _relationValue(Expr<Object?> key, Object? value) => value == null
    ? null
    : switch (key.codec.sqlType) {
        'decimal' => Codecs.decimal.decode(value).toString(),
        'instant' => Codecs.dateTime.encode(Codecs.dateTime.decode(value)),
        'date' => Codecs.date.decode(value).toString(),
        'time' => Codecs.time.decode(value).toString(),
        'local_datetime' => Codecs.localDateTime.decode(value).toString(),
        _ => value,
      };
