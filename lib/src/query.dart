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
  const _QueryState(
    this.source, {
    this.predicate,
    this.order = const [],
    this.group = const [],
    this.having,
    this.limit,
    this.offset,
    this.distinct = false,
  });
  _QueryState copy({
    Expr<bool?>? predicate,
    List<OrderTerm>? order,
    List<Expr<Object?>>? group,
    Expr<bool?>? having,
    int? limit,
    int? offset,
    bool? distinct,
  }) => _QueryState(
    source,
    predicate: predicate ?? this.predicate,
    order: order ?? this.order,
    group: group ?? this.group,
    having: having ?? this.having,
    limit: limit ?? this.limit,
    offset: offset ?? this.offset,
    distinct: distinct ?? this.distinct,
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

  (_SelectionPlan, _Decoder<R>) _plan() {
    final plan = _SelectionPlan();
    final decode = _selection._bind(plan);
    if (plan.columns.isEmpty) {
      throw const OrmException(
        'QUERY.EMPTY_SELECTION',
        'Select at least one field.',
      );
    }
    return (plan, decode);
  }

  SqlCommand _compile(_SelectionPlan plan) {
    final w = _Writer(database.dialect, {_state.source: 't0'});
    final buffer = StringBuffer('SELECT ${_state.distinct ? 'DISTINCT ' : ''}');
    buffer.write(plan.columns.map((e) => e._node.write(w)).join(', '));
    buffer.write(' FROM ${w.quote(_state.source.schema.name)} AS "t0"');
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
    if (_state.order.isNotEmpty) {
      buffer.write(
        ' ORDER BY ${_state.order.map((o) => '${o.expression._node.write(w)} ${o.descending ? 'DESC' : 'ASC'}').join(', ')}',
      );
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
    return SqlCommand(buffer.toString(), w.parameters);
  }

  SqlCommand compile() => _compile(_plan().$1);

  Future<List<R>> get() => database._run((connection) async {
    final (plan, decode) = _plan();
    final result = await database._execute(connection, _compile(plan));
    final rows = await _expandRelations(
      database,
      connection,
      plan,
      result.rows,
    );
    return [for (final row in rows) decode(row)];
  });

  Future<R?> first() async {
    final rows = await take(_state.limit == 0 ? 0 : 1).get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<R> single() async {
    final rows = await take(
      _state.limit == null || _state.limit! > 2 ? 2 : _state.limit!,
    ).get();
    if (rows.length != 1) {
      throw OrmException(
        'QUERY.CARDINALITY',
        'Expected one row, received ${rows.length}.',
      );
    }
    return rows.single;
  }

  Future<int> count() async {
    final inner = compile();
    final result = await database.execute(
      SqlCommand(
        'SELECT COUNT(*) FROM (${inner.sql}) AS "orm_count"',
        inner.parameters,
      ),
    );
    return Codecs.integer.decode(result.rows.single.single);
  }

  Future<bool> exists() async {
    final inner = take(_state.limit == 0 ? 0 : 1).compile();
    final result = await database.execute(
      SqlCommand('SELECT EXISTS (${inner.sql})', inner.parameters),
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
    assignments(_fields),
    createFields: definition.createFields,
  );
  BatchInsert<F> insertMany<T>(
    Iterable<T> rows,
    List<Assignment> Function(F, T) values,
  ) => BatchInsert._(database, _fields, _state, [
    for (final row in rows) List<Assignment>.unmodifiable(values(_fields, row)),
  ]);
  Future<R> createRow(List<Assignment> Function(F) assignments) =>
      insert(assignments).returning(definition.selectRow).single();
}
