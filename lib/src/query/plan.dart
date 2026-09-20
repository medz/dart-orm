import 'package:meta/meta.dart';

import '../../driver.dart';
import 'context.dart';
import 'nodes.dart';
import 'query.dart';
import 'reads.dart';
import 'relation.dart';
import 'selection.dart';
import 'table.dart';

/// A physical SQL output slot, including association keys and presence markers.
/// Expressions without a direct column source have null table/column names.
typedef PlannedColumn = ({
  int index,
  String codecType,
  String? table,
  String? column,
  bool presence,
});

/// A joined table name, join kind and whether a relation introduced it.
typedef PlannedJoin = ({String table, bool left, bool relation});

/// A non-executing description of one SQL statement and its dependent batches.
/// Bound values are omitted; literal SQL text is retained. A batch SQL template
/// contains one parent key tuple.
final class QueryPlan {
  /// The dialect used to compile this statement.
  final SqlDialect dialect;

  /// Compiled SQL text without bound parameter values.
  final String sql;

  /// The number of separately bound values.
  final int parameterCount;

  /// Physical output slots, including internal association and presence keys.
  final List<PlannedColumn> columns;

  /// Explicit and relation-generated joins in the root statement.
  final List<PlannedJoin> joins;

  /// Conditional relationship loads that may execute extra statements.
  final List<RelationLoadPlan> loads;

  /// Sorted physical table names read by this statement.
  final List<String> reads;

  /// Whether raw SQL may read tables that cannot be inferred.
  final bool opaqueReads;

  /// @nodoc
  @internal
  QueryPlan.internal(
    this.dialect,
    SqlCommand command,
    List<PlannedColumn> columns,
    List<PlannedJoin> joins,
    List<RelationLoadPlan> loads,
    ReadTables reads,
  ) : sql = command.sql,
      parameterCount = command.parameters.length,
      columns = List.unmodifiable(columns),
      joins = List.unmodifiable(joins),
      loads = List.unmodifiable(loads),
      reads = List.unmodifiable(
        reads.tables.map((t) => t.name).toSet().toList()..sort(),
      ),
      opaqueReads = reads.opaque;

  /// Statement templates in this tree, not the number of executed statements.
  int get sqlTemplateCount =>
      1 +
      loads.fold(
        0,
        (count, load) => count + (load.query?.sqlTemplateCount ?? 0),
      );

  /// Returns an inspection report without parameter values.
  Map<String, Object?> toJson() => {
    'dialect': dialect.name,
    'sql': sql,
    'parameterCount': parameterCount,
    'columns': [
      for (final c in columns)
        {
          'index': c.index,
          'codecType': c.codecType,
          if (c.table != null) 'table': c.table,
          if (c.column != null) 'column': c.column,
          if (c.presence) 'presence': true,
        },
    ],
    'joins': [
      for (final j in joins)
        {
          'table': j.table,
          'kind': j.left ? 'left' : 'inner',
          'relation': j.relation,
        },
    ],
    'loads': loads.map((l) => l.toJson()).toList(),
    'reads': reads,
    'opaqueReads': opaqueReads,
    'sqlTemplateCount': sqlTemplateCount,
  };
}

/// One batch per chunk of distinct non-null parent keys, conditional on data.
/// For nested loads, this rule applies separately to each returned parent batch.
final class RelationLoadPlan {
  /// Root output positions containing the relationship's parent key.
  final List<int> parentColumns;

  /// Child output positions containing the matching foreign key.
  final List<int> childColumns;

  /// The number of columns in each relationship key.
  final int keyWidth;

  /// An optional row limit applied separately to each parent.
  final int? limitPerParent;

  /// An optional row offset applied separately to each parent.
  final int offsetPerParent;

  /// Bound parameters needed before adding parent key tuples.
  final int? fixedParameters;

  /// Maximum parent keys that fit within the engine's parameter limit.
  final int? maxKeysPerBatch;

  /// Null when take(0) skips this relationship entirely.
  final QueryPlan? query;

  /// @nodoc
  @internal
  RelationLoadPlan.internal(
    List<int> parentColumns,
    List<int> childColumns,
    this.keyWidth,
    this.limitPerParent,
    this.offsetPerParent,
    this.fixedParameters,
    this.maxKeysPerBatch,
    this.query,
  ) : parentColumns = List.unmodifiable(parentColumns),
      childColumns = List.unmodifiable(childColumns);

  /// Whether this load is known to produce no rows without executing SQL.
  bool get skipped => query == null;

  /// Returns a serializable description of the conditional load.
  Map<String, Object?> toJson() => {
    'strategy': 'batch',
    'parentColumns': parentColumns,
    'childColumns': childColumns,
    'keyWidth': keyWidth,
    'limitPerParent': limitPerParent,
    'offsetPerParent': offsetPerParent,
    'skipped': skipped,
    if (!skipped) 'fixedParameters': fixedParameters,
    if (!skipped) 'maxKeysPerBatch': maxKeysPerBatch,
    if (query != null) 'query': query!.toJson(),
  };
}

/// @nodoc
@internal
QueryPlan inspectQuery(Query<Object?, Fields> query) {
  final plan = query.planQuery().$1, reads = ReadTables(includeRaw: true);
  final command = query.compileQuery(plan, reads: reads);
  return _describeStatement(
    query.database,
    query.queryState,
    plan,
    command,
    reads,
  );
}

QueryPlan _describeStatement(
  QueryContext db,
  QueryState state,
  SelectionPlan plan,
  SqlCommand command,
  ReadTables reads,
) {
  final loads = [for (final load in plan.relations) load.inspect(db)];
  final columns = <PlannedColumn>[];
  for (final (i, expression) in plan.columns.indexed) {
    final node = unwrapStorage(expression.expressionNode);
    final (table, column) = switch (node) {
      ColumnNode() => (node.table.schema.name, node.name),
      PresenceNode() => (
        node.alias.fields.table.schema.name,
        node.alias.presenceMarker,
      ),
      _ => (null, null),
    };
    columns.add((
      index: i,
      codecType: expression.codec.sqlType,
      table: table,
      column: column,
      presence: node is PresenceNode,
    ));
  }
  return QueryPlan.internal(
    db.dialect,
    command,
    columns,
    [
      for (final join in state.joins)
        (
          table: join.alias.fields.table.schema.name,
          left: join.left,
          relation: false,
        ),
      for (final join in plan.joins)
        (
          table: join.alias.fields.table.schema.name,
          left: join.left,
          relation: true,
        ),
    ],
    loads,
    reads,
  );
}

/// @nodoc
@internal
RelationLoadPlan inspectRelation(
  QueryContext db,
  TypedRelationBinding<Object?, Fields> binding,
) {
  final relation = binding.relation, width = relation.childFields.length;
  final state = relation.queryState;
  if (state.limit == 0) {
    return RelationLoadPlan.internal(
      binding.parentIndices,
      const [],
      width,
      0,
      state.offset ?? 0,
      null,
      null,
      null,
    );
  }
  final plan = SelectionPlan();
  // Bind descriptions, never decode a fake row.
  relation.querySelection.bindSelection(plan);
  final childIndices = [
    for (final key in relation.childFields) plan.column(key),
  ];
  final reads = ReadTables(includeRaw: true);
  // Null placeholders require no codec or fabricated domain object. The command
  // is a template only and is never sent to a driver.
  final command = binding.compileQuery(db, plan, [
    RelationKey(List.filled(width, null)),
  ], reads: reads);
  final fixed = command.parameters.length - width;
  final capacity = (db.capabilities.maxParameters - fixed) ~/ width;
  if (capacity < 1) {
    throw const OrmException(
      'QUERY.PARAMETERS',
      'No parameter capacity remains for relation keys.',
    );
  }
  return RelationLoadPlan.internal(
    binding.parentIndices,
    childIndices,
    width,
    state.limit,
    state.offset ?? 0,
    fixed,
    capacity,
    _describeStatement(db, state, plan, command, reads),
  );
}
