part of '../sql.dart';

enum ToOneStrategy { automatic, join, batch }

/// A relationship is a query description. Constructing or selecting it performs
/// no I/O. List results are loaded in batches on the root query's connection.
final class Relation<R, F extends Fields> {
  final TableAlias<Object?, F> _alias;
  final List<Expr<Object?>> _parent;
  final List<ReadField<Object?>> _child;
  final F _fields;
  final _QueryState _state;
  final Selection<R> _selection;

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
    return Relation._(
      alias,
      List.unmodifiable(parent),
      List.unmodifiable(keys),
      fields,
      _QueryState(fields.table),
      target.selectRow(fields),
    );
  }
  Relation._(
    this._alias,
    this._parent,
    this._child,
    this._fields,
    this._state,
    this._selection,
  );
  Relation<R, F> _copy(_QueryState state) =>
      Relation._(_alias, _parent, _child, _fields, state, _selection);
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
      Relation._(_alias, _parent, _child, _fields, _state, selection(_fields));
  Selection<List<R>> many() => _RelationSelection(this);
  bool get _uniqueTarget {
    final names = _child.map((key) => key.definition.name).toSet();
    final schema = _fields.table.schema;
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

  Selection<R?> one({ToOneStrategy strategy = ToOneStrategy.automatic}) =>
      _useJoin(strategy)
      ? _JoinedRelationSelection<R?, F>(this)
      : _oneBatch().map((rows) => rows.firstOrNull);

  Selection<List<R>> _oneBatch() =>
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
        return rows;
      });

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

final class _JoinedRelationSelection<R, F extends Fields>(
  final Relation<R, F> relation, {
  final bool required = false,
}) extends Selection<R> {
  @override
  _Decoder<R> _bind(_SelectionPlan plan) {
    Expr<bool?> match(int i) => Expr._(
      _Binary(relation._child[i]._node, '=', relation._parent[i]._node),
      Codecs.boolean.nullable(),
    );
    Expr<bool?> predicate = match(0);
    for (var i = 1; i < relation._child.length; i++) {
      predicate = predicate.and(match(i));
    }
    if (relation._state.predicate case final filter?) {
      predicate = predicate.and(filter);
    }
    // A proven unique match has at most one row, so skipping it or taking zero
    // must produce an absent relation, without filtering out the root row.
    if (relation._state.limit == 0 || (relation._state.offset ?? 0) > 0) {
      predicate = predicate.and(value(false, Codecs.boolean));
    }
    final existing = plan.joins
        .where((join) => join.alias.fields.table == relation._fields.table)
        .firstOrNull;
    if (existing == null) {
      plan.joins.add(_Join(relation._alias, predicate, true));
    } else if (!_sameSqlNode(existing.on._node, predicate._node)) {
      throw const OrmException(
        'RELATION.ALIAS',
        'Use a fresh relation getter for differently filtered joins.',
      );
    }
    final marker = plan.column(
      Expr._(_Presence(relation._alias), Codecs.integer.nullable()),
    );
    final decode = plan.optional(relation._fields.table, relation._selection);
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

final class _RelationSubquery(
  final Relation<Object?, Fields> relation,
  final bool count,
) extends _Node {
  @override
  String writeSql(_Writer w) {
    if (relation._state.limit != null || relation._state.offset != null) {
      throw const OrmException(
        'RELATION.AGGREGATE',
        'Apply relation count/any/every before pagination.',
      );
    }
    final source = relation._state.source;
    w.reads?.tables.add(source.schema);
    final previous = w.aliases[source];
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
      if (previous == null) {
        w.aliases.remove(source);
      } else {
        w.aliases[source] = previous;
      }
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
  RelationLoadPlan inspect(QueryContext db);
  void collectReads(QueryContext db, _ReadTables reads);
  Future<List<Object?>> load(
    QueryContext db,
    SqlConnection connection,
    List<List<Object?>> parents, {
    ExecutionOptions options = const ExecutionOptions(),
  });
}

final class _TypedRelationBinding<R, F extends Fields>(
  final Relation<R, F> relation,
  final List<int> parentIndices,
) extends _RelationBinding {
  @override
  RelationLoadPlan inspect(QueryContext db) => _inspectRelation(db, this);
  @override
  void collectReads(QueryContext db, _ReadTables reads) => reads.query(
    Query._(db, relation._fields, relation._state, relation._selection),
  );

  @override
  Future<List<Object?>> load(
    QueryContext db,
    SqlConnection connection,
    List<List<Object?>> parents, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final keys = <_RelationKey>{};
    final parentKeys = [
      for (final row in parents)
        _RelationKey([
          for (var i = 0; i < parentIndices.length; i++)
            _relationValue(relation._parent[i], row[parentIndices[i]]),
        ]),
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
      final command = _compile(db, plan, all.sublist(offset, end));
      final result = await db.executeOn(connection, command, options: options);
      final rows = await _expandRelations(
        db,
        connection,
        plan,
        result.rows,
        options: options,
      );
      db.observeDecode(command.sql, rows.length, () {
        for (final row in rows) {
          final key = _RelationKey([
            for (var i = 0; i < childIndices.length; i++)
              _relationValue(relation._child[i], row[childIndices[i]]),
          ]);
          (grouped[key] ??= []).add(decode(row));
        }
      });
    }
    return [
      for (final key in parentKeys) List<R>.unmodifiable(grouped[key] ?? <R>[]),
    ];
  }

  SqlCommand _compile(
    QueryContext db,
    _SelectionPlan plan,
    List<_RelationKey> keys, {
    _ReadTables? reads,
  }) {
    final state = relation._state;
    final w = _Writer(
      db.dialect,
      {},
      database: db,
      reads: reads,
      exactDecimal: db.capabilities.exactDecimal,
      temporal: db.capabilities.temporal,
    );
    Expr<bool?> predicate = Expr._(
      _RelationKeys(relation._child, keys),
      Codecs.boolean,
    );
    if (state.predicate case final filter?) predicate = predicate.and(filter);
    final paginated = state.limit != null || state.offset != null;
    final sqlPlan = _SelectionPlan()
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
        rowNumber(partitionBy: relation._child, orderBy: state.order),
      );
    }
    final query = Query._(
      db,
      relation._fields,
      _QueryState(
        state.source,
        predicate: predicate,
        order: paginated ? const [] : state.order,
      ),
      relation._selection,
    );
    var text = query._write(w, sqlPlan, aliasColumns: true, decodeResult: true);
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

Future<List<List<Object?>>> _expandRelations(
  QueryContext db,
  SqlConnection connection,
  _SelectionPlan plan,
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

// Row-value IN avoids a deep OR tree for large composite-key batches.
final class _RelationKeys(
  final List<ReadField<Object?>> columns,
  final List<_RelationKey> keys,
) extends _Node {
  @override
  String writeSql(_Writer w) {
    // Keys stay comparable storage values while grouping. Restore floating SQL
    // intent only when binding them (JS cannot identify an integral double).
    Object? parameter(int index, Object? value) =>
        value != null && columns[index].codec.sqlType == 'real'
        ? Codecs.real.encode(Codecs.real.decode(value))
        : value;
    if (columns.length == 1) {
      return _In(columns.single._node, [
        for (final key in keys)
          _Parameter(
            parameter(0, key.values.single),
            storageType: columns.single.codec.sqlType,
          ),
      ]).write(w);
    }
    return '(${columns.map((c) => c._node.write(w)).join(', ')}) IN (${w.dialect == SqlDialect.sqlite ? 'VALUES ' : ''}'
        '${keys.map((key) => '(${[for (var i = 0; i < key.values.length; i++) _Parameter(parameter(i, key.values[i]), storageType: columns[i].codec.sqlType).write(w)].join(', ')})').join(', ')})';
  }
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
