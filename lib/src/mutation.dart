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
  Mutation._(
    this.database,
    this._fields,
    this._state,
    this._kind,
    List<Assignment> assignments,
  ) : _assignments = List.unmodifiable(assignments);

  SqlCommand _compile([_SelectionPlan? selection]) {
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
    final names = <String>{};
    for (final a in _assignments) {
      if (a.field.table != _state.source)
        throw const OrmException(
          'QUERY.SCOPE',
          'Assignment belongs to another table.',
        );
      if (!names.add(a.field.definition.name))
        throw const OrmException(
          'MUTATION.DUPLICATE',
          'A column can be assigned only once.',
        );
    }
    String assigned(Assignment a) {
      if (a._value case final expression?) return expression.write(w);
      if (a.field.definition.defaultSql == null)
        throw const OrmException(
          'MUTATION.DEFAULT',
          'Column has no declared database default.',
        );
      if (database.dialect == SqlDialect.sqlite)
        throw const OrmException(
          'CAPABILITY.DEFAULT',
          'SQLite does not support SET column = DEFAULT.',
        );
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
          b.write(' VALUES (${values.map(assigned).join(', ')})');
        }
      case _MutationKind.update:
        if (_assignments.isEmpty)
          throw const OrmException(
            'MUTATION.EMPTY',
            'Update needs an assignment.',
          );
        b.write(
          'UPDATE $table SET ${_assignments.map((a) => '${w.quote(a.field.definition.name)} = ${assigned(a)}').join(', ')}',
        );
      case _MutationKind.delete:
        b.write('DELETE FROM $table');
    }
    if (_state.predicate case final predicate?)
      b.write(' WHERE ${predicate._node.write(w)}');
    if (selection != null) {
      if (!database.capabilities.returning)
        throw const OrmException(
          'CAPABILITY.RETURNING',
          'Driver does not support RETURNING.',
        );
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
    if (result.length != 1)
      throw OrmException(
        'QUERY.CARDINALITY',
        'Expected one returned row, received ${result.length}.',
      );
    return result.single;
  }
}
