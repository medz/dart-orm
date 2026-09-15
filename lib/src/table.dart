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
  final ComputedColumn? computed;

  /// Called once for an omitted value when constructing an insert. Prepared
  /// mutations retain that value; compilation and updates never call this.
  final T Function()? clientDefault;

  /// Signed integer storage width (16, 32 or 64). The default is 64.
  /// This describes the column, not the result width of SQL arithmetic.
  final int? integerBits;
  final int? decimalPrecision;
  final int? decimalScale;
  final int? temporalPrecision;
  const Column(
    this.name,
    this.codec, {
    this.nullable = false,
    this.generated = false,
    this.defaultSql,
    this.computed,
    this.clientDefault,
    this.integerBits,
    this.decimalPrecision,
    this.decimalScale,
    this.temporalPrecision,
  });
}

enum ComputedStorage { stored, virtual }

/// Database-computed SQL using physical column names.
final class ComputedColumn {
  final String sqlite, postgres;
  final ComputedStorage storage;
  const ComputedColumn(
    String expression, {
    this.storage = ComputedStorage.stored,
  }) : sqlite = expression,
       postgres = expression;
  const ComputedColumn.forDialects({
    required this.sqlite,
    required this.postgres,
    this.storage = ComputedStorage.stored,
  });
  String expression(SqlDialect dialect) =>
      dialect == SqlDialect.sqlite ? sqlite : postgres;
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

/// A row CHECK expression. A null name leaves naming to the database.
final class CheckSchema {
  final String? name;
  final String sqlite;
  final String postgres;
  const CheckSchema(this.name, String expression)
    : sqlite = expression,
      postgres = expression;
  const CheckSchema.forDialects(
    this.name, {
    required this.sqlite,
    required this.postgres,
  });
  String expression(SqlDialect dialect) =>
      dialect == SqlDialect.sqlite ? sqlite : postgres;
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
  final List<CheckSchema> checks;
  final List<Column<Object?>> _clientDefaults;
  TableSchema(
    this.name, {
    required List<Column<Object?>> columns,
    List<String> primaryKey = const [],
    List<List<String>> uniqueKeys = const [],
    List<ForeignKey> foreignKeys = const [],
    List<IndexSchema> indexes = const [],
    List<CheckSchema> checks = const [],
  }) : columns = List.unmodifiable(columns),
       _clientDefaults = List.unmodifiable(
         columns.where((c) => c.clientDefault != null),
       ),
       primaryKey = List.unmodifiable(primaryKey),
       uniqueKeys = List.unmodifiable(
         uniqueKeys.map(List<String>.unmodifiable),
       ),
       foreignKeys = List.unmodifiable([
         for (final key in foreignKeys)
           ForeignKey(
             List.unmodifiable(key.columns),
             key.target,
             List.unmodifiable(key.targetColumns),
             onDelete: key.onDelete,
           ),
       ]),
       checks = List.unmodifiable(checks),
       indexes = List.unmodifiable([
         for (final index in indexes)
           IndexSchema(
             index.name,
             List.unmodifiable(index.columns),
             unique: index.unique,
           ),
       ]);
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
  Assignment set(T value) => _assign(_Parameter(codec.encode(value)));
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
                )
        : _DecimalCast(
            node,
            definition.decimalPrecision!,
            definition.decimalScale ?? 0,
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
