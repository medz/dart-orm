part of '../orm.dart';

final class Assignment {
  final Field<Object?> field;
  final _Node? _value;
  const Assignment._(this.field, this._value);
}

enum _MutationKind { insert, update, delete }

final class Mutation<F extends Fields> {
  final Database<Backend> database;
  final F _fields;
  final _QueryState _state;
  final _MutationKind _kind;
  final List<Assignment> _assignments;
  final F Function(TableRef)? _createFields;
  final _Conflict? _conflict;
  final List<List<Assignment>>? _rows;
  Mutation._(
    this.database,
    this._fields,
    this._state,
    this._kind,
    List<Assignment> assignments, {
    this._createFields,
    this._conflict,
    this._rows,
  }) : _assignments = List.unmodifiable(assignments);

  Mutation<F> onConflictDoNothing({List<Field<Object?>> Function(F)? target}) =>
      _withConflict(target == null ? [] : target(_fields), const [], null);

  Mutation<F> onConflictUpdate({
    required List<Field<Object?>> Function(F) target,
    required List<Assignment> Function(F existing, F incoming) set,
  }) {
    if (_createFields == null) {
      throw const OrmException(
        'MUTATION.CONFLICT',
        'Upsert applies to an insert.',
      );
    }
    final incoming = _createFields(TableRef(_state.source.schema));
    final assignments = set(_fields, incoming);
    if (assignments.isEmpty) {
      throw const OrmException(
        'MUTATION.EMPTY',
        'Conflict update needs assignments.',
      );
    }
    return _withConflict(target(_fields), assignments, incoming.table);
  }

  Mutation<F> _withConflict(
    List<Field<Object?>> target,
    List<Assignment> assignments,
    TableRef? incoming,
  ) {
    if (_kind != _MutationKind.insert) {
      throw const OrmException(
        'MUTATION.CONFLICT',
        'Upsert applies to an insert.',
      );
    }
    final schema = _state.source.schema;
    final names = [for (final field in target) field.definition.name];
    if (names.isEmpty && assignments.isNotEmpty) {
      throw const OrmException(
        'MUTATION.CONFLICT',
        'Conflict update requires a unique key target.',
      );
    }
    if (target.any((f) => f.table != _state.source)) {
      throw const OrmException(
        'QUERY.SCOPE',
        'Conflict target belongs to another table.',
      );
    }
    final keys = [
      schema.primaryKey,
      ...schema.uniqueKeys,
      for (final i in schema.indexes)
        if (i.unique) i.columns,
    ];
    if ((names.isNotEmpty || assignments.isNotEmpty) &&
        !keys.any(
          (k) =>
              k.length == names.length &&
              k.indexed.every((entry) => entry.$2 == names[entry.$1]),
        )) {
      throw const OrmException(
        'MUTATION.CONFLICT',
        'Conflict target must be a declared unique key.',
      );
    }
    return Mutation._(
      database,
      _fields,
      _state,
      _kind,
      _assignments,
      createFields: _createFields,
      conflict: _Conflict(
        List.unmodifiable(names),
        List.unmodifiable(assignments),
        incoming,
      ),
    );
  }

  SqlCommand _compile([_SelectionPlan? selection]) {
    if (selection != null && selection.relations.isNotEmpty) {
      throw const OrmException(
        'MUTATION.RELATION',
        'RETURNING selects scalar fields; query relations after the mutation.',
      );
    }
    if (_state.limit != null ||
        _state.offset != null ||
        _state.order.isNotEmpty ||
        _state.group.isNotEmpty ||
        _state.having != null ||
        _state.distinct) {
      throw const OrmException(
        'MUTATION.QUERY',
        'Mutations accept a table and WHERE; select keys for paginated mutations.',
      );
    }
    final w = _Writer(database.dialect, {_state.source: 't0'});
    void validate(List<Assignment> assignments) {
      final names = <String>{};
      for (final a in assignments) {
        if (a._value == null &&
            !a.field.definition.generated &&
            a.field.definition.defaultSql == null) {
          throw const OrmException(
            'MUTATION.DEFAULT',
            'Column has no declared database default.',
          );
        }
        if (a.field.table != _state.source) {
          throw const OrmException(
            'QUERY.SCOPE',
            'Assignment belongs to another table.',
          );
        }
        if (!names.add(a.field.definition.name)) {
          throw const OrmException(
            'MUTATION.DUPLICATE',
            'A column can be assigned only once.',
          );
        }
      }
    }

    validate(_assignments);
    for (final row in _rows ?? <List<Assignment>>[]) {
      validate(row);
    }
    if (_conflict case final conflict?) validate(conflict.assignments);
    String assigned(Assignment a) {
      if (a._value case final expression?) return expression.write(w);
      if (a.field.definition.defaultSql == null) {
        throw const OrmException(
          'MUTATION.DEFAULT',
          'Column has no declared database default.',
        );
      }
      if (database.dialect == SqlDialect.sqlite) {
        throw const OrmException(
          'CAPABILITY.DEFAULT',
          'SQLite does not support SET column = DEFAULT.',
        );
      }
      return 'DEFAULT';
    }

    final table = '${w.quote(_state.source.schema.name)} AS "t0"';
    final b = StringBuffer();
    switch (_kind) {
      case _MutationKind.insert:
        final values = _assignments.where((a) => a._value != null).toList();
        b.write('INSERT INTO $table');
        if (values.isEmpty) {
          b.write(' DEFAULT VALUES');
        } else {
          b.write(
            ' (${values.map((a) => w.quote(a.field.definition.name)).join(', ')})',
          );
          final rows = _rows ?? [_assignments];
          b.write(
            ' VALUES ${rows.map((row) => '(${row.where((a) => a._value != null).map(assigned).join(', ')})').join(', ')}',
          );
        }
      case _MutationKind.update:
        if (_assignments.isEmpty) {
          throw const OrmException(
            'MUTATION.EMPTY',
            'Update needs an assignment.',
          );
        }
        b.write(
          'UPDATE $table SET ${_assignments.map((a) => '${w.quote(a.field.definition.name)} = ${assigned(a)}').join(', ')}',
        );
      case _MutationKind.delete:
        b.write('DELETE FROM $table');
    }
    if (_state.predicate case final predicate?) {
      b.write(' WHERE ${predicate._node.write(w)}');
    }
    if (_conflict case final conflict?) {
      b.write(' ON CONFLICT');
      if (conflict.target.isNotEmpty) {
        b.write(' (${conflict.target.map(w.quote).join(', ')})');
      }
      if (conflict.assignments.isEmpty) {
        b.write(' DO NOTHING');
      } else {
        w.aliases[conflict.incoming!] = 'excluded';
        b.write(
          ' DO UPDATE SET ${conflict.assignments.map((a) => '${w.quote(a.field.definition.name)} = ${assigned(a)}').join(', ')}',
        );
        w.aliases.remove(conflict.incoming);
      }
    }
    if (selection != null) {
      if (!database.capabilities.returning) {
        throw const OrmException(
          'CAPABILITY.RETURNING',
          'Driver does not support RETURNING.',
        );
      }
      w.unqualified = database.dialect == SqlDialect.sqlite;
      b.write(
        ' RETURNING ${selection.columns.map((e) => e._node.write(w)).join(', ')}',
      );
    }
    return SqlCommand(b.toString(), w.parameters);
  }

  SqlCommand compile() => _compile();
  Future<int> execute() async =>
      (await database.execute(compile())).affectedRows;
  Returning<R> returning<R>(Selection<R> Function(F) selection) =>
      Returning._(this, selection(_fields));
}

final class Returning<R> {
  final Mutation<Fields> _mutation;
  final Selection<R> _selection;
  Returning._(this._mutation, this._selection);
  Future<List<R>> get() async {
    final plan = _SelectionPlan();
    final decode = _selection._bind(plan);
    final result = await _mutation.database.execute(_mutation._compile(plan));
    return [for (final row in result.rows) decode(row)];
  }

  Future<R> single() async {
    final result = await get();
    if (result.length != 1) {
      throw OrmException(
        'QUERY.CARDINALITY',
        'Expected one returned row, received ${result.length}.',
      );
    }
    return result.single;
  }

  Future<R?> first() async => (await get()).firstOrNull;
}

final class _Conflict(
  final List<String> target,
  final List<Assignment> assignments,
  final TableRef? incoming,
);
