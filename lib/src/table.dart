part of '../orm.dart';

/// A table occurrence has nominal identity, even when two row records have the
/// same structural Dart type or a query joins the same physical table twice.
final class TableRef {
  final TableSchema schema;
  TableRef(this.schema);
}

final class Column<T> {
  final String name;
  final Codec<T> codec;
  final bool nullable;
  final bool generated;
  final String? defaultSql;
  const Column(
    this.name,
    this.codec, {
    this.nullable = false,
    this.generated = false,
    this.defaultSql,
  });
}

final class ForeignKey {
  final List<String> columns;
  final String target;
  final List<String> targetColumns;
  final String onDelete;
  const ForeignKey(
    this.columns,
    this.target,
    this.targetColumns, {
    this.onDelete = 'RESTRICT',
  });
}

final class IndexSchema {
  final String name;
  final List<String> columns;
  final bool unique;
  const IndexSchema(this.name, this.columns, {this.unique = false});
}

final class TableSchema {
  final String name;
  final List<Column<Object?>> columns;
  final List<String> primaryKey;
  final List<List<String>> uniqueKeys;
  final List<ForeignKey> foreignKeys;
  final List<IndexSchema> indexes;
  TableSchema(
    this.name, {
    required List<Column<Object?>> columns,
    List<String> primaryKey = const [],
    List<List<String>> uniqueKeys = const [],
    List<ForeignKey> foreignKeys = const [],
    List<IndexSchema> indexes = const [],
  }) : columns = List.unmodifiable(columns),
       primaryKey = List.unmodifiable(primaryKey),
       uniqueKeys = List.unmodifiable(
         uniqueKeys.map(List<String>.unmodifiable),
       ),
       foreignKeys = List.unmodifiable(foreignKeys),
       indexes = List.unmodifiable(indexes);
}

abstract class Fields {
  final TableRef table;
  const Fields(this.table);
  Field<T> column<T>(Column<T> column) => Field._(table, column);
}

final class Field<T> extends Expr<T> {
  final TableRef table;
  final Column<T> definition;
  Field._(this.table, this.definition)
    : super._(_ColumnNode(table, definition.name), definition.codec);
  Assignment set(T value) =>
      Assignment._(this, _Parameter(codec.encode(value)));
  Assignment setExpression(Expr<T> expression) =>
      Assignment._(this, expression._node);
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
