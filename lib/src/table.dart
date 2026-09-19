part of '../sql.dart';

/// A table occurrence has nominal identity, even when two row records have the
/// same structural Dart type or a query joins the same physical table twice.
final class TableRef {
  final TableSchema schema;
  TableRef(this.schema);
}

abstract class Fields {
  final TableRef table;
  const Fields(this.table);
  Field<T> column<T>(Column<T> column) => Field._(table, column);
  ReadField<T> readColumn<T>(Column<T> column) => ReadField._(table, column);
}

base class ReadField<T> extends Expr<T> {
  final TableRef table;
  final Column<T> definition;
  ReadField._(this.table, this.definition)
    : super._(_ColumnNode(table, definition.name), definition.codec);
}

final class Field<T> extends ReadField<T> {
  Field._(super.table, super.definition) : super._() {
    if (definition.computed != null) {
      throw const OrmException(
        'COLUMN.READ_ONLY',
        'Use readColumn for a computed column.',
      );
    }
  }
  Assignment set(T value) =>
      _assign(_Parameter(codec.encode(value), storageType: codec.sqlType));
  Assignment setExpression(Expr<T> expression) => _assign(expression._node);
  Assignment _assign(_Node node) => Assignment._(
    this,
    definition.decimalPrecision == null
        ? definition.temporalPrecision == null
              ? node
              : _TemporalCast(
                  node,
                  definition.codec.sqlType,
                  definition.temporalPrecision!,
                  columnAssignment: true,
                )
        : _DecimalCast(
            node,
            definition.decimalPrecision!,
            definition.decimalScale ?? 0,
            columnAssignment: true,
          ),
  );
  Assignment defaultValue() => Assignment._(this, null);
}

extension NumericField<T extends num> on Field<T> {
  Assignment increment(T amount) => setExpression(plus(amount));
  Assignment decrement(T amount) => setExpression(minus(amount));
}

final class Table<R, F extends Fields> {
  final TableSchema schema;
  final F Function(TableRef) createFields;
  final Selection<R> Function(F) selectRow;
  const Table(this.schema, this.createFields, this.selectRow);
  TableAlias<R, F> alias() => TableAlias._(this);
}

sealed class Change<T> {
  const Change();
  const factory Change.keep() = _Keep<T>;
  const factory Change.set(T value) = _Set<T>;
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

extension ChangeField<T> on Field<T> {
  List<Assignment> change(Change<T> change) => switch (change) {
    _Keep<T>() => [],
    _Set<T>(:final value) => [set(value)],
    _Default<T>() => [defaultValue()],
  };
}
