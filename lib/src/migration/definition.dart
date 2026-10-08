import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:orm/database.dart' show Engine;
import 'package:orm/schema.dart';

/// A reviewed migration saved as Dart source, independent of application types.
///
/// [steps] contains SQL for exactly [engine]. [snapshot] describes the complete
/// managed schema after applying it. Construction checks [reviewedFingerprint];
/// editing SQL or schema requires a new migration, never a revised fingerprint
/// on an already applied definition. Collections are copied and frozen.
final class Migration {
  Migration({
    required this.version,
    required this.name,
    required this.engine,
    required List<String> steps,
    required SchemaSnapshot snapshot,
    required this.reviewedFingerprint,
  }) : steps = List.unmodifiable(steps),
       snapshot = freezeSnapshot(snapshot) {
    if (version < 1 || name.trim().isEmpty) {
      throw ArgumentError('Migration needs a positive version and a name.');
    }
    if (engine != snapshot.engine) {
      throw ArgumentError('Migration and snapshot engines differ.');
    }
    if (steps.any((step) => step.trim().isEmpty)) {
      throw ArgumentError('Migration SQL steps must not be empty.');
    }
    if (fingerprint != reviewedFingerprint) {
      throw StateError(
        'Migration $version does not match its reviewed fingerprint.',
      );
    }
  }

  final int version;
  final String name;
  final Engine engine;
  final List<String> steps;
  final SchemaSnapshot snapshot;
  final String reviewedFingerprint;

  /// SHA-256 over version, name, engine, SQL and every frozen schema property.
  String get fingerprint => migrationFingerprint(
    version: version,
    name: name,
    engine: engine,
    steps: steps,
    snapshot: snapshot,
  );
}

/// Ordered static registration of immutable migrations for one engine.
///
/// Versions must be positive and strictly increasing. Gaps are allowed; sorting
/// or rewriting historical entries is never performed automatically.
final class MigrationHistory {
  MigrationHistory({required this.engine, required List<Migration> migrations})
    : migrations = List.unmodifiable(migrations) {
    var previous = 0;
    for (final migration in migrations) {
      if (migration.engine != engine) {
        throw ArgumentError('A migration history cannot mix database engines.');
      }
      if (migration.version <= previous) {
        throw ArgumentError('Migration versions must be strictly increasing.');
      }
      if (migration.fingerprint != migration.reviewedFingerprint) {
        throw StateError(
          'Migration ${migration.version} changed after review.',
        );
      }
      previous = migration.version;
    }
  }

  final Engine engine;
  final List<Migration> migrations;
}

/// Calculates the fingerprint to paste into a reviewed Dart migration file.
///
/// This does not load or save any files. Collection order and SQL whitespace are
/// significant, so source changes cannot silently preserve the reviewed hash.
String migrationFingerprint({
  required int version,
  required String name,
  required Engine engine,
  required List<String> steps,
  required SchemaSnapshot snapshot,
}) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          'orm-migration-v1',
          version,
          name,
          engine.name,
          steps,
          snapshotValue(snapshot),
        ]),
      ),
    )
    .toString();

/// Copies and validates a snapshot without retaining mutable application data.
///
/// SQLite physical identifiers use ASCII case folding; PostgreSQL quoted names
/// preserve case and must fit within 63 UTF-8 bytes. SQLite's `sqlite_` table
/// prefix and the migration history table are reserved.
SchemaSnapshot freezeSnapshot(SchemaSnapshot snapshot) {
  final tables = <TableDefinition>[];
  final tableNames = <String>{};
  for (final table in snapshot.tables) {
    _validatePhysicalIdentifier(snapshot.engine, table.name);
    final tableIdentity = physicalIdentity(snapshot.engine, table.name);
    if (tableIdentity == '_orm_migrations' ||
        (snapshot.engine == Engine.sqlite &&
            tableIdentity.startsWith('sqlite_')) ||
        !tableNames.add(tableIdentity)) {
      throw ArgumentError('Duplicate or reserved table ${table.name}.');
    }
    if (table.columns.isEmpty) {
      throw ArgumentError('Table ${table.name} has no columns.');
    }
    final names = <String>{};
    final fields = <String>{};
    var primaryKeys = 0;
    final columns = <ColumnDefinition>[];
    for (final column in table.columns) {
      _validatePhysicalIdentifier(snapshot.engine, column.name);
      if (!names.add(physicalIdentity(snapshot.engine, column.name)) ||
          !fields.add(column.field)) {
        throw ArgumentError('Duplicate column or field in ${table.name}.');
      }
      if (column.field.isEmpty) {
        throw ArgumentError('Column field must not be empty.');
      }
      if (column.primaryKey) primaryKeys++;
      if (column.primaryKey && column.nullable) {
        throw ArgumentError('Primary keys cannot be nullable.');
      }
      if (column.identity &&
          (!column.primaryKey ||
              column.type != ScalarType.integer ||
              column.defaultValue != null)) {
        throw ArgumentError(
          'Identity requires an integer primary key without a default.',
        );
      }
      final reference = column.references;
      if (reference != null) {
        _validatePhysicalIdentifier(snapshot.engine, reference.table);
        _validatePhysicalIdentifier(snapshot.engine, reference.column);
        if (!const {
          'restrict',
          'cascade',
          'set null',
          'no action',
        }.contains(reference.onDelete.toLowerCase())) {
          throw ArgumentError('Unsupported ON DELETE ${reference.onDelete}.');
        }
        if (reference.onDelete.toLowerCase() == 'set null' &&
            !column.nullable) {
          throw ArgumentError('SET NULL requires a nullable foreign key.');
        }
      }
      final value = column.defaultValue;
      validateDefault(column);
      columns.add(
        ColumnDefinition(
          name: column.name,
          field: column.field,
          type: column.type,
          nullable: column.nullable,
          primaryKey: column.primaryKey,
          identity: column.identity,
          unique: column.unique,
          defaultValue: value is Uint8List
              ? Uint8List.fromList(value).asUnmodifiableView()
              : value,
          references: reference,
        ),
      );
    }
    if (primaryKeys > 1) {
      throw ArgumentError('Composite primary keys are not supported.');
    }
    tables.add(TableDefinition(table.name, List.unmodifiable(columns)));
  }
  final result = SchemaSnapshot(
    engine: snapshot.engine,
    tables: List.unmodifiable(tables),
  );
  for (final table in result.tables) {
    for (final column in table.columns) {
      final reference = column.references;
      if (reference == null) continue;
      final target = result.tables
          .where(
            (t) =>
                physicalIdentity(snapshot.engine, t.name) ==
                physicalIdentity(snapshot.engine, reference.table),
          )
          .firstOrNull;
      final key = target?.columns
          .where(
            (c) =>
                physicalIdentity(snapshot.engine, c.name) ==
                physicalIdentity(snapshot.engine, reference.column),
          )
          .firstOrNull;
      if (key == null ||
          (!key.primaryKey && !key.unique) ||
          key.type != column.type) {
        throw ArgumentError(
          'Foreign key ${table.name}.${column.name} needs a matching unique target.',
        );
      }
    }
  }
  return result;
}

// SQLite identifiers fold ASCII letters even when quoted. Unicode characters
// remain distinct. PostgreSQL quoted identifiers preserve their original case.
String physicalIdentity(Engine engine, String name) => engine == Engine.sqlite
    ? String.fromCharCodes(
        name.codeUnits.map(
          (unit) => unit >= 65 && unit <= 90 ? unit + 32 : unit,
        ),
      )
    : name;

void _validatePhysicalIdentifier(Engine engine, String name) {
  validIdentifier(name);
  if (engine == Engine.postgresql && utf8.encode(name).length > 63) {
    throw ArgumentError(
      'PostgreSQL identifiers must fit within 63 UTF-8 bytes.',
    );
  }
}

void validIdentifier(String value) {
  if (value.isEmpty || value.contains('\u0000')) {
    throw ArgumentError('Invalid SQL identifier.');
  }
}

void validateDefault(ColumnDefinition column) {
  final value = column.defaultValue;
  if (value == null) return;
  final valid = switch (column.type) {
    ScalarType.integer => value is int,
    ScalarType.text => value is String,
    ScalarType.boolean => value is bool,
    ScalarType.real => value is num && value.isFinite,
    ScalarType.dateTime => value is DateTime,
    ScalarType.bytes => value is Uint8List,
  };
  if (!valid) {
    throw ArgumentError(
      'Default for ${column.name} does not match ${column.type.name}.',
    );
  }
}

Object snapshotValue(SchemaSnapshot snapshot) => [
  snapshot.engine.name,
  [
    for (final table in snapshot.tables)
      [
        table.name,
        [for (final column in table.columns) columnValue(column)],
      ],
  ],
];

Object columnValue(ColumnDefinition column) => [
  column.name,
  column.field,
  column.type.name,
  column.nullable,
  column.primaryKey,
  column.identity,
  column.unique,
  defaultValue(column.defaultValue),
  if (column.references case final reference?)
    [reference.table, reference.column, reference.onDelete]
  else
    null,
];

Object? defaultValue(Object? value) => switch (value) {
  DateTime value => ['dateTime', value.toUtc().toIso8601String()],
  Uint8List value => ['bytes', base64Encode(value)],
  _ => value,
};
