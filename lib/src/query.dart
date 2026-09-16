part of '../orm.dart';

final class _QueryState {
  final TableRef source;
  final Expr<bool?>? predicate;
  final List<OrderTerm> order;
  final List<Expr<Object?>> group;
  final Expr<bool?>? having;
  final int? limit;
  final int? offset;
  final bool distinct;
  final List<_Join> joins;
  final List<_CteDefinition> ctes;
  final _UnionSource? union;
  const _QueryState(
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
  _QueryState copy({
    Expr<bool?>? predicate,
    List<OrderTerm>? order,
    List<Expr<Object?>>? group,
    Expr<bool?>? having,
    int? limit,
    int? offset,
    bool? distinct,
    List<_Join>? joins,
    List<_CteDefinition>? ctes,
  }) => _QueryState(
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

class Query<R, F extends Fields> {
  final Database<Backend> database;
  final F _fields;
  final _QueryState _state;
  final Selection<R> _selection;
  Query._(this.database, this._fields, this._state, this._selection);

  Query<R, F> _copy(_QueryState state) =>
      Query._(database, _fields, state, _selection);
  Query<R, F> where(Expr<bool?> Function(F) condition) {
    final next = condition(_fields);
    return _copy(_state.copy(predicate: _state.predicate?.and(next) ?? next));
  }

  Query<R, F> orderBy(List<OrderTerm> Function(F) order) =>
      _copy(_state.copy(order: List.unmodifiable(order(_fields))));
  Query<R, F> groupBy(List<Expr<Object?>> Function(F) group) =>
      _copy(_state.copy(group: List.unmodifiable(group(_fields))));
  Query<R, F> having(Expr<bool?> Function(F) condition) =>
      _copy(_state.copy(having: condition(_fields)));
  Query<R, F> take(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return _copy(_state.copy(limit: count));
  }

  Query<R, F> skip(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return _copy(_state.copy(offset: count));
  }

  Query<R, F> distinct() => _copy(_state.copy(distinct: true));
  Query<S, F> select<S>(Selection<S> Function(F) selection) =>
      Query._(database, _fields, _state, selection(_fields));

  /// Maps decoded rows in Dart. This does not create SQL columns or change
  /// database DISTINCT/UNION semantics; compose SQL set operations first.
  Query<S, F> map<S>(S Function(R) mapper) =>
      Query._(database, _fields, _state, _selection.map(mapper));

  Query<R, F> join<S, G extends Fields>(
    TableAlias<S, G> alias, {
    required Expr<bool?> Function(F, G) on,
  }) => _join(alias, on(_fields, alias.fields), false);
  Query<R, F> leftJoin<S, G extends Fields>(
    TableAlias<S, G> alias, {
    required Expr<bool?> Function(F, G) on,
  }) => _join(alias, on(_fields, alias.fields), true);
  Query<R, F> _join(
    TableAlias<Object?, Fields> alias,
    Expr<bool?> on,
    bool left,
  ) {
    if (alias.fields.table == _state.source ||
        _state.joins.any((j) => j.alias.fields.table == alias.fields.table)) {
      throw const OrmException(
        'QUERY.ALIAS',
        'Create a fresh alias for each table occurrence.',
      );
    }
    return _copy(
      _state.copy(
        joins: List.unmodifiable([..._state.joins, _Join(alias, on, left)]),
      ),
    );
  }

  Expr<R?> scalar() {
    final selection = _selection;
    if (selection is! Expr<R>) {
      throw const OrmException(
        'QUERY.SCALAR',
        'A scalar subquery selects one SQL expression.',
      );
    }
    if (_state.limit != 1 &&
        !(_state.group.isEmpty && _aggregate(selection._node))) {
      throw const OrmException(
        'QUERY.SCALAR',
        'Use take(1) or an ungrouped aggregate for a scalar subquery.',
      );
    }
    return Expr._(_Subquery(this), selection.codec.nullable());
  }

  Expr<bool> existsExpression() =>
      Expr._(_Subquery(this, exists: true), Codecs.boolean);
  Cte<R, F> asCte(String name) => Cte._(this, name);

  (_SelectionPlan, _Decoder<R>) _plan({bool deduplicate = true}) {
    final plan = _SelectionPlan(deduplicate: deduplicate);
    final decode = _selection._bind(plan);
    if (plan.columns.isEmpty) {
      throw const OrmException(
        'QUERY.EMPTY_SELECTION',
        'Select at least one field.',
      );
    }
    return (plan, decode);
  }

  SqlCommand _compile(_SelectionPlan plan, {_ReadTables? reads}) {
    final w = _Writer(
      database.dialect,
      {},
      database: database,
      reads: reads,
      exactDecimal: database.capabilities.exactDecimal,
      temporal: database.capabilities.temporal,
    );
    return SqlCommand(_write(w, plan), w.parameters);
  }

  String _write(_Writer w, _SelectionPlan plan, {bool aliasColumns = false}) {
    if (!identical(w.database, database)) {
      throw const OrmException(
        'QUERY.SESSION',
        'Compose queries from the same database or transaction session.',
      );
    }
    final joins = [..._state.joins, ...plan.joins];
    if (_state.union == null &&
        !_state.ctes.any((cte) => cte.name == _state.source.schema.name)) {
      w.reads?.tables.add(_state.source.schema);
    }
    for (final join in joins) {
      if (join.alias._cte == null) {
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
          ...plan.columns.map((e) => e._node),
          ..._state.order.map((o) => o.expression._node),
        ].any(_window)) {
      throw const OrmException(
        'CAPABILITY.WINDOW',
        'This driver does not support window functions.',
      );
    }
    _validateGrouping(_state.copy(joins: joins), plan);
    final saved = Map<TableRef, String>.of(w.aliases);
    final markers = Set<TableRef>.of(w.leftJoins);
    if (w.aliases.containsKey(_state.source)) {
      throw const OrmException(
        'QUERY.ALIAS',
        'A nested query needs a fresh source occurrence.',
      );
    }
    w.aliases[_state.source] = 't${w.aliases.length}';
    final rootAlias = w.aliases[_state.source]!;
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
    w.averageInputs = _AverageInputs(
      w,
      _state.source.schema.columns.isEmpty
          ? w.quote(rootAlias)
          : '${w.quote(rootAlias)}.${w.quote(_state.source.schema.columns.first.name)}',
    );
    try {
      final buffer = StringBuffer();
      final ctes = <String, _CteDefinition>{};
      for (final cte in [
        ..._state.ctes,
        for (final join in joins) ?join.alias._cte,
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
          'WITH ${ctes.values.map((c) => c._writeDefinition(w)).join(', ')} ',
        );
      }
      final stage =
          w.dialect == SqlDialect.postgres &&
              [
                ...plan.columns.map((e) => e._node),
                ..._state.order.map((o) => o.expression._node),
              ].any(_needsWindowStage)
          ? _WindowStage(
              w,
              preWindow: [
                ...plan.columns.map((e) => e._node),
                ..._state.order.map((o) => o.expression._node),
              ].any(_averageWindow),
            )
          : null;
      final columns = <String>[];
      final order = <String>[];
      if (stage != null) w.project = stage.capture;
      try {
        for (var i = 0; i < plan.columns.length; i++) {
          columns.add(
            '${plan.columns[i]._node.write(w)}${aliasColumns ? ' AS ${w.quote('c$i')}' : ''}',
          );
        }
        for (final term in _state.order) {
          if (stage != null) {
            // PostgreSQL DISTINCT requires ORDER BY to reuse selected expressions.
            final match = plan.columns.indexWhere(
              (e) => _sameSqlNode(e._node, term.expression._node),
            );
            order.add(
              match < 0 ? term._write(w) : '${match + 1}${term._suffix}',
            );
          } else {
            order.add(term._write(w));
          }
        }
      } finally {
        w.project = null;
      }
      buffer.write(
        'SELECT ${stage == null && _state.distinct ? 'DISTINCT ' : ''}',
      );
      buffer.write(
        stage == null ? columns.join(', ') : stage.inputs.join(', '),
      );
      buffer.write(
        ' FROM ${_state.union == null ? w.quote(_state.source.schema.name) : '(${_state.union!.write(w)})'} AS ${w.quote(rootAlias)}',
      );
      final visible = {...saved, _state.source: rootAlias};
      for (final join in joins) {
        final ref = join.alias.fields.table;
        final alias = w.aliases[ref]!;
        visible[ref] = alias;
        final check = _Writer(
          w.dialect,
          visible,
          database: w.database,
          exactDecimal: w.exactDecimal,
          temporal: w.temporal,
        )..leftJoins.addAll(w.leftJoins.where(visible.containsKey));
        join.on._node.write(check);
        final table = w.quote(ref.schema.name);
        final source = join.left
            ? '(SELECT *, 1 AS ${w.quote(join.alias._marker)} FROM $table)'
            : table;
        buffer.write(
          ' ${join.left ? 'LEFT JOIN' : 'JOIN'} $source AS ${w.quote(alias)} ON ${join.on._node.write(w)}',
        );
      }
      final joinEnd = buffer.length;
      if (_state.predicate case final predicate?) {
        buffer.write(' WHERE ${predicate._node.write(w)}');
      }
      if (_state.group.isNotEmpty) {
        buffer.write(
          ' GROUP BY ${_state.group.map((e) => e._node.write(w)).join(', ')}',
        );
      }
      if (_state.having case final having?) {
        buffer.write(' HAVING ${having._node.write(w)}');
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
          'SELECT ${_state.distinct ? 'DISTINCT ' : ''}${columns.join(', ')} FROM ($inner) AS ${w.quote(stage.alias)}',
        );
      }
      if (_state.order.isNotEmpty) {
        buffer.write(' ORDER BY ${order.join(', ')}');
      }
      if (_state.limit case final limit?) {
        buffer.write(' LIMIT ${w.parameter(limit)}');
      }
      if (_state.offset case final offset?) {
        if (_state.limit == null && database.dialect == SqlDialect.sqlite) {
          buffer.write(' LIMIT -1');
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

  SqlCommand compile() => _compile(_plan().$1);

  /// Inspects SQL and conditional relation batches without acquiring a connection.
  /// This does not ask the database optimizer for an execution plan.
  QueryPlan inspect() => _inspectQuery(this);

  Future<List<R>> get({ExecutionOptions options = const ExecutionOptions()}) {
    options.check();
    return database._run((connection) async {
      final (plan, decode) = _plan();
      final command = _compile(plan);
      final result = await database._execute(
        connection,
        command,
        options: options,
      );
      final rows = await _expandRelations(
        database,
        connection,
        plan,
        result.rows,
        options: options,
      );
      return database._observeDecode(
        command.sql,
        rows.length,
        () => [for (final row in rows) decode(row)],
      );
    }, acquire: options._acquisition);
  }

  Future<R?> first({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final rows = await take(_state.limit == 0 ? 0 : 1).get(options: options);
    return rows.isEmpty ? null : rows.first;
  }

  Future<R> single({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final rows = await take(
      _state.limit == null || _state.limit! > 2 ? 2 : _state.limit!,
    ).get(options: options);
    if (rows.length != 1) {
      throw OrmException(
        'QUERY.CARDINALITY',
        'Expected one row, received ${rows.length}.',
      );
    }
    return rows.single;
  }

  Future<int> count({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final inner = compile();
    final result = await database.execute(
      SqlCommand(
        'SELECT COUNT(*) FROM (${inner.sql}) AS "orm_count"',
        inner.parameters,
      ),
      options: options,
    );
    return Codecs.integer.decode(result.rows.single.single);
  }

  Future<bool> exists({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final inner = take(_state.limit == 0 ? 0 : 1).compile();
    final result = await database.execute(
      SqlCommand('SELECT EXISTS (${inner.sql})', inner.parameters),
      options: options,
    );
    return Codecs.boolean.decode(result.rows.single.single);
  }

  Mutation<F> update(List<Assignment> Function(F) assignments) => Mutation._(
    database,
    _fields,
    _state,
    _MutationKind.update,
    assignments(_fields),
  );
  Mutation<F> delete() =>
      Mutation._(database, _fields, _state, _MutationKind.delete, const []);
}

// A scalar SQL subquery cannot contain an enclosing query's window function.
// Evaluate its inputs in that query, then perform decimal division/rounding in
// an outer projection. Filtering, grouping and windows stay inside; DISTINCT,
// ordering and pagination apply to the final values. This remains one statement.
// Window averages additionally share their input before the native component
// windows run, including when the input is itself a grouped aggregate.
bool _needsWindowStage(_Node node) =>
    node is _WindowNode && node.function is _DecimalAverage ||
    node is _DecimalRatio && _children(node).any(_window) ||
    _children(node).any(_needsWindowStage);

bool _averageWindow(_Node node) =>
    node is _WindowNode && node.function is _DecimalAverage ||
    _children(node).any(_averageWindow);
bool _averageInput(_Node node) =>
    node is _AverageInput || _children(node).any(_averageInput);

final class _WindowStage(final _Writer writer, {final bool preWindow = false}) {
  late final String alias = '_orm_window_${writer.aliases.length}';
  late final String inputAlias = '_orm_inputs_${writer.aliases.length}';
  final List<String> inputs = [];
  final List<String> windows = [];
  final Map<_AverageInput, String> _shared = {};

  String wrap(String sql) => preWindow
      ? 'SELECT ${windows.join(', ')} FROM ($sql) AS ${writer.quote(inputAlias)}'
      : sql;

  String? capture(_Node node) {
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

  String? _capturePre(_Node node) {
    if (node is _AverageInput) {
      return _shared.putIfAbsent(node, () => _input(node.child));
    }
    if (node is _WindowNode || _averageInput(node)) return null;
    return _input(node);
  }

  String _input(_Node node) {
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

class TableSet<R, F extends Fields> extends Query<R, F> {
  final Table<R, F> definition;
  TableSet(Database<Backend> database, Table<R, F> definition)
    : this._(
        database,
        definition,
        definition.createFields(TableRef(definition.schema)),
      );
  TableSet._(Database<Backend> database, this.definition, F fields)
    : super._(
        database,
        fields,
        _QueryState(fields.table),
        definition.selectRow(fields),
      );

  Mutation<F> insert(List<Assignment> Function(F) assignments) => Mutation._(
    database,
    _fields,
    _state,
    _MutationKind.insert,
    _insertDefaults(assignments(_fields)),
    createFields: definition.createFields,
  );
  BatchInsert<F> insertMany<T>(
    Iterable<T> rows,
    List<Assignment> Function(F, T) values,
  ) => BatchInsert._(database, _fields, _state, [
    for (final row in rows)
      List<Assignment>.unmodifiable(_insertDefaults(values(_fields, row))),
  ]);

  List<Assignment> _insertDefaults(List<Assignment> assignments) {
    final defaults = definition.schema._clientDefaults;
    if (defaults.isEmpty) return assignments;
    final assigned = {for (final a in assignments) a.field.definition.name};
    return [
      ...assignments,
      for (final column in defaults)
        if (!assigned.contains(column.name))
          _fields.column(column).set(column.clientDefault!()),
    ];
  }

  Future<R> createRow(
    List<Assignment> Function(F) assignments, {
    ExecutionOptions options = const ExecutionOptions(),
  }) =>
      insert(assignments)
          .returning(definition.selectRow)
          .single(options: options);
}
