part of '../sql.dart';

final class Assignment {
  final Field<Object?> field;
  final _Node? _value;
  const Assignment._(this.field, this._value);
}

enum _MutationKind { insert, update, delete }

final class Mutation<F extends Fields> {
  final QueryContext database;
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

  Mutation<F> onConflictDoNothing({
    List<ReadField<Object?>> Function(F)? target,
  }) => _withConflict(target == null ? [] : target(_fields), const [], null);

  /// MySQL/MariaDB update on any duplicate unique key, matching native semantics.
  Mutation<F> onDuplicateKeyUpdate({
    required List<Assignment> Function(F existing, F incoming) set,
  }) {
    if (_kind != _MutationKind.insert || _createFields == null) {
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
    return Mutation._(
      database,
      _fields,
      _state,
      _kind,
      _assignments,
      createFields: _createFields,
      conflict: _Conflict(
        const [],
        List.unmodifiable(assignments),
        incoming.table,
      ),
    );
  }

  Mutation<F> onConflictUpdate({
    required List<ReadField<Object?>> Function(F) target,
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
    List<ReadField<Object?>> target,
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
    if (selection != null && selection.columns.isEmpty) {
      throw const OrmException(
        'QUERY.EMPTY_SELECTION',
        'Select at least one field.',
      );
    }
    if (selection != null &&
        selection.columns.any((e) => _aggregate(e._node) || _window(e._node))) {
      throw const OrmException(
        'MUTATION.RETURNING',
        'RETURNING cannot contain aggregate or window functions.',
      );
    }
    if (selection != null &&
        (selection.relations.isNotEmpty || selection.joins.isNotEmpty)) {
      throw const OrmException(
        'MUTATION.RELATION',
        'RETURNING selects scalar fields; query relations after the mutation.',
      );
    }
    if (_state.limit != null ||
        _state.joins.isNotEmpty ||
        _state.union != null ||
        _state.ctes.isNotEmpty ||
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
    final w = _Writer(
      database.dialect,
      {_state.source: 't0'},
      database: database,
      exactDecimal: database.capabilities.exactDecimal,
      temporal: database.capabilities.temporal,
    );
    void validate(List<Assignment> assignments) {
      final names = <String>{};
      for (final a in assignments) {
        if (a._value case final node?) {
          if (_aggregate(node) || _window(node)) {
            throw const OrmException(
              'QUERY.AGGREGATE',
              'Assignments cannot contain aggregate or window functions. Use a scalar subquery.',
            );
          }
        }
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
    if (_state.predicate case final predicate?) {
      if (_aggregate(predicate._node) || _window(predicate._node)) {
        throw const OrmException(
          'QUERY.AGGREGATE',
          'Mutation predicates cannot contain aggregate or window functions. Use a subquery.',
        );
      }
    }
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

    final table = w.mysql && _kind == _MutationKind.insert
        ? w.quote(_state.source.schema.name)
        : '${w.quote(_state.source.schema.name)} AS ${w.quote('t0')}';
    if (w.mysql && _kind == _MutationKind.insert) {
      w.unqualifiedTable = _state.source;
    }
    final b = StringBuffer();
    switch (_kind) {
      case _MutationKind.insert:
        final values = _assignments.where((a) => a._value != null).toList();
        b.write('INSERT INTO $table');
        if (values.isEmpty) {
          b.write(w.mysql ? ' () VALUES ()' : ' DEFAULT VALUES');
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
      if (w.mysql) {
        if (conflict.target.isNotEmpty) {
          throw const OrmException(
            'CAPABILITY.CONFLICT_TARGET',
            'MySQL/MariaDB cannot select a conflict target. Use onDuplicateKeyUpdate.',
          );
        }
        b.write(' ON DUPLICATE KEY UPDATE ');
        if (conflict.assignments.isEmpty) {
          throw const OrmException(
            'CAPABILITY.DO_NOTHING',
            'MySQL/MariaDB cannot ignore only duplicate keys without update side effects.',
          );
        } else {
          w.aliases[conflict.incoming!] = 'excluded';
          b.write(
            conflict.assignments
                .map(
                  (a) => '${w.quote(a.field.definition.name)} = ${assigned(a)}',
                )
                .join(', '),
          );
          w.aliases.remove(conflict.incoming);
        }
      } else {
        if (conflict.target.isEmpty && conflict.assignments.isNotEmpty) {
          throw const OrmException(
            'CAPABILITY.DUPLICATE_KEY',
            'Use onConflictUpdate with a declared target on this database.',
          );
        }
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
    return w.finish(b.toString());
  }

  SqlCommand compile() => _compile();
  Future<int> execute({
    ExecutionOptions options = const ExecutionOptions(),
  }) async => (await database.executeCommand(
    compile(),
    options: options,
    changedTables: [_state.source.schema],
    affectedOnly: true,
    cascade: _kind == _MutationKind.delete,
  )).affectedRows;
  Returning<R> returning<R>(Selection<R> Function(F) selection) =>
      Returning._(this, selection(_fields));
}

final class Returning<R> {
  final Mutation<Fields> _mutation;
  final Selection<R> _selection;
  Returning._(this._mutation, this._selection);
  Future<List<R>> get({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final plan = _SelectionPlan();
    final decode = _selection._bind(plan);
    final command = _mutation._compile(plan);
    final result = await _mutation.database.executeCommand(
      command,
      options: options,
      changedTables: [_mutation._state.source.schema],
      affectedOnly: true,
      cascade: _mutation._kind == _MutationKind.delete,
    );
    return _mutation.database.observeDecode(
      command.sql,
      result.rows.length,
      () => [for (final row in result.rows) decode(row)],
    );
  }

  Future<R> single({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final result = await get(options: options);
    if (result.length != 1) {
      throw OrmException(
        'QUERY.CARDINALITY',
        'Expected one returned row, received ${result.length}.',
      );
    }
    return result.single;
  }

  Future<R?> first({
    ExecutionOptions options = const ExecutionOptions(),
  }) async => (await get(options: options)).firstOrNull;
}

final class _Conflict(
  final List<String> target,
  final List<Assignment> assignments,
  final TableRef? incoming,
);
