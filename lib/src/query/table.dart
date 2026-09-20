import 'package:meta/meta.dart';

import '../../schema_model.dart';
import 'expression.dart';
import 'joins.dart';
import 'mutation.dart';
import 'nodes.dart';
import 'selection.dart';

/// A table occurrence has nominal identity, even when two row records have the
/// same structural Dart type or a query joins the same physical table twice.
final class TableRef {
  /// The physical schema for this occurrence of a table.
  final TableSchema schema;

  /// Creates a distinct occurrence, even when the schema is shared.
  TableRef(this.schema);
}

/// Typed expressions belonging to one table occurrence.
///
/// Generated field classes extend this type. Manual definitions use [column] for
/// writable columns and [readColumn] for database-computed columns.
abstract class Fields {
  /// The table occurrence that owns these expressions.
  final TableRef table;

  /// Binds a field collection to one table occurrence.
  const Fields(this.table);

  /// Creates a writable field; rejects computed column definitions.
  Field<T> column<T>(Column<T> column) => Field.internal(table, column);

  /// Creates a read-only field, including a database-computed column.
  ReadField<T> readColumn<T>(Column<T> column) =>
      ReadField.internal(table, column);
}

/// A selectable column expression with no assignment operations.
base class ReadField<T> extends Expr<T> {
  /// The owning table occurrence, used to validate query scope.
  final TableRef table;

  /// The column's name, codec and physical constraints.
  final Column<T> definition;

  /// @nodoc
  @internal
  ReadField.internal(this.table, this.definition)
    : super.internal(ColumnNode(table, definition.name), definition.codec);
}

/// A writable column expression that can create mutation assignments.
final class Field<T> extends ReadField<T> {
  /// @nodoc
  @internal
  Field.internal(super.table, super.definition) : super.internal() {
    if (definition.computed != null) {
      throw const OrmException(
        'COLUMN.READ_ONLY',
        'Use readColumn for a computed column.',
      );
    }
  }

  /// Assigns a bound value, including NULL when the field is nullable.
  Assignment set(T value) =>
      _assign(ParameterNode(codec.encode(value), storageType: codec.sqlType));

  /// Assigns a SQL expression with the same Dart value type.
  Assignment setExpression(Expr<T> expression) =>
      _assign(expression.expressionNode);
  Assignment _assign(SqlNode node) => Assignment.internal(
    this,
    definition.decimalPrecision == null
        ? definition.temporalPrecision == null
              ? node
              : TemporalCast(
                  node,
                  definition.codec.sqlType,
                  definition.temporalPrecision!,
                  columnAssignment: true,
                )
        : DecimalCast(
            node,
            definition.decimalPrecision!,
            definition.decimalScale ?? 0,
            columnAssignment: true,
          ),
  );

  /// Requests the database default rather than a Dart client default.
  Assignment defaultValue() => Assignment.internal(this, null);
}

/// Atomic numeric updates evaluated inside the database statement.
extension NumericField<T extends num> on Field<T> {
  /// Adds a bound amount to the stored value.
  Assignment increment(T amount) => setExpression(plus(amount));

  /// Subtracts a bound amount from the stored value.
  Assignment decrement(T amount) => setExpression(minus(amount));
}

/// A table's physical schema, typed fields and full-row decoder.
///
/// Use generated definitions for normal application code, or construct one for a
/// manual schema. A definition can be bound to different database sessions.
final class Table<R, F extends Fields> {
  /// The physical schema used for validation and SQL generation.
  final TableSchema schema;

  /// Creates typed fields for a fresh table occurrence.
  final F Function(TableRef) createFields;

  /// Builds the full-row selection from that occurrence's fields.
  final Selection<R> Function(F) selectRow;

  /// Defines a table without opening a database connection.
  const Table(this.schema, this.createFields, this.selectRow);

  /// Creates an independent alias for a join or self-join.
  TableAlias<R, F> alias() => TableAlias.internal(this);
}

/// A patch value that distinguishes omission, assignment and SQL DEFAULT.
///
/// Use `.keep()` to omit, `.set(value)` to write, or `.defaultValue()` to request
/// the database default. Setting null is legal only for a nullable field.
sealed class Change<T> {
  /// Base constructor for the closed set of patch operations.
  const Change();

  /// Leaves the field out of the update.
  const factory Change.keep() = _Keep<T>;

  /// Writes the supplied value, including an explicitly allowed null.
  const factory Change.set(T value) = _Set<T>;

  /// Requests the database default for this field.
  const factory Change.defaultValue() = _Default<T>;
}

final class _Keep<T> extends Change<T> {
  const _Keep();
}

final class _Set<T> extends Change<T> {
  final T value;
  const _Set(this.value);
}

final class _Default<T> extends Change<T> {
  const _Default();
}

/// Converts a generated patch input into zero or one SQL assignment.
extension ChangeField<T> on Field<T> {
  /// Omits unchanged fields and builds assignments for the other cases.
  List<Assignment> change(Change<T> change) => switch (change) {
    _Keep<T>() => [],
    _Set<T>(:final value) => [set(value)],
    _Default<T>() => [defaultValue()],
  };
}
