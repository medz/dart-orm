part of '../../migrate.dart';

/// Statically imported migrations and their independently recorded fingerprints.
/// Keep these entries in version order. [checked] validates before returning them.
final class MigrationHistory {
  final SqlDialect dialect;
  final List<(Migration, String)> entries;
  MigrationHistory(
    Iterable<(Migration, String)> entries, {
    required this.dialect,
  }) : entries = List.unmodifiable(entries);

  List<Migration> get checked {
    final migrations = <Migration>[];
    for (final (migration, expected) in entries) {
      if (migration.checksum != expected) {
        throw OrmException(
          'MIGRATION.CHECKSUM',
          'Migration ${migration.id} differs from its recorded Dart definition.',
        );
      }
      migrations.add(migration);
    }
    validateMigrations(migrations, dialect: dialect);
    return List.unmodifiable(migrations);
  }
}

/// Emits a standalone historical schema library, without application imports.
String schemaSource(SchemaSnapshot schema) =>
    '''
// Generated physical schema. Keep historical copies with their migration.
import 'package:orm/migrate.dart';

final schema = ${_snapshotSource(schema)};
''';

/// Emits a reviewed migration and its fixed fingerprint as ordinary Dart values.
/// Formatting/comments are not part of the fingerprint; SQL and operation data are.
String migrationSource(Migration migration) =>
    '''
// Review before applying. Applied migrations must remain unchanged.
import 'package:orm/migrate.dart';

const migrationChecksum = ${_dartValue(migration.checksum)};
final migration = Migration.steps(
  ${_dartValue(migration.id)},
  [${migration.steps.map(_stepSource).join(', ')}],
  dialect: SqlDialect.${migration.dialect.name},
  ${migration.previous == null ? '' : 'previous: ${_dartValue(migration.previous)},'}
  ${migration.snapshot == null ? '' : 'snapshot: _schema,'}
);
${migration.snapshot == null ? '' : '\nfinal _schema = ${_snapshotSource(migration.snapshot!)};'}
''';

/// Emits a static registry. Each file owns its recorded fingerprint so rebuilding
/// this registry does not silently accept edited migration definitions.
String migrationHistorySource(
  Iterable<String> ids, {
  required SqlDialect dialect,
}) {
  final names = ids.toList();
  if (names.toSet().length != names.length ||
      names.any((id) => !RegExp(r'^[0-9]+_[a-z][a-z0-9_]*$').hasMatch(id))) {
    throw ArgumentError('Use distinct migration IDs in version order.');
  }
  return '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
import 'package:orm/migrate.dart';
${[for (var i = 0; i < names.length; i++) "import 'm${names[i]}.dart' as m$i;"].join('\n')}

const migrationDialect = SqlDialect.${dialect.name};
final migrationHistory = MigrationHistory([
  ${[for (var i = 0; i < names.length; i++) '(m$i.migration, m$i.migrationChecksum),'].join('\n')}
], dialect: migrationDialect);
''';
}

String _snapshotSource(SchemaSnapshot schema) =>
    'SchemaSnapshot([${schema.tables.map(_tableSource).join(', ')}])';

String _tableSource(TableSchema table) =>
    '''TableSchema(
  ${_dartValue(table.name)},
  columns: [${table.columns.map(_columnSource).join(', ')}],
  primaryKey: ${_dartValue(table.primaryKey)},
  ${table.uniqueKeys.isEmpty ? '' : 'uniqueKeys: ${_dartValue(table.uniqueKeys)},'}
  ${table.indexes.isEmpty ? '' : 'indexes: [${table.indexes.map((i) => 'IndexSchema(${_dartValue(i.name)}, ${_dartValue(i.columns)}, unique: ${i.unique})').join(', ')}],'}
  ${table.foreignKeys.isEmpty ? '' : 'foreignKeys: [${table.foreignKeys.map((k) => 'ForeignKey(${_dartValue(k.columns)}, ${_dartValue(k.target)}, ${_dartValue(k.targetColumns)}, onDelete: ${_dartValue(k.onDelete)})').join(', ')}],'}
  ${table.checks.isEmpty ? '' : 'checks: [${table.checks.map(_checkSource).join(', ')}],'}
)''';

String _columnSource(Column<Object?> column) {
  final codec = switch (column.codec.sqlType) {
    'instant' => 'Codecs.dateTime',
    'date' => 'Codecs.date',
    'time' => 'Codecs.time',
    'local_datetime' => 'Codecs.localDateTime',
    'blob' => 'Codecs.bytes',
    'timestamp' => "Codec<Object?>('timestamp', (v) => v, (v) => v)",
    'integer' ||
    'bigint' ||
    'decimal' ||
    'text' ||
    'real' ||
    'boolean' ||
    'json' => 'Codecs.${column.codec.sqlType}',
    final unsupported => throw OrmException(
      'SCHEMA.TYPE',
      'Unknown storage type $unsupported.',
    ),
  };
  return '''Column(
    ${_dartValue(column.name)}, $codec${column.nullable ? '.nullable()' : ''},
    ${column.nullable ? 'nullable: true,' : ''}
    ${column.generated ? 'generated: true,' : ''}
    ${column.defaultSql == null ? '' : 'defaultSql: ${_dartValue(column.defaultSql)},'}
    ${column.computed == null ? '' : 'computed: ${_computedSource(column.computed!)},'}
    ${column.integerBits == null ? '' : 'integerBits: ${column.integerBits},'}
    ${column.decimalPrecision == null ? '' : 'decimalPrecision: ${column.decimalPrecision},'}
    ${column.decimalScale == null ? '' : 'decimalScale: ${column.decimalScale},'}
    ${column.temporalPrecision == null ? '' : 'temporalPrecision: ${column.temporalPrecision},'}
  )''';
}

String _computedSource(ComputedColumn column) =>
    column.sqlite == column.postgres &&
        column.mysql == column.sqlite &&
        column.mariadb == column.sqlite
    ? 'ComputedColumn(${_dartValue(column.sqlite)}, storage: ComputedStorage.${column.storage.name})'
    : 'ComputedColumn.forDialects(sqlite: ${_dartValue(column.sqlite)}, postgres: ${_dartValue(column.postgres)}, mysql: ${_dartValue(column.mysql)}, mariadb: ${_dartValue(column.mariadb)}, storage: ComputedStorage.${column.storage.name})';
String _checkSource(CheckSchema check) =>
    check.sqlite == check.postgres &&
        check.mysql == check.sqlite &&
        check.mariadb == check.sqlite
    ? 'CheckSchema(${_dartValue(check.name)}, ${_dartValue(check.sqlite)})'
    : 'CheckSchema.forDialects(${_dartValue(check.name)}, sqlite: ${_dartValue(check.sqlite)}, postgres: ${_dartValue(check.postgres)}, mysql: ${_dartValue(check.mysql)}, mariadb: ${_dartValue(check.mariadb)})';

String _stepSource(MigrationStep step) => switch (step) {
  ExecuteSql() => 'ExecuteSql(${_dartValue(step.sql)})',
  CheckedTableSql() =>
    'CheckedTableSql(${_dartValue(step.sql)}, before: ${step.before == null ? 'null' : _tableSource(step.before!)}, after: ${step.after == null ? 'null' : _tableSource(step.after!)})',
  DropTable() => 'DropTable(${_dartValue(step.table)})',
  DropConstraint() =>
    'DropConstraint(${_dartValue(step.table)}, ${_dartValue(step.constraint)})',
  RebuildTable() =>
    'RebuildTable(${_tableSource(step.before)}, ${_tableSource(step.after)}, copy: ${_dartValue(step.copy)})',
  CheckedSql() =>
    'CheckedSql(${_dartValue(step.sql)}, readyWhen: ${_dartValue(step.readyWhen)}, doneWhen: ${_dartValue(step.doneWhen)})',
  Backfill() =>
    'Backfill(${_tableSource(step.table)}, set: ${_dartValue(step.set)}, where: ${_dartValue(step.where)}, doneWhen: ${_dartValue(step.doneWhen)}, batchSize: ${step.batchSize})',
};

String _dartValue(Object? value) => switch (value) {
  String() => jsonEncode(value).replaceAll(r'$', r'\$'),
  null || bool() || int() => '$value',
  List<Object?>() => '[${value.map(_dartValue).join(', ')}]',
  Map<String, Object?>() =>
    '{${value.entries.map((e) => '${_dartValue(e.key)}: ${_dartValue(e.value)}').join(', ')}}',
  _ => throw ArgumentError.value(
    value,
    'value',
    'Unsupported migration literal.',
  ),
};
