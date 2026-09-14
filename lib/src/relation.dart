part of '../orm.dart';

/// A relationship is a query description. Constructing or selecting it performs
/// no I/O. List results are loaded in batches on the root query's connection.
final class Relation<R, F extends Fields> {
  final List<Expr<Object?>> _parent;
  final List<Field<Object?>> _child;
  final F _fields;
  final _QueryState _state;
  final Selection<R> _selection;

  factory Relation(
    Table<R, F> target, {
    required List<Expr<Object?>> parent,
    required List<Field<Object?>> Function(F) child,
  }) {
    final fields = target.createFields(TableRef(target.schema));
    final keys = child(fields);
    if (parent.isEmpty || parent.length != keys.length) {
      throw ArgumentError('Relationship keys need equal, non-zero arity.');
    }
    return Relation._(
      List.unmodifiable(parent),
      List.unmodifiable(keys),
      fields,
      _QueryState(fields.table),
      target.selectRow(fields),
    );
  }
  Relation._(
    this._parent,
    this._child,
    this._fields,
    this._state,
    this._selection,
  );
  Relation<R, F> _copy(_QueryState state) =>
      Relation._(_parent, _child, _fields, state, _selection);
  Relation<R, F> where(Expr<bool?> Function(F) predicate) {
    final next = predicate(_fields);
    return _copy(_state.copy(predicate: _state.predicate?.and(next) ?? next));
  }

  Relation<R, F> orderBy(List<OrderTerm> Function(F) order) =>
      _copy(_state.copy(order: List.unmodifiable(order(_fields))));
  Relation<R, F> take(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return _copy(_state.copy(limit: count));
  }

  Relation<R, F> skip(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return _copy(_state.copy(offset: count));
  }

  Relation<S, F> select<S>(Selection<S> Function(F) selection) =>
      Relation._(_parent, _child, _fields, _state, selection(_fields));
  Selection<List<R>> many() => _RelationSelection(this);
  Selection<R?> one() =>
      _copy(
        _state.copy(
          order: _state.order.isEmpty
              ? [for (final key in _child) key.asc()]
              : _state.order,
          limit: _state.limit != null && _state.limit! < 2 ? _state.limit : 2,
        ),
      ).many().map((rows) {
        if (rows.length > 1) {
          throw const OrmException(
            'RELATION.CARDINALITY',
            'Expected at most one related row.',
          );
        }
        return rows.firstOrNull;
      });
  Selection<R> required() => one().map((row) {
    if (row == null) {
      throw const OrmException(
        'RELATION.MISSING',
        'A required related row is not visible.',
      );
    }
    return row;
  });
  Expr<bool> any() => Expr._(_RelationSubquery(this, false), Codecs.boolean);
  Expr<bool?> none() => any().not();
  Expr<bool?> every(Expr<bool?> Function(F) condition) {
    final conditionNode = condition(_fields)._node;
    return where(
      (_) => Expr._(
        _Unary('IS NOT TRUE', conditionNode, postfix: true),
        Codecs.boolean,
      ),
    ).none();
  }

  Expr<int> count() => Expr._(_RelationSubquery(this, true), Codecs.integer);
}

final class _RelationSubquery(
  final Relation<Object?, Fields> relation,
  final bool count,
) extends _Node {
  @override
  String write(_Writer w) {
    if (relation._state.limit != null || relation._state.offset != null) {
      throw const OrmException(
        'RELATION.AGGREGATE',
        'Apply relation count/any/every before pagination.',
      );
    }
    final source = relation._state.source;
    final alias = 't${w.aliases.length}';
    w.aliases[source] = alias;
    try {
      final predicates = [
        for (var i = 0; i < relation._child.length; i++)
          _Binary(
            relation._child[i]._node,
            '=',
            relation._parent[i]._node,
          ).write(w),
        if (relation._state.predicate case final p?) p._node.write(w),
      ];
      final query =
          'SELECT ${count ? 'COUNT(*)' : '1'} FROM ${w.quote(source.schema.name)} AS ${w.quote(alias)} WHERE ${predicates.join(' AND ')}';
      return count ? '($query)' : 'EXISTS ($query)';
    } finally {
      w.aliases.remove(source);
    }
  }
}

final class _RelationSelection<R, F extends Fields>(
  final Relation<R, F> relation,
) extends Selection<List<R>> {
  @override
  _Decoder<List<R>> _bind(_SelectionPlan plan) {
    final index = plan.relations.length;
    final parentIndices = [
      for (final key in relation._parent) plan.column(key),
    ];
    plan.relations.add(_TypedRelationBinding(relation, parentIndices));
    return (row) => row[plan.columns.length + index] as List<R>;
  }
}

abstract class _RelationBinding {
  Future<List<Object?>> load(
    Database<Backend> db,
    SqlConnection connection,
    List<List<Object?>> parents,
  );
}

final class _TypedRelationBinding<R, F extends Fields>(
  final Relation<R, F> relation,
  final List<int> parentIndices,
) extends _RelationBinding {
  @override
  Future<List<Object?>> load(
    Database<Backend> db,
    SqlConnection connection,
    List<List<Object?>> parents,
  ) async {
    final keys = <_RelationKey>{};
    final parentKeys = [
      for (final row in parents)
        _RelationKey([for (final i in parentIndices) row[i]]),
    ];
    for (final key in parentKeys) {
      if (!key.values.contains(null)) keys.add(key);
    }
    final grouped = <_RelationKey, List<R>>{};
    if (keys.isEmpty || relation._state.limit == 0) {
      return [for (final _ in parents) <R>[]];
    }
    final plan = _SelectionPlan();
    final decode = relation._selection._bind(plan);
    final childIndices = [for (final key in relation._child) plan.column(key)];
    final all = keys.toList();
    final baseCount =
        _compile(db, plan, [all.first]).parameters.length -
        relation._child.length;
    final chunkSize =
        (db.capabilities.maxParameters - baseCount) ~/ relation._child.length;
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
      final result = await db._execute(
        connection,
        _compile(db, plan, all.sublist(offset, end)),
      );
      final rows = await _expandRelations(db, connection, plan, result.rows);
      for (final row in rows) {
        final key = _RelationKey([for (final i in childIndices) row[i]]);
        (grouped[key] ??= []).add(decode(row));
      }
    }
    return [
      for (final key in parentKeys) List<R>.unmodifiable(grouped[key] ?? <R>[]),
    ];
  }

  SqlCommand _compile(
    Database<Backend> db,
    _SelectionPlan plan,
    List<_RelationKey> keys,
  ) {
    final state = relation._state;
    final w = _Writer(db.dialect, {state.source: 't0'});
    final predicates = <String>[];
    if (relation._child.length == 1) {
      predicates.add(
        _In(relation._child.single._node, [
          for (final key in keys) _Parameter(key.values.single),
        ]).write(w),
      );
    } else {
      predicates.add(
        '(${keys.map((key) => '(${[for (var i = 0; i < key.values.length; i++) _Binary(relation._child[i]._node, '=', _Parameter(key.values[i])).write(w)].join(' AND ')})').join(' OR ')})',
      );
    }
    if (state.predicate case final predicate?) {
      predicates.add(predicate._node.write(w));
    }
    // Compile WHERE before SELECT is fine for numbered parameters; SQLite '?'
    // binds by textual order, so use explicit numbered placeholders everywhere.
    final selected = [
      for (var i = 0; i < plan.columns.length; i++)
        '${plan.columns[i]._node.write(w)} AS "c$i"',
    ];
    final paginated = state.limit != null || state.offset != null;
    final order = state.order.toList();
    if (paginated) {
      if (!db.capabilities.windowFunctions) {
        throw const OrmException(
          'CAPABILITY.WINDOW',
          'Per-parent pagination needs window functions.',
        );
      }
      if (order.isEmpty) {
        throw const OrmException(
          'RELATION.ORDER',
          'Per-parent pagination requires explicit ordering.',
        );
      }
      final partition = relation._child.map((e) => e._node.write(w)).join(', ');
      selected.add(
        'ROW_NUMBER() OVER (PARTITION BY $partition ORDER BY ${order.map((o) => '${o.expression._node.write(w)} ${o.descending ? 'DESC' : 'ASC'}').join(', ')}) AS "orm_rank"',
      );
    }
    var query =
        'SELECT ${selected.join(', ')} FROM ${w.quote(state.source.schema.name)} AS "t0" WHERE ${predicates.join(' AND ')}';
    if (paginated) {
      final offset = state.offset ?? 0;
      query =
          'SELECT ${[for (var i = 0; i < plan.columns.length; i++) '"c$i"'].join(', ')} FROM ($query) AS "orm_partition" WHERE "orm_rank" > ${w.parameter(offset)}';
      if (state.limit case final limit?) {
        query += ' AND "orm_rank" <= ${w.parameter(offset + limit)}';
      }
      query += ' ORDER BY "orm_rank"';
    } else if (order.isNotEmpty) {
      query +=
          ' ORDER BY ${order.map((o) => '${o.expression._node.write(w)} ${o.descending ? 'DESC' : 'ASC'}').join(', ')}';
    }
    return SqlCommand(query, w.parameters);
  }
}

Future<List<List<Object?>>> _expandRelations(
  Database<Backend> db,
  SqlConnection connection,
  _SelectionPlan plan,
  List<List<Object?>> source,
) async {
  if (plan.relations.isEmpty || source.isEmpty) return source;
  final rows = [
    for (final row in source)
      [...row, ...List<Object?>.filled(plan.relations.length, null)],
  ];
  for (var i = 0; i < plan.relations.length; i++) {
    final values = await plan.relations[i].load(db, connection, rows);
    for (var row = 0; row < rows.length; row++) {
      rows[row][plan.columns.length + i] = values[row];
    }
  }
  return rows;
}

final class _RelationKey(final List<Object?> values) {
  @override
  int get hashCode =>
      Object.hashAll(values.map((v) => v is Uint8List ? Object.hashAll(v) : v));
  @override
  bool operator ==(Object other) {
    if (other is! _RelationKey || values.length != other.values.length) {
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
