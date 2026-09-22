import 'package:meta/meta.dart';

import '../../driver.dart';
import '../../schema_model.dart';
import 'batch.dart';
import 'context.dart';
import 'cte.dart';
import 'expression.dart';
import 'joins.dart';
import 'mutation.dart';
import 'nodes.dart';
import 'plan.dart';
import 'reads.dart';
import 'relation.dart';
import 'selection.dart';
import 'table.dart';
import 'union.dart';

/// @nodoc
@internal
final class QueryState {
  final TableRef source;
  final Expr<bool?>? predicate;
  final List<OrderTerm> order;
  final List<Expr<Object?>> group;
  final Expr<bool?>? having;
  final int? limit;
  final int? offset;
  final bool distinct;
  final List<Join> joins;
  final List<CteDefinition> ctes;
  final UnionSource? union;
  const QueryState(
    this.source, {
    this.predicate,
    this.order = const [],
    this.group = const [],
    this.having,
    this.limit,
    this.offset,
    this.distinct = false,
    this.joins = const [],
    this.ctes = const [],
    this.union,
  });
  QueryState copy({
    Expr<bool?>? predicate,
    List<OrderTerm>? order,
    List<Expr<Object?>>? group,
    Expr<bool?>? having,
    int? limit,
    int? offset,
    bool? distinct,
    List<Join>? joins,
    List<CteDefinition>? ctes,
  }) => QueryState(
    source,
    predicate: predicate ?? this.predicate,
    order: order ?? this.order,
    group: group ?? this.group,
    having: having ?? this.having,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
    distinct: distinct ?? this.distinct,
    joins: joins ?? this.joins,
    ctes: ctes ?? this.ctes,
    union: union,
  );
}

/// An immutable typed query bound to a SQL context.
///
/// Composition methods return new descriptions. [compile] and [inspect] perform
/// no I/O; reads execute only with a bound database or session. [select] changes
/// the result type without changing the typed source fields.
class Query<R, F extends Fields> {
  /// The compilation or execution context that owns this query.
  final QueryContext database;

  /// @nodoc
  @internal
  final F queryFields;

  /// @nodoc
  @internal
  final QueryState queryState;

  /// @nodoc
  @internal
  final Selection<R> querySelection;

  /// @nodoc
  @internal
  Query.internal(
    this.database,
    this.queryFields,
    this.queryState,
    this.querySelection,
  );

  /// @nodoc
  @internal
  Query<R, F> copyQuery(QueryState state) =>
      Query.internal(database, queryFields, state, querySelection);

  /// Adds a predicate with AND, preserving any existing filter.
  Query<R, F> where(Expr<bool?> Function(F) condition) {
    final next = condition(queryFields);
    return copyQuery(
      queryState.copy(predicate: allOf([?queryState.predicate, next])),
    );
  }

  /// Replaces the query's ordering with the supplied expressions.
  Query<R, F> orderBy(List<OrderTerm> Function(F) order) =>
      copyQuery(queryState.copy(order: List.unmodifiable(order(queryFields))));

  /// Replaces SQL grouping expressions; selected non-aggregates must be grouped.
  Query<R, F> groupBy(List<Expr<Object?>> Function(F) group) =>
      copyQuery(queryState.copy(group: List.unmodifiable(group(queryFields))));

  /// Adds an aggregate filter with AND to the existing HAVING clause.
  Query<R, F> having(Expr<bool?> Function(F) condition) =>
      copyQuery(queryState.copy(having: condition(queryFields)));

  /// Replaces the row limit; count must be nonnegative.
  Query<R, F> take(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return copyQuery(queryState.copy(limit: count));
  }

  /// Replaces the row offset; count must be nonnegative.
  Query<R, F> skip(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return copyQuery(queryState.copy(offset: count));
  }

  /// Removes duplicate SQL projections before any Dart mapping.
  Query<R, F> distinct() => copyQuery(queryState.copy(distinct: true));

  /// Chooses the SQL columns and result type to decode.
  Query<S, F> select<S>(Selection<S> Function(F) selection) =>
      Query.internal(database, queryFields, queryState, selection(queryFields));

  /// Maps decoded rows in Dart. This does not create SQL columns or change
  /// database DISTINCT/UNION semantics; compose SQL set operations first.
  Query<S, F> map<S>(S Function(R) mapper) => Query.internal(
    database,
    queryFields,
    queryState,
    querySelection.map(mapper),
  );

  /// Adds an inner join using an independently created table alias.
  Query<R, F> join<S, G extends Fields>(
    TableAlias<S, G> alias, {
    required Expr<bool?> Function(F, G) on,
  }) => _join(alias, on(queryFields, alias.fields), false);

  /// Adds a left join; use the alias's optional selection for absent rows.
  Query<R, F> leftJoin<S, G extends Fields>(
    TableAlias<S, G> alias, {
    required Expr<bool?> Function(F, G) on,
  }) => _join(alias, on(queryFields, alias.fields), true);
  Query<R, F> _join(
    TableAlias<Object?, Fields> alias,
    Expr<bool?> on,
    bool left,
  ) {
    if (alias.fields.table == queryState.source ||
        queryState.joins.any(
          (j) => j.alias.fields.table == alias.fields.table,
        )) {
      throw const OrmException(
        'QUERY.ALIAS',
        'Create a fresh alias for each table occurrence.',
      );
    }
    return copyQuery(
      queryState.copy(
        joins: List.unmodifiable([...queryState.joins, Join(alias, on, left)]),
      ),
    );
  }

  /// Converts a scalar selection into a nullable SQL subquery.
  ///
  /// Requires `take(1)` or an ungrouped aggregate. This builds an expression and
  /// does not execute the subquery independently.
  Expr<R?> scalar() {
    final selection = querySelection;
    if (selection is! Expr<R>) {
      throw const OrmException(
        'QUERY.SCALAR',
        'A scalar subquery selects one SQL expression.',
      );
    }
    if (queryState.limit != 1 &&
        !(queryState.group.isEmpty && aggregate(selection.expressionNode))) {
      throw const OrmException(
        'QUERY.SCALAR',
        'Use take(1) or an ungrouped aggregate for a scalar subquery.',
      );
    }
    return Expr.internal(SubqueryNode(this), selection.codec.nullable());
  }

  /// Builds a SQL EXISTS expression without executing a read.
  Expr<bool> existsExpression() =>
      Expr.internal(SubqueryNode(this, exists: true), Codecs.boolean);

  /// Names this query as a CTE for further typed composition.
  Cte<R, F> asCte(String name) => Cte.internal(this, name);

  /// @nodoc
  @internal
  (SelectionPlan, RowDecoder<R>) planQuery({bool deduplicate = true}) {
    final plan = SelectionPlan(deduplicate: deduplicate);
    final decode = querySelection.bindSelection(plan);
    if (plan.columns.isEmpty) {
      throw const OrmException(
        'QUERY.EMPTY_SELECTION',
        'Select at least one field.',
      );
    }
    return (plan, decode);
  }

  /// @nodoc
  @internal
  SqlCommand compileQuery(SelectionPlan plan, {ReadTables? reads}) {
    final w = SqlWriter(
      database.dialect,
      {},
      database: database,
      reads: reads,
      exactDecimal: database.capabilities.exactDecimal,
      temporal: database.capabilities.temporal,
    );
    return w.finish(writeQuery(w, plan, decodeResult: true));
  }

  /// @nodoc
  @internal
  String writeQuery(
    SqlWriter w,
    SelectionPlan plan, {
    bool aliasColumns = false,
    bool decodeResult = false,
  }) {
    if (w.mysql &&
        decodeResult &&
        queryState.distinct &&
        plan.columns.any((e) => e.codec.sqlType == 'json')) {
      throw const OrmException(
        'CAPABILITY.JSON_DISTINCT',
        'Project native JSON DISTINCT through a CTE before decoding the result.',
      );
    }
    if (!identical(w.database, database)) {
      throw const OrmException(
        'QUERY.SESSION',
        'Compose queries from the same database or transaction session.',
      );
    }
    final joins = [...queryState.joins, ...plan.joins];
    if (queryState.union == null &&
        !queryState.ctes.any(
          (cte) =>
              queryState.source.schema.namespace == null &&
              cte.name == queryState.source.schema.name,
        )) {
      w.reads?.tables.add(queryState.source.schema);
    }
    for (final join in joins) {
      if (join.alias.cteDefinition == null) {
        w.reads?.tables.add(join.alias.fields.table.schema);
      }
    }
    if (w.dialect != database.dialect) {
      throw const OrmException(
        'QUERY.DIALECT',
        'A statement cannot mix SQL dialects.',
      );
    }
    if (!database.capabilities.windowFunctions &&
        [
          ...plan.columns.map((e) => e.expressionNode),
          ...queryState.order.map((o) => o.expression.expressionNode),
        ].any(window)) {
      throw const OrmException(
        'CAPABILITY.WINDOW',
        'This driver does not support window functions.',
      );
    }
    validateGrouping(queryState.copy(joins: joins), plan);
    final saved = Map<TableRef, String>.of(w.aliases);
    final markers = Set<TableRef>.of(w.leftJoins);
    if (w.aliases.containsKey(queryState.source)) {
      throw const OrmException(
        'QUERY.ALIAS',
        'A nested query needs a fresh source occurrence.',
      );
    }
    w.aliases[queryState.source] = 't${w.aliases.length}';
    final rootAlias = w.aliases[queryState.source]!;
    for (final join in joins) {
      if (w.aliases.containsKey(join.alias.fields.table)) {
        throw const OrmException(
          'QUERY.ALIAS',
          'Create a fresh occurrence for each join.',
        );
      }
      w.aliases[join.alias.fields.table] = 't${w.aliases.length}';
      if (join.left) w.leftJoins.add(join.alias.fields.table);
    }
    final savedAverageInputs = w.averageInputs;
    w.averageInputs = AverageInputs(
      w,
      queryState.source.schema.columns.isEmpty
          ? w.quote(rootAlias)
          : '${w.quote(rootAlias)}.${w.quote(queryState.source.schema.columns.first.name)}',
    );
    try {
      final buffer = StringBuffer();
      final ctes = <String, CteDefinition>{};
      for (final cte in [
        ...queryState.ctes,
        for (final join in joins) ?join.alias.cteDefinition,
      ]) {
        if (ctes.containsKey(cte.name) && !identical(ctes[cte.name], cte)) {
          throw const OrmException(
            'QUERY.CTE',
            'Different CTEs cannot use the same name in one scope.',
          );
        }
        ctes[cte.name] = cte;
      }
      if (ctes.isNotEmpty) {
        buffer.write(
          'WITH ${ctes.values.map((c) => c.writeDefinition(w)).join(', ')} ',
        );
      }
      final stage =
          w.dialect == SqlDialect.postgres &&
              [
                ...plan.columns.map((e) => e.expressionNode),
                ...queryState.order.map((o) => o.expression.expressionNode),
              ].any(_needsWindowStage)
          ? _WindowStage(
              w,
              preWindow: [
                ...plan.columns.map((e) => e.expressionNode),
                ...queryState.order.map((o) => o.expression.expressionNode),
              ].any(_averageWindow),
            )
          : null;
      final columns = <String>[];
      final order = <String>[];
      if (stage != null) w.project = stage.capture;
      try {
        for (var i = 0; i < plan.columns.length; i++) {
          columns.add(
            '${decodeResult ? projection(plan.columns[i], w) : plan.columns[i].expressionNode.write(w)}${aliasColumns ? ' AS ${w.quote('c$i')}' : ''}',
          );
        }
        for (final term in queryState.order) {
          if (stage != null) {
            // PostgreSQL DISTINCT requires ORDER BY to reuse selected expressions.
            final match = plan.columns.indexWhere(
              (e) =>
                  sameSqlNode(e.expressionNode, term.expression.expressionNode),
            );
            order.add(
              match < 0
                  ? term.writeQuery(w)
                  : '${match + 1}${term.orderSuffix}',
            );
          } else {
            order.add(term.writeQuery(w));
          }
        }
      } finally {
        w.project = null;
      }
      buffer.write(
        'SELECT ${stage == null && queryState.distinct ? 'DISTINCT ' : ''}',
      );
      buffer.write(
        stage == null ? columns.join(', ') : stage.inputs.join(', '),
      );
      buffer.write(
        ' FROM ${queryState.union == null ? w.table(queryState.source.schema) : '(${queryState.union!.write(w)})'} AS ${w.quote(rootAlias)}',
      );
      final visible = {...saved, queryState.source: rootAlias};
      for (final join in joins) {
        final ref = join.alias.fields.table;
        final alias = w.aliases[ref]!;
        visible[ref] = alias;
        final check = SqlWriter(
          w.dialect,
          visible,
          database: w.database,
          exactDecimal: w.exactDecimal,
          temporal: w.temporal,
        )..leftJoins.addAll(w.leftJoins.where(visible.containsKey));
        join.on.expressionNode.write(check);
        final table = w.table(ref.schema);
        final source = join.left
            ? '(SELECT *, 1 AS ${w.quote(join.alias.presenceMarker)} FROM $table)'
            : table;
        buffer.write(
          ' ${join.left ? 'LEFT JOIN' : 'JOIN'} $source AS ${w.quote(alias)} ON ${join.on.expressionNode.write(w)}',
        );
      }
      final joinEnd = buffer.length;
      if (queryState.predicate case final predicate?) {
        buffer.write(' WHERE ${predicate.expressionNode.write(w)}');
      }
      if (queryState.group.isNotEmpty) {
        buffer.write(
          ' GROUP BY ${queryState.group.map((e) => e.expressionNode.write(w)).join(', ')}',
        );
      }
      if (queryState.having case final having?) {
        buffer.write(' HAVING ${having.expressionNode.write(w)}');
      }
      if (w.averageInputs!.joins.isNotEmpty) {
        final text = buffer.toString();
        buffer.clear();
        buffer.write(
          '${text.substring(0, joinEnd)}${w.averageInputs!.joins.join()}${text.substring(joinEnd)}',
        );
      }
      if (stage != null) {
        final inner = stage.wrap(buffer.toString());
        buffer.clear();
        buffer.write(
          'SELECT ${queryState.distinct ? 'DISTINCT ' : ''}${columns.join(', ')} FROM ($inner) AS ${w.quote(stage.alias)}',
        );
      }
      if (queryState.order.isNotEmpty) {
        buffer.write(' ORDER BY ${order.join(', ')}');
      }
      if (queryState.limit case final limit?) {
        buffer.write(' LIMIT ${w.parameter(limit)}');
      }
      if (queryState.offset case final offset?) {
        if (queryState.limit == null) {
          if (database.dialect == SqlDialect.sqlite) buffer.write(' LIMIT -1');
          if (w.mysql) buffer.write(' LIMIT 18446744073709551615');
        }
        buffer.write(' OFFSET ${w.parameter(offset)}');
      }
      return buffer.toString();
    } finally {
      w.averageInputs = savedAverageInputs;
      w.aliases
        ..clear()
        ..addAll(saved);
      w.leftJoins
        ..clear()
        ..addAll(markers);
    }
  }

  /// Validates and compiles SQL with separately bound parameters, without I/O.
  SqlCommand compile() => compileQuery(planQuery().$1);

  /// Inspects SQL and conditional relation batches without acquiring a connection.
  /// This does not ask the database optimizer for an execution plan.
  QueryPlan inspect() => inspectQuery(this);

  /// Physical read dependencies used by subscriptions, including relation batches.
  ({Set<TableSchema> tables, bool opaque}) get dependencies {
    final reads = ReadTables()..query(this);
    return (tables: Set.unmodifiable(reads.tables), opaque: reads.opaque);
  }

  /// Rebind the root description to an execution context. Nested queries retain
  /// their original context and are rejected when they do not match.
  Query<R, F> bind(QueryContext context) =>
      Query.internal(context, queryFields, queryState, querySelection);

  /// Executes the query and decodes all selected rows.
  ///
  /// Relation batches reuse the same connection. Use an explicit transaction when
  /// a consistent snapshot across multiple statements is required.
  Future<List<R>> get({ExecutionOptions options = const ExecutionOptions()}) {
    options.check();
    return database.run((connection) async {
      final (plan, decode) = planQuery();
      final command = compileQuery(plan);
      final result = await database.executeOn(
        connection,
        command,
        options: options,
      );
      final rows = await expandRelations(
        database,
        connection,
        plan,
        result.rows,
        options: options,
      );
      return database.observeDecode(
        command.sql,
        rows.length,
        () => [for (final row in rows) decode(row)],
      );
    }, acquire: options.acquisition);
  }

  /// Returns the first selected row, or throws `QUERY.CARDINALITY` if empty.
  ///
  /// Fetches at most one root row. Use [orderBy] for a deterministic first row.
  /// A selected SQL NULL is a row and is returned when `R` is nullable.
  Future<R> first({ExecutionOptions options = const ExecutionOptions()}) async {
    final rows = await take(queryState.limit == 0 ? 0 : 1)
        .get(options: options);
    if (rows.isEmpty) {
      throw const OrmException(
        'QUERY.CARDINALITY',
        'Expected a row, received none.',
      );
    }
    return rows.first;
  }

  /// Returns the first selected row, or null when the query is empty.
  ///
  /// Fetches at most one root row. A nullable selection also returns null for a
  /// row containing SQL NULL; select a Record to distinguish these cases.
  Future<R?> firstOrNull({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final rows = await take(queryState.limit == 0 ? 0 : 1)
        .get(options: options);
    return rows.isEmpty ? null : rows.first;
  }

  /// Returns exactly one selected row or throws `QUERY.CARDINALITY`.
  ///
  /// Fetches at most two root rows to detect an ambiguous result.
  Future<R> single({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final rows = await take(
      queryState.limit == null || queryState.limit! > 2 ? 2 : queryState.limit!,
    ).get(options: options);
    if (rows.length != 1) {
      throw OrmException(
        'QUERY.CARDINALITY',
        'Expected one row, received ${rows.length}.',
      );
    }
    return rows.single;
  }

  /// Returns the only selected row, or null when empty.
  ///
  /// Throws `QUERY.CARDINALITY` for more than one row, fetching at most two.
  Future<R?> singleOrNull({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final rows = await take(
      queryState.limit == null || queryState.limit! > 2 ? 2 : queryState.limit!,
    ).get(options: options);
    if (rows.length > 1) {
      throw OrmException(
        'QUERY.CARDINALITY',
        'Expected at most one row, received ${rows.length}.',
      );
    }
    return rows.firstOrNull;
  }

  /// Counts the query's result rows, including its limit, offset and grouping.
  Future<int> count({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final inner = compile();
    final result = await database.execute(
      SqlCommand(
        'SELECT COUNT(*) FROM (${inner.sql}) AS ${SqlWriter(database.dialect, {}).quote('orm_count')}',
        inner.parameters,
      ),
      options: options,
    );
    return Codecs.integer.decode(result.rows.single.single);
  }

  /// Checks whether the current query yields at least one row.
  Future<bool> exists({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final inner = take(queryState.limit == 0 ? 0 : 1).compile();
    final result = await database.execute(
      SqlCommand('SELECT EXISTS (${inner.sql})', inner.parameters),
      options: options,
    );
    return Codecs.boolean.decode(result.rows.single.single);
  }

  /// Prepares an update; call the mutation's execute or returning method.
  Mutation<F> update(List<Assignment> Function(F) assignments) =>
      Mutation.internal(
        database,
        queryFields,
        queryState,
        MutationKind.update,
        assignments(queryFields),
      );

  /// Prepares a delete; no SQL runs until the mutation is executed.
  Mutation<F> delete() => Mutation.internal(
    database,
    queryFields,
    queryState,
    MutationKind.delete,
    const [],
  );
}

// A scalar SQL subquery cannot contain an enclosing query's window function.
// Evaluate its inputs in that query, then perform decimal division/rounding in
// an outer projection. Filtering, grouping and windows stay inside; DISTINCT,
// ordering and pagination apply to the final values. This remains one statement.
// Window averages additionally share their input before the native component
// windows run, including when the input is itself a grouped aggregate.
bool _needsWindowStage(SqlNode node) =>
    node is WindowNode && node.function is DecimalAverage ||
    node is DecimalRatio && children(node).any(window) ||
    children(node).any(_needsWindowStage);

bool _averageWindow(SqlNode node) =>
    node is WindowNode && node.function is DecimalAverage ||
    children(node).any(_averageWindow);

bool _averageInput(SqlNode node) =>
    node is AverageInput || children(node).any(_averageInput);

final class _WindowStage(
  final SqlWriter writer, {
  final bool preWindow = false,
}) {
  late final String alias = '_orm_window_${writer.aliases.length}';
  late final String inputAlias = '_orm_inputs_${writer.aliases.length}';
  final List<String> inputs = [];
  final List<String> windows = [];
  final Map<AverageInput, String> _shared = {};

  String wrap(String sql) => preWindow
      ? 'SELECT ${windows.join(', ')} FROM ($sql) AS ${writer.quote(inputAlias)}'
      : sql;

  String? capture(SqlNode node) {
    if (_needsWindowStage(node)) return null;
    final output = preWindow ? windows : inputs;
    final index = output.length;
    final saved = writer.project;
    writer.project = preWindow ? _capturePre : null;
    try {
      final sql = preWindow ? node.write(writer) : node.writeSql(writer);
      output.add('$sql AS ${writer.quote('w$index')}');
    } finally {
      writer.project = saved;
    }
    return '${writer.quote(alias)}.${writer.quote('w$index')}';
  }

  String? _capturePre(SqlNode node) {
    if (node is AverageInput) {
      return _shared.putIfAbsent(node, () => _input(node.child));
    }
    if (node is WindowNode || _averageInput(node)) return null;
    return _input(node);
  }

  String _input(SqlNode node) {
    final index = inputs.length;
    final saved = writer.project;
    writer.project = null;
    try {
      inputs.add('${node.writeSql(writer)} AS ${writer.quote('p$index')}');
    } finally {
      writer.project = saved;
    }
    return '${writer.quote(inputAlias)}.${writer.quote('p$index')}';
  }
}

/// Typed access to a table, including full-row reads and prepared inserts.
class TableSet<R, F extends Fields> extends Query<R, F> {
  /// The table definition used to create fields and decode full rows.
  final Table<R, F> definition;

  /// Binds a table definition to a compilation or execution context.
  TableSet(QueryContext database, Table<R, F> definition)
    : this.internal(
        database,
        definition,
        definition.createFields(TableRef(definition.schema)),
      );

  /// @nodoc
  @internal
  TableSet.internal(QueryContext database, this.definition, F fields)
    : super.internal(
        database,
        fields,
        QueryState(fields.table),
        definition.selectRow(fields),
      );

  /// Prepares one insert, evaluating omitted client defaults once now.
  Mutation<F> insert(List<Assignment> Function(F) assignments) =>
      Mutation.internal(
        database,
        queryFields,
        queryState,
        MutationKind.insert,
        _insertDefaults(assignments(queryFields)),
        fieldsFactory: definition.createFields,
      );

  /// Prepares rows for a parameter-aware batch insert.
  ///
  /// Client defaults run once per omitted field during preparation. Execution uses
  /// one transaction across all generated statement chunks.
  BatchInsert<F> insertMany<T>(
    Iterable<T> rows,
    List<Assignment> Function(F, T) values,
  ) => BatchInsert.internal(database, queryFields, queryState, [
    for (final row in rows)
      List<Assignment>.unmodifiable(_insertDefaults(values(queryFields, row))),
  ]);

  List<Assignment> _insertDefaults(List<Assignment> assignments) {
    final defaults = definition.schema.clientDefaults;
    if (defaults.isEmpty) return assignments;
    final assigned = {for (final a in assignments) a.field.definition.name};
    return [
      ...assignments,
      for (final column in defaults)
        if (!assigned.contains(column.name))
          queryFields.column(column).set(column.clientDefault!()),
    ];
  }

  /// Inserts and returns a complete row.
  ///
  /// Uses RETURNING when supported. Otherwise inserts and reads the primary key on
  /// one transaction; keys must be literal values or one generated identity.
  Future<R> createRow(
    List<Assignment> Function(F) assignments, {
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    final mutation = insert(assignments);
    if (database.capabilities.returning) {
      return mutation.returning(definition.selectRow).single(options: options);
    }
    final keys = definition.schema.primaryKey;
    final values = <String, ParameterNode>{};
    final generated = <String>{};
    for (final key in keys) {
      final column = definition.schema.columns.firstWhere((c) => c.name == key);
      final assignment = mutation.writeAssignments
          .where((a) => a.field.definition.name == key)
          .firstOrNull;
      if (assignment?.assignedValue case final ParameterNode parameter) {
        values[key] = parameter;
      } else if (column.generated && assignment?.assignedValue == null) {
        generated.add(key);
      } else {
        throw const OrmException(
          'CAPABILITY.CREATE_KEY',
          'Reading an inserted row without RETURNING requires literal primary keys or a generated identity.',
        );
      }
    }
    if (keys.isEmpty || generated.length > 1) {
      throw const OrmException(
        'CAPABILITY.CREATE_KEY',
        'Reading an inserted row requires a primary key and at most one generated identity.',
      );
    }
    Future<R> create(QueryContext tx) async {
      try {
        final bound = Mutation.internal(
          tx,
          mutation.queryFields,
          mutation.queryState,
          mutation.mutationKind,
          mutation.writeAssignments,
          fieldsFactory: mutation.fieldsFactory,
        );
        final result = await tx.executeCommand(
          bound.compile(),
          options: options,
          changedTables: [definition.schema],
          affectedOnly: true,
          cascade: false,
        );
        if (generated.isNotEmpty) {
          if (result.lastInsertId == null) {
            throw const OrmException(
              'DRIVER.IDENTITY',
              'The driver did not return the generated identity.',
            );
          }
          values[generated.single] = ParameterNode(result.lastInsertId);
        }
        SqlNode? predicate;
        for (final key in keys) {
          final equal = BinaryNode(
            ColumnNode(queryState.source, key),
            '=',
            values[key]!,
          );
          predicate = predicate == null
              ? equal
              : BinaryNode(predicate, 'AND', equal);
        }
        return await Query.internal(
          tx,
          queryFields,
          queryState.copy(
            predicate: Expr<bool?>.internal(
              predicate!,
              Codecs.boolean.nullable(),
            ),
          ),
          definition.selectRow(queryFields),
        ).single(options: options);
      } catch (_) {
        tx.markFailed();
        rethrow;
      }
    }

    return database.inTransaction
        ? create(database)
        : database.atomic(create, acquire: options.acquisition);
  }
}
