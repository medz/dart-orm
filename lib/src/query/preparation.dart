import 'package:meta/meta.dart';

import '../values/codec.dart';
import '../schema/model.dart';
import 'batch.dart';
import 'context.dart';
import 'expression.dart';
import 'joins.dart';
import 'mutation.dart';
import 'nodes.dart';
import 'query.dart';
import 'selection.dart';
import 'table.dart';

/// @nodoc
@internal
void preflightAssignments(TableRef source, Iterable<List<Assignment>> rows) {
  for (final row in rows) {
    final names = <String>{};
    for (final assignment in row) {
      if (assignment.field.table != source) {
        throw const OrmException(
          'QUERY.SCOPE',
          'Assignment belongs to another table.',
        );
      }
      if (!names.add(assignment.field.definition.name)) {
        throw const OrmException(
          'MUTATION.DUPLICATE',
          'A column can be assigned only once.',
        );
      }
      if (assignment.assignedValue case final node?) {
        if (aggregate(node) || window(node)) {
          throw const OrmException(
            'QUERY.AGGREGATE',
            'Assignments cannot contain aggregate or window functions. Use a scalar subquery.',
          );
        }
      } else if (!assignment.field.definition.generated &&
          assignment.field.definition.defaultSql == null) {
        throw const OrmException(
          'MUTATION.DEFAULT',
          'Column has no declared database default.',
        );
      }
    }
  }
}

/// @nodoc
@internal
List<List<Assignment>> prepareInsertRows<F extends Fields>(
  QueryContext database,
  F fields,
  QueryState state,
  Iterable<List<Assignment>> rows,
) {
  database.checkActive();
  preflightMutationQuery(state);
  // Capture all callbacks before validation and before any client factory runs.
  final inputs = [for (final row in rows) _InsertInput(fields, state, row)];
  preflightAssignments(state.source, inputs.map((input) => input.explicit));
  final dryRows = [for (final input in inputs) input.dry];
  if (dryRows.length == 1) {
    Mutation.internal(
      database,
      fields,
      state,
      MutationKind.insert,
      dryRows.single,
    ).compile();
  } else {
    BatchInsert.internal(database, fields, state, dryRows).compile();
  }
  return List.unmodifiable([for (final input in inputs) input.materialize()]);
}

/// @nodoc
@internal
Mutation<F> prepareInsert<R, F extends Fields>(
  TableSet<R, F> query,
  List<Assignment> assignments,
  SelectionPlan? selection, {
  bool needsRow = false,
  List<ReadField<Object?>>? conflictTarget,
}) {
  final fields = query.queryFields;
  final state = query.queryState;
  query.database.checkActive();
  final input = _InsertInput(fields, state, assignments);
  preflightAssignments(state.source, [input.explicit]);
  final dry = input.dry;
  Mutation<F> mutation(List<Assignment> values) {
    final prepared = Mutation.internal(
      query.database,
      fields,
      state,
      MutationKind.insert,
      values,
      fieldsFactory: query.definition.createFields,
    );
    return conflictTarget == null
        ? prepared
        : prepared.onConflictDoNothing(target: (_) => conflictTarget);
  }

  mutation(dry).compileQuery(selection);
  if (needsRow && !query.database.capabilities.returning) {
    final keys = state.source.schema.primaryKey;
    var generated = 0;
    for (final key in keys) {
      final column = state.source.schema.columns.firstWhere(
        (c) => c.name == key,
      );
      final assigned = dry
          .where((a) => a.field.definition.name == key)
          .firstOrNull;
      if (assigned?.assignedValue is ParameterNode) continue;
      if (column.generated && assigned?.assignedValue == null) {
        generated++;
        continue;
      }
      throw const OrmException(
        'CAPABILITY.CREATE_KEY',
        'Reading an inserted row needs literal keys or one generated identity.',
      );
    }
    if (keys.isEmpty || generated > 1) {
      throw const OrmException(
        'CAPABILITY.CREATE_KEY',
        'Reading an inserted row needs a key and at most one generated identity.',
      );
    }
  }
  return mutation(input.materialize());
}

final class _InsertInput {
  final Fields fields;
  final List<Assignment> explicit;
  final List<Column<Object?>> omitted;
  _InsertInput(this.fields, QueryState state, List<Assignment> assignments)
    : explicit = List.unmodifiable(assignments),
      omitted = [
        for (final column in state.source.schema.clientDefaults)
          if (!assignments.any((a) => a.field.definition.name == column.name))
            column,
      ];

  List<Assignment> get dry => [
    ...explicit,
    for (final column in omitted)
      fields
          .column(column)
          .setExpression(
            Expr<Object?>.internal(
              ParameterNode(null, storageType: column.codec.sqlType),
              column.codec,
            ),
          ),
  ];

  List<Assignment> materialize() => List.unmodifiable([
    ...explicit,
    for (final column in omitted)
      fields.column(column).set(column.clientDefault!()),
  ]);
}
