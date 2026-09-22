import 'package:meta/meta.dart';

import '../../driver.dart';
import 'context.dart';
import 'joins.dart';
import 'nodes.dart';
import 'query.dart';
import 'reads.dart';
import 'selection.dart';
import 'table.dart';

/// One typed column assignment prepared by a writable field.
///
/// Obtain assignments through a field's `set`, `setExpression`, `increment`, or
/// `defaultValue` methods, then return them from an insert or update callback.
final class Assignment {
  /// Writable field belonging to the mutation's table occurrence.
  final Field<Object?> field;

  /// @nodoc
  @internal
  final SqlNode? assignedValue;

  /// @nodoc
  @internal
  const Assignment.internal(this.field, this.assignedValue);
}

/// @nodoc
@internal
enum MutationKind { insert, update, delete }

/// A prepared insert, update, or delete that performs no I/O until executed.
///
/// [compile] inspects SQL; [execute] returns the affected-row count;
/// [returning] prepares a typed result. Updates and deletes accept table filters,
/// not joins, ordering, grouping, or pagination. Client defaults in a prepared
/// insert are evaluated when it is built and reused if it executes again.
///
/// Relationship predicates remain subqueries within one statement. On MySQL,
/// updates/deletes whose typed subqueries read the target table are rejected
/// with `CAPABILITY.MUTATION_SELF_REFERENCE` before execution. Select keys in an
/// explicit transaction, then mutate by those keys when that restriction applies.
final class Mutation<F extends Fields> {
  /// Query context that owns this mutation's execution and transaction scope.
  final QueryContext database;

  /// @nodoc
  @internal
  final F queryFields;

  /// @nodoc
  @internal
  final QueryState queryState;

  /// @nodoc
  @internal
  final MutationKind mutationKind;

  /// @nodoc
  @internal
  final List<Assignment> writeAssignments;

  /// @nodoc
  @internal
  final F Function(TableRef)? fieldsFactory;
  final _Conflict? _conflict;

  /// @nodoc
  @internal
  final List<List<Assignment>>? insertRows;

  /// @nodoc
  @internal
  Mutation.internal(
    this.database,
    this.queryFields,
    this.queryState,
    this.mutationKind,
    List<Assignment> assignments, {
    this.fieldsFactory,
    this._conflict,
    this.insertRows,
  }) : writeAssignments = List.unmodifiable(assignments);

  /// Prepares SQLite/PostgreSQL duplicate-key suppression for this insert.
  ///
  /// An explicit [target] must match a declared primary or unique key. Omitting
  /// it uses the database's untargeted `ON CONFLICT DO NOTHING` behavior.
  Mutation<F> onConflictDoNothing({
    List<ReadField<Object?>> Function(F)? target,
  }) =>
      _withConflict(target == null ? [] : target(queryFields), const [], null);

  /// MySQL/MariaDB update on any duplicate unique key, matching native semantics.
  ///
  /// [set] receives the existing row and the proposed incoming row. It must
  /// return at least one assignment; this method does not execute the insert.
  Mutation<F> onDuplicateKeyUpdate({
    required List<Assignment> Function(F existing, F incoming) set,
  }) {
    final fieldsFactory = this.fieldsFactory;
    if (mutationKind != MutationKind.insert || fieldsFactory == null) {
      throw const OrmException(
        'MUTATION.CONFLICT',
        'Upsert applies to an insert.',
      );
    }
    final incoming = fieldsFactory(TableRef(queryState.source.schema));
    final assignments = set(queryFields, incoming);
    if (assignments.isEmpty) {
      throw const OrmException(
        'MUTATION.EMPTY',
        'Conflict update needs assignments.',
      );
    }
    return Mutation.internal(
      database,
      queryFields,
      queryState,
      mutationKind,
      writeAssignments,
      fieldsFactory: fieldsFactory,
      conflict: _Conflict(
        const [],
        List.unmodifiable(assignments),
        incoming.table,
      ),
    );
  }

  /// Prepares a SQLite/PostgreSQL upsert against a declared unique [target].
  ///
  /// [set] distinguishes existing values from proposed incoming values and must
  /// return at least one assignment. MySQL/MariaDB use [onDuplicateKeyUpdate].
  Mutation<F> onConflictUpdate({
    required List<ReadField<Object?>> Function(F) target,
    required List<Assignment> Function(F existing, F incoming) set,
  }) {
    final fieldsFactory = this.fieldsFactory;
    if (fieldsFactory == null) {
      throw const OrmException(
        'MUTATION.CONFLICT',
        'Upsert applies to an insert.',
      );
    }
    final incoming = fieldsFactory(TableRef(queryState.source.schema));
    final assignments = set(queryFields, incoming);
    if (assignments.isEmpty) {
      throw const OrmException(
        'MUTATION.EMPTY',
        'Conflict update needs assignments.',
      );
    }
    return _withConflict(target(queryFields), assignments, incoming.table);
  }

  Mutation<F> _withConflict(
    List<ReadField<Object?>> target,
    List<Assignment> assignments,
    TableRef? incoming,
  ) {
    if (mutationKind != MutationKind.insert) {
      throw const OrmException(
        'MUTATION.CONFLICT',
        'Upsert applies to an insert.',
      );
    }
    final schema = queryState.source.schema;
    final names = [for (final field in target) field.definition.name];
    if (names.isEmpty && assignments.isNotEmpty) {
      throw const OrmException(
        'MUTATION.CONFLICT',
        'Conflict update requires a unique key target.',
      );
    }
    if (target.any((f) => f.table != queryState.source)) {
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
    return Mutation.internal(
      database,
      queryFields,
      queryState,
      mutationKind,
      writeAssignments,
      fieldsFactory: fieldsFactory,
      conflict: _Conflict(
        List.unmodifiable(names),
        List.unmodifiable(assignments),
        incoming,
      ),
    );
  }

  /// @nodoc
  @internal
  SqlCommand compileQuery([SelectionPlan? selection]) {
    if (selection != null && selection.columns.isEmpty) {
      throw const OrmException(
        'QUERY.EMPTY_SELECTION',
        'Select at least one field.',
      );
    }
    if (selection != null &&
        selection.columns.any(
          (e) => aggregate(e.expressionNode) || window(e.expressionNode),
        )) {
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
    if (queryState.limit != null ||
        queryState.joins.isNotEmpty ||
        queryState.union != null ||
        queryState.ctes.isNotEmpty ||
        queryState.offset != null ||
        queryState.order.isNotEmpty ||
        queryState.group.isNotEmpty ||
        queryState.having != null ||
        queryState.distinct) {
      throw const OrmException(
        'MUTATION.QUERY',
        'Mutations accept a table and WHERE; select keys for paginated mutations.',
      );
    }
    final subqueryReads =
        database.dialect == SqlDialect.mysql &&
            mutationKind != MutationKind.insert
        ? ReadTables()
        : null;
    final w = SqlWriter(
      database.dialect,
      {queryState.source: 't0'},
      database: database,
      reads: subqueryReads,
      exactDecimal: database.capabilities.exactDecimal,
      temporal: database.capabilities.temporal,
    );
    void validate(List<Assignment> assignments) {
      final names = <String>{};
      for (final a in assignments) {
        if (a.assignedValue case final node?) {
          if (aggregate(node) || window(node)) {
            throw const OrmException(
              'QUERY.AGGREGATE',
              'Assignments cannot contain aggregate or window functions. Use a scalar subquery.',
            );
          }
        }
        if (a.assignedValue == null &&
            !a.field.definition.generated &&
            a.field.definition.defaultSql == null) {
          throw const OrmException(
            'MUTATION.DEFAULT',
            'Column has no declared database default.',
          );
        }
        if (a.field.table != queryState.source) {
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

    validate(writeAssignments);
    if (queryState.predicate case final predicate?) {
      if (aggregate(predicate.expressionNode) ||
          window(predicate.expressionNode)) {
        throw const OrmException(
          'QUERY.AGGREGATE',
          'Mutation predicates cannot contain aggregate or window functions. Use a subquery.',
        );
      }
    }
    for (final row in insertRows ?? <List<Assignment>>[]) {
      validate(row);
    }
    if (_conflict case final conflict?) validate(conflict.assignments);
    String assigned(Assignment a) {
      if (a.assignedValue case final expression?) return expression.write(w);
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

    final table = w.mysql && mutationKind == MutationKind.insert
        ? w.table(queryState.source.schema)
        : '${w.table(queryState.source.schema)} AS ${w.quote('t0')}';
    if (w.mysql && mutationKind == MutationKind.insert) {
      w.unqualifiedTable = queryState.source;
    }
    final b = StringBuffer();
    switch (mutationKind) {
      case MutationKind.insert:
        final values = writeAssignments
            .where((a) => a.assignedValue != null)
            .toList();
        b.write('INSERT INTO $table');
        if (values.isEmpty) {
          b.write(w.mysql ? ' () VALUES ()' : ' DEFAULT VALUES');
        } else {
          b.write(
            ' (${values.map((a) => w.quote(a.field.definition.name)).join(', ')})',
          );
          final rows = insertRows ?? [writeAssignments];
          b.write(
            ' VALUES ${rows.map((row) => '(${row.where((a) => a.assignedValue != null).map(assigned).join(', ')})').join(', ')}',
          );
        }
      case MutationKind.update:
        if (writeAssignments.isEmpty) {
          throw const OrmException(
            'MUTATION.EMPTY',
            'Update needs an assignment.',
          );
        }
        b.write(
          'UPDATE $table SET ${writeAssignments.map((a) => '${w.quote(a.field.definition.name)} = ${assigned(a)}').join(', ')}',
        );
      case MutationKind.delete:
        b.write('DELETE FROM $table');
    }
    if (queryState.predicate case final predicate?) {
      b.write(' WHERE ${predicate.expressionNode.write(w)}');
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
        ' RETURNING ${selection.columns.map((e) => e.expressionNode.write(w)).join(', ')}',
      );
    }
    final target = queryState.source.schema;
    if (subqueryReads?.tables.any(
          (table) =>
              table.name == target.name && table.namespace == target.namespace,
        ) ??
        false) {
      throw const OrmException(
        'CAPABILITY.MUTATION_SELF_REFERENCE',
        'MySQL cannot update or delete a table read by a subquery. Select keys in an explicit transaction, then mutate by those keys.',
      );
    }
    return w.finish(b.toString());
  }

  /// Validates and compiles SQL with separate parameters, without database I/O.
  SqlCommand compile() => compileQuery();

  /// Executes the complete mutation and returns the driver's affected-row count.
  ///
  /// Counts follow the selected database's native semantics, including upserts.
  Future<int> execute({
    ExecutionOptions options = const ExecutionOptions(),
  }) async => (await database.executeCommand(
    compile(),
    options: options,
    changedTables: [queryState.source.schema],
    affectedOnly: true,
    cascade: mutationKind == MutationKind.delete,
  )).affectedRows;

  /// Prepares a typed `RETURNING` result on an engine that supports it.
  ///
  /// Select scalar SQL expressions or composed projections. Relationships,
  /// aggregate functions, and window functions are rejected before execution.
  Returning<R> returning<R>(Selection<R> Function(F) selection) =>
      Returning.internal(this, selection(queryFields));
}

/// A prepared mutation whose returned SQL rows decode to `R`.
///
/// Every read method executes the entire mutation again. Selecting only its
/// first result does not limit affected rows. Cardinality and decoding errors
/// can occur after the write; let them escape a transaction callback when that
/// transaction must roll back the changes.
final class Returning<R> {
  final Mutation<Fields> _mutation;

  /// @nodoc
  @internal
  final Selection<R> querySelection;

  /// @nodoc
  @internal
  Returning.internal(this._mutation, this.querySelection);

  /// Executes the mutation and decodes all rows from `RETURNING`.
  ///
  /// Returned row order is determined by the database and has no implicit sort.
  Future<List<R>> get({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final plan = SelectionPlan();
    final decode = querySelection.bindSelection(plan);
    final command = _mutation.compileQuery(plan);
    final result = await _mutation.database.executeCommand(
      command,
      options: options,
      changedTables: [_mutation.queryState.source.schema],
      affectedOnly: true,
      cascade: _mutation.mutationKind == MutationKind.delete,
    );
    return _mutation.database.observeDecode(
      command.sql,
      result.rows.length,
      () => [for (final row in result.rows) decode(row)],
    );
  }

  /// Executes the mutation and requires exactly one returned row.
  ///
  /// Throws `QUERY.CARDINALITY` after execution if the result is empty or has
  /// multiple rows. Use a transaction if that failure must roll back the write.
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

  /// Executes the mutation and returns its first row, rejecting an empty result.
  ///
  /// The mutation still affects all matching rows. Cardinality is checked after
  /// execution; a returned SQL NULL is a row when `R` is nullable.
  Future<R> first({ExecutionOptions options = const ExecutionOptions()}) async {
    final rows = await get(options: options);
    if (rows.isEmpty) {
      throw const OrmException(
        'QUERY.CARDINALITY',
        'Expected a returned row, received none.',
      );
    }
    return rows.first;
  }

  /// Executes the mutation and returns the first returned row, or null if empty.
  ///
  /// All matching rows are affected, regardless of how many are returned here.
  Future<R?> firstOrNull({
    ExecutionOptions options = const ExecutionOptions(),
  }) async => (await get(options: options)).firstOrNull;

  /// Executes the mutation and accepts zero or one returned row.
  ///
  /// Throws `QUERY.CARDINALITY` after execution for multiple rows. Use a
  /// transaction if that failure must roll back the write.
  Future<R?> singleOrNull({
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final rows = await get(options: options);
    if (rows.length > 1) {
      throw OrmException(
        'QUERY.CARDINALITY',
        'Expected at most one returned row, received ${rows.length}.',
      );
    }
    return rows.firstOrNull;
  }
}

final class _Conflict(
  final List<String> target,
  final List<Assignment> assignments,
  final TableRef? incoming,
);
