part of '../orm.dart';

/// A physical SQL output slot, including association keys and presence markers.
/// Expressions without a direct column source have null table/column names.
typedef PlannedColumn = ({
  int index,
  String codecType,
  String? table,
  String? column,
  bool presence,
});
typedef PlannedJoin = ({String table, bool left, bool relation});

/// A non-executing description of one SQL statement and its dependent batches.
/// Bound values are omitted; literal SQL text is retained. A batch SQL template
/// contains one parent key tuple.
final class QueryPlan {
  final SqlDialect dialect;
  final String sql;
  final int parameterCount;
  final List<PlannedColumn> columns;
  final List<PlannedJoin> joins;
  final List<RelationLoadPlan> loads;
  final List<String> reads;
  final bool opaqueReads;
  QueryPlan._(
    this.dialect,
    SqlCommand command,
    List<PlannedColumn> columns,
    List<PlannedJoin> joins,
    List<RelationLoadPlan> loads,
    _ReadTables reads,
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
  final List<int> parentColumns;
  final List<int> childColumns;
  final int keyWidth;
  final int? limitPerParent;
  final int offsetPerParent;
  final int? fixedParameters;
  final int? maxKeysPerBatch;

  /// Null when take(0) skips this relationship entirely.
  final QueryPlan? query;
  RelationLoadPlan._(
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
  bool get skipped => query == null;
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

QueryPlan _inspectQuery(Query<Object?, Fields> query) {
  final plan = query._plan().$1, reads = _ReadTables(includeRaw: true);
  final command = query._compile(plan, reads: reads);
  return _describeStatement(query.database, query._state, plan, command, reads);
}

QueryPlan _describeStatement(
  Database<Backend> db,
  _QueryState state,
  _SelectionPlan plan,
  SqlCommand command,
  _ReadTables reads,
) {
  final loads = [for (final load in plan.relations) load.inspect(db)];
  final columns = <PlannedColumn>[];
  for (final (i, expression) in plan.columns.indexed) {
    final node = _unwrapStorage(expression._node);
    final (table, column) = switch (node) {
      _ColumnNode() => (node.table.schema.name, node.name),
      _Presence() => (node.alias.fields.table.schema.name, node.alias._marker),
      _ => (null, null),
    };
    columns.add((
      index: i,
      codecType: expression.codec.sqlType,
      table: table,
      column: column,
      presence: node is _Presence,
    ));
  }
  return QueryPlan._(
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

RelationLoadPlan _inspectRelation(
  Database<Backend> db,
  _TypedRelationBinding<Object?, Fields> binding,
) {
  final relation = binding.relation, width = relation._child.length;
  final state = relation._state;
  if (state.limit == 0) {
    return RelationLoadPlan._(
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
  final plan = _SelectionPlan();
  // Bind descriptions, never decode a fake row.
  relation._selection._bind(plan);
  final childIndices = [for (final key in relation._child) plan.column(key)];
  final reads = _ReadTables(includeRaw: true);
  // Null placeholders require no codec or fabricated domain object. The command
  // is a template only and is never sent to a driver.
  final command = binding._compile(db, plan, [
    _RelationKey(List.filled(width, null)),
  ], reads: reads);
  final fixed = command.parameters.length - width;
  final capacity = (db.capabilities.maxParameters - fixed) ~/ width;
  if (capacity < 1) {
    throw const OrmException(
      'QUERY.PARAMETERS',
      'No parameter capacity remains for relation keys.',
    );
  }
  return RelationLoadPlan._(
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
