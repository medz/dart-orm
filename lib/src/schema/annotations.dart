/// Declares a database table independently from its Dart row type.
final class Table {
  const Table(this.name);
  final String name;
}

/// Overrides a field's SQL name and optional literal database default.
final class Column {
  const Column({this.name, this.defaultValue});
  final String? name;
  final Object? defaultValue;
}

/// Declares a primary key. Identity keys must be non-nullable integers.
final class PrimaryKey {
  const PrimaryKey({this.autoIncrement = false});
  final bool autoIncrement;
}

/// Declares a unique column constraint.
final class Unique {
  const Unique();
}

/// Declares a foreign key by physical table/column identity.
final class References {
  const References(
    this.table, {
    this.column = 'id',
    this.onDelete = 'restrict',
  });
  final String table;
  final String column;
  final String onDelete;
}

/// Registers a named-record selection against a declared row type.
/// Generated code rejects unknown selections before SQL execution.
final class SelectFrom {
  const SelectFrom(this.rowType);
  final Type rowType;
}
