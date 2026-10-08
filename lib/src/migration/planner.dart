import 'dart:convert';
import 'dart:typed_data';

import 'package:orm/database.dart' show Engine;
import 'package:orm/schema.dart';

import 'definition.dart';

/// SQL for a reviewed schema transition on one database engine.
///
/// Automatic planning only creates tables and adds nullable or literal-default
/// columns. Drops, renames, constraint/type changes and identity changes require
/// explicitly authored migration SQL. No rename is inferred from similarity.
final class MigrationPlan {
  MigrationPlan({
    required this.engine,
    required List<String> steps,
    required SchemaSnapshot snapshot,
  }) : steps = List.unmodifiable(steps),
       snapshot = freezeSnapshot(snapshot) {
    if (engine != snapshot.engine) {
      throw ArgumentError('Plan and snapshot engines differ.');
    }
  }

  final Engine engine;
  final List<String> steps;
  final SchemaSnapshot snapshot;
}

/// Plans conservative additions between two complete frozen snapshots.
MigrationPlan planSchemaChange(SchemaSnapshot before, SchemaSnapshot after) {
  final old = freezeSnapshot(before);
  final next = freezeSnapshot(after);
  if (old.engine != next.engine) throw ArgumentError('Schema engines differ.');
  final oldTables = {for (final table in old.tables) table.name: table};
  final nextTables = {for (final table in next.tables) table.name: table};
  for (final name in oldTables.keys) {
    if (!nextTables.containsKey(name)) {
      throw StateError(
        'Dropping or renaming table $name requires explicit SQL.',
      );
    }
  }
  final steps = <String>[];
  final pending = {
    for (final table in next.tables)
      if (!oldTables.containsKey(table.name)) table.name: table,
  };
  final available = {
    for (final name in oldTables.keys) physicalIdentity(next.engine, name),
  };
  while (pending.isNotEmpty) {
    final ready = pending.values
        .where(
          (table) => table.columns.every(
            (column) =>
                column.references == null ||
                physicalIdentity(next.engine, column.references!.table) ==
                    physicalIdentity(next.engine, table.name) ||
                available.contains(
                  physicalIdentity(next.engine, column.references!.table),
                ),
          ),
        )
        .firstOrNull;
    if (ready == null) {
      throw StateError('Cyclic new-table references require explicit SQL.');
    }
    steps.add(
      'CREATE TABLE ${quoteIdentifier(ready.name)} (${ready.columns.map((c) => columnSql(next.engine, c)).join(', ')})',
    );
    pending.remove(ready.name);
    available.add(physicalIdentity(next.engine, ready.name));
  }
  for (final table in next.tables) {
    final previous = oldTables[table.name];
    if (previous == null) continue;
    final previousColumns = {
      for (final column in previous.columns) column.name: column,
    };
    final nextColumns = {
      for (final column in table.columns) column.name: column,
    };
    for (final name in previousColumns.keys) {
      if (!nextColumns.containsKey(name)) {
        throw StateError(
          'Dropping or renaming ${table.name}.$name requires explicit SQL.',
        );
      }
    }
    for (final column in table.columns) {
      final previousColumn = previousColumns[column.name];
      if (previousColumn != null) {
        if (!_sameStorage(previousColumn, column)) {
          throw StateError(
            'Changing ${table.name}.${column.name} requires explicit SQL.',
          );
        }
        continue;
      }
      if ((!column.nullable && column.defaultValue == null) ||
          column.primaryKey ||
          column.identity ||
          column.unique ||
          (column.references != null && column.defaultValue != null)) {
        throw StateError(
          'Adding ${table.name}.${column.name} requires explicit SQL for its constraints or existing rows.',
        );
      }
      steps.add(
        'ALTER TABLE ${quoteIdentifier(table.name)} ADD COLUMN ${columnSql(next.engine, column)}',
      );
    }
  }
  return MigrationPlan(engine: next.engine, steps: steps, snapshot: next);
}

bool _sameStorage(ColumnDefinition a, ColumnDefinition b) {
  final left = (columnValue(a) as List).toList()..[1] = '';
  final right = (columnValue(b) as List).toList()..[1] = '';
  return jsonEncode(left) == jsonEncode(right);
}

String quoteIdentifier(String value) {
  validIdentifier(value);
  return '"${value.replaceAll('"', '""')}"';
}

String storageType(Engine engine, ScalarType type) => switch ((engine, type)) {
  (
    Engine.sqlite,
    ScalarType.integer || ScalarType.boolean || ScalarType.dateTime,
  ) =>
    'INTEGER',
  (Engine.sqlite, ScalarType.text) => 'TEXT',
  (Engine.sqlite, ScalarType.real) => 'REAL',
  (Engine.sqlite, ScalarType.bytes) => 'BLOB',
  (Engine.postgresql, ScalarType.integer) => 'BIGINT',
  (Engine.postgresql, ScalarType.text) => 'TEXT',
  (Engine.postgresql, ScalarType.boolean) => 'BOOLEAN',
  (Engine.postgresql, ScalarType.real) => 'DOUBLE PRECISION',
  (Engine.postgresql, ScalarType.dateTime) => 'TIMESTAMPTZ',
  (Engine.postgresql, ScalarType.bytes) => 'BYTEA',
};

String columnSql(Engine engine, ColumnDefinition column) {
  final sql = StringBuffer(
    '${quoteIdentifier(column.name)} ${storageType(engine, column.type)}',
  );
  if (column.identity && engine == Engine.postgresql) {
    sql.write(' GENERATED ALWAYS AS IDENTITY');
  }
  if (column.primaryKey) sql.write(' PRIMARY KEY');
  if (column.identity && engine == Engine.sqlite) sql.write(' AUTOINCREMENT');
  if (!column.nullable) sql.write(' NOT NULL');
  if (column.unique && !column.primaryKey) sql.write(' UNIQUE');
  if (column.defaultValue != null) {
    sql.write(' DEFAULT ${literalSql(engine, column.defaultValue!)}');
  }
  if (column.references case final reference?) {
    sql.write(
      ' REFERENCES ${quoteIdentifier(reference.table)} (${quoteIdentifier(reference.column)}) ON DELETE ${reference.onDelete.toUpperCase()}',
    );
  }
  return sql.toString();
}

String literalSql(Engine engine, Object value) => switch (value) {
  String value => "'${value.replaceAll("'", "''")}'",
  bool value =>
    engine == Engine.sqlite ? (value ? '1' : '0') : (value ? 'TRUE' : 'FALSE'),
  int value => value.toString(),
  double value when value.isFinite => value.toString(),
  DateTime value =>
    engine == Engine.sqlite
        ? value.microsecondsSinceEpoch.toString()
        : literalSql(engine, _postgresTimestamp(value)),
  Uint8List value =>
    engine == Engine.sqlite
        ? "X'${_hex(value)}'"
        : "decode('${_hex(value)}', 'hex')",
  _ => throw ArgumentError('Unsupported SQL literal ${value.runtimeType}.'),
};

// PostgreSQL uses unsigned Gregorian years and BC, whereas Dart uses a signed
// astronomical year with year zero. Expanded positive years have no plus sign.
String _postgresTimestamp(DateTime value) {
  final utc = value.toUtc();
  final year = utc.year <= 0 ? 1 - utc.year : utc.year;
  final iso = utc.toIso8601String();
  return '${year.toString().padLeft(4, '0')}${iso.substring(iso.indexOf('-', 1))}${utc.year <= 0 ? ' BC' : ''}';
}

String _hex(Uint8List value) =>
    value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
