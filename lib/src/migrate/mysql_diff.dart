import '../../driver.dart' show SqlDialect;
import '../../schema_model.dart' show Column, IndexSchema, TableSchema;
import '../../values.dart' show OrmException;
import 'checks.dart' show checkDelta;
import 'diff.dart' show SchemaRenames;
import 'migration.dart' show Migration;
import 'mysql_schema.dart'
    show
        mysqlAddForeign,
        mysqlColumn,
        mysqlCopy,
        mysqlCreateTable,
        mysqlForeignName,
        mysqlPhysicalTable,
        mysqlUniqueName;
import 'schema.dart' show checkDefinition, sameStorage;
import 'snapshot.dart'
    show SchemaSnapshot, columnJson, foreignKeyJson, indexJson;
import 'sql_utils.dart' show migrationHash, quoteIdentifier;
import 'step.dart' show CheckedTableSql, MigrationStep;

Migration mysqlDiff(
  String id, {
  required SqlDialect dialect,
  required SchemaSnapshot from,
  required SchemaSnapshot to,
  required SchemaRenames renames,
  required String? previous,
  required bool allowDestructive,
  required Map<String, Map<String, String>> using,
}) {
  if (using.isNotEmpty) {
    throw const OrmException(
      'MIGRATION.CAST',
      'MySQL/MariaDB ALTER does not support USING. Backfill an explicit replacement column before changing its storage.',
    );
  }
  final state = {
    for (final table in from.tables) table.name: mysqlPhysicalTable(table),
  };
  final target = {
    for (final table in to.tables) table.name: mysqlPhysicalTable(table),
  };
  final steps = <MigrationStep>[];
  void validateNames(
    Map<String, String> names,
    Set<String> old,
    Set<String> next,
  ) {
    if (names.values.toSet().length != names.length ||
        names.entries.any(
          (e) =>
              !old.contains(e.key) ||
              old.contains(e.value) ||
              !next.contains(e.value),
        )) {
      throw const OrmException(
        'MIGRATION.RENAME',
        'Rename sources must exist and targets must be new, distinct target names.',
      );
    }
  }

  validateNames(renames.tables, state.keys.toSet(), target.keys.toSet());
  String tableName(String name) => renames.tables[name] ?? name;
  String columnName(String table, String column) =>
      renames.columns[tableName(table)]?[column] ?? column;
  for (final entry in renames.columns.entries) {
    final before = state.values
        .where((t) => tableName(t.name) == entry.key)
        .firstOrNull;
    final after = target[entry.key];
    if (before == null || after == null) {
      throw const OrmException(
        'MIGRATION.RENAME',
        'Column rename requires a surviving table.',
      );
    }
    validateNames(
      entry.value,
      before.columns.map((c) => c.name).toSet(),
      after.columns.map((c) => c.name).toSet(),
    );
  }
  void append(String sql, TableSchema? before, TableSchema? after) {
    steps.add(CheckedTableSql(sql, before: before, after: after));
    if (before != null) state.remove(before.name);
    if (after != null) state[after.name] = after;
  }

  bool same(Object? a, Object? b) => migrationHash(a) == migrationHash(b);
  bool columnChanges(String table, List<String> columns) {
    final old = state[table], next = target[tableName(table)];
    if (old == null || next == null || tableName(table) != table) return true;
    return columns.any((name) {
      final prior = old.columns.where((c) => c.name == name).firstOrNull;
      final after = next.columns
          .where((c) => c.name == columnName(table, name))
          .firstOrNull;
      return prior == null ||
          after == null ||
          name != after.name ||
          !sameStorage(prior, after);
    });
  }

  // Drop affected FK constraints first, including incoming keys on other tables.
  // Their explicit backing indexes remain until the ordinary table diff below.
  for (final before in state.values.toList()) {
    final next = target[tableName(before.name)];
    final drop = before.foreignKeys
        .where(
          (key) =>
              next == null ||
              columnChanges(before.name, key.columns) ||
              columnChanges(key.target, key.targetColumns) ||
              !next.foreignKeys.any(
                (candidate) =>
                    same(foreignKeyJson(key), foreignKeyJson(candidate)),
              ) ||
              !same(
                state[key.target]?.primaryKey,
                target[tableName(key.target)]?.primaryKey,
              ) ||
              !same(
                state[key.target]?.uniqueKeys,
                target[tableName(key.target)]?.uniqueKeys,
              ),
        )
        .toList();
    if (drop.isNotEmpty) {
      append(
        'ALTER TABLE ${quoteIdentifier(before.name)} ${drop.map((key) => 'DROP FOREIGN KEY ${quoteIdentifier(mysqlForeignName(before.name, key))}').join(', ')}',
        before,
        mysqlCopy(
          before,
          foreignKeys: before.foreignKeys
              .where((key) => !drop.contains(key))
              .toList(),
        ),
      );
    }
  }
  for (final before in state.values.toList()) {
    if (target.containsKey(tableName(before.name))) continue;
    if (!allowDestructive) {
      throw OrmException(
        'MIGRATION.DESTRUCTIVE',
        'Dropping ${before.name} requires allowDestructive.',
      );
    }
    append('DROP TABLE ${quoteIdentifier(before.name)}', before, null);
  }
  for (final entry in renames.tables.entries) {
    final before = state[entry.key]!;
    final changes = [
      for (final key in before.uniqueKeys)
        'RENAME INDEX ${quoteIdentifier(mysqlUniqueName(entry.key, key))} TO ${quoteIdentifier(mysqlUniqueName(entry.value, key))}',
      'RENAME TO ${quoteIdentifier(entry.value)}',
    ];
    append(
      'ALTER TABLE ${quoteIdentifier(before.name)} ${changes.join(', ')}',
      before,
      mysqlCopy(before, name: entry.value),
    );
  }
  for (final after in target.values) {
    final before = state[after.name];
    if (before == null) {
      final created = mysqlCopy(after, foreignKeys: []);
      append(mysqlCreateTable(created, dialect), null, created);
      continue;
    }
    final names = renames.columns[after.name] ?? const <String, String>{};
    String renamed(String name) => names[name] ?? name;
    final operations = <String>[];
    final desired = mysqlCopy(after, foreignKeys: before.foreignKeys);
    final removed = before.columns
        .where(
          (column) => !after.columns.any((c) => c.name == renamed(column.name)),
        )
        .toList();
    if (removed.isNotEmpty && !allowDestructive) {
      throw OrmException(
        'MIGRATION.DESTRUCTIVE',
        'Removing columns from ${after.name} requires allowDestructive.',
      );
    }
    for (final column in before.columns) {
      final next = after.columns
          .where((c) => c.name == renamed(column.name))
          .firstOrNull;
      if (next == null) {
        operations.add('DROP COLUMN ${quoteIdentifier(column.name)}');
        continue;
      }
      if (column.generated != next.generated) {
        throw const OrmException(
          'MIGRATION.IDENTITY',
          'Identity changes require a reviewed manual migration.',
        );
      }
      if (!sameStorage(column, next) && !_mysqlSafeWiden(column, next)) {
        throw OrmException(
          'MIGRATION.CAST',
          '${after.name}.${next.name} requires a reviewed replacement-column/backfill migration.',
        );
      }
      if ((column.computed == null) != (next.computed == null) ||
          column.computed?.storage != next.computed?.storage) {
        throw const OrmException(
          'MIGRATION.COMPUTED',
          'Changing stored/generated mode requires an explicit reviewed replacement migration.',
        );
      }
      if (column.name != next.name) {
        operations.add(
          'CHANGE COLUMN ${quoteIdentifier(column.name)} ${mysqlColumn(next, dialect)}',
        );
      } else if (!same(columnJson(column), columnJson(next))) {
        operations.add('MODIFY COLUMN ${mysqlColumn(next, dialect)}');
      }
    }
    for (final column in after.columns) {
      if (before.columns.any((c) => renamed(c.name) == column.name)) continue;
      if (column.generated ||
          column.computed == null &&
              !column.nullable &&
              column.defaultSql == null) {
        throw OrmException(
          'MIGRATION.BACKFILL',
          '${after.name}.${column.name} needs a nullable/defaulted stage and explicit backfill.',
        );
      }
      operations.add('ADD COLUMN ${mysqlColumn(column, dialect)}');
    }
    if (!same(before.primaryKey.map(renamed).toList(), after.primaryKey)) {
      if (before.primaryKey.isNotEmpty) operations.add('DROP PRIMARY KEY');
      if (after.primaryKey.isNotEmpty) {
        operations.add(
          'ADD PRIMARY KEY (${after.primaryKey.map(quoteIdentifier).join(', ')})',
        );
      }
    }
    final pendingUnique = after.uniqueKeys.toList();
    for (final key in before.uniqueKeys) {
      final mapped = key.map(renamed).toList();
      final i = pendingUnique.indexWhere((k) => same(k, mapped));
      final oldName = mysqlUniqueName(after.name, key);
      if (i < 0) {
        operations.add('DROP INDEX ${quoteIdentifier(oldName)}');
      } else {
        final nextName = mysqlUniqueName(after.name, mapped);
        if (oldName != nextName) {
          operations.add(
            'RENAME INDEX ${quoteIdentifier(oldName)} TO ${quoteIdentifier(nextName)}',
          );
        }
        pendingUnique.removeAt(i);
      }
    }
    for (final key in pendingUnique) {
      operations.add(
        'ADD CONSTRAINT ${quoteIdentifier(mysqlUniqueName(after.name, key))} UNIQUE (${key.map(quoteIdentifier).join(', ')})',
      );
    }
    final pendingIndexes = after.indexes.toList();
    for (final index in before.indexes) {
      final mapped = IndexSchema(
        index.name,
        index.columns.map(renamed).toList(),
        unique: index.unique,
      );
      final i = pendingIndexes.indexWhere(
        (candidate) => same(indexJson(mapped), indexJson(candidate)),
      );
      if (i < 0) {
        operations.add('DROP INDEX ${quoteIdentifier(index.name)}');
      } else {
        pendingIndexes.removeAt(i);
      }
    }
    for (final index in pendingIndexes) {
      operations.add(
        'ADD ${index.unique ? 'UNIQUE ' : ''}INDEX ${quoteIdentifier(index.name)} (${index.columns.map(quoteIdentifier).join(', ')})',
      );
    }
    final checks = checkDelta(before.checks, after.checks, dialect);
    for (final check in checks.removed) {
      if (check.name == null) {
        throw const OrmException(
          'MIGRATION.CHECK',
          'Removing an unnamed MySQL/MariaDB check requires a reviewed step with its catalog name.',
        );
      }
      operations.add(
        'DROP ${dialect == SqlDialect.mysql ? 'CHECK' : 'CONSTRAINT'} ${quoteIdentifier(check.name!)}',
      );
    }
    for (final check in checks.added) {
      operations.add('ADD ${checkDefinition(check, dialect)}');
    }
    if (operations.isNotEmpty) {
      append(
        'ALTER TABLE ${quoteIdentifier(after.name)} ${operations.join(', ')}',
        before,
        desired,
      );
    }
  }
  for (final after in target.values) {
    final before = state[after.name]!;
    final add = after.foreignKeys
        .where(
          (key) => !before.foreignKeys.any(
            (old) => same(foreignKeyJson(old), foreignKeyJson(key)),
          ),
        )
        .toList();
    if (add.isNotEmpty) {
      append(
        'ALTER TABLE ${quoteIdentifier(after.name)} ${add.map((key) => mysqlAddForeign(after.name, key)).join(', ')}',
        before,
        after,
      );
    }
  }
  return Migration.steps(
    id,
    steps,
    dialect: dialect,
    snapshot: to,
    previous: previous,
  );
}

bool _mysqlSafeWiden(Column<Object?> before, Column<Object?> after) {
  if (before.codec.sqlType != after.codec.sqlType) return false;
  return switch (before.codec.sqlType) {
    'integer' => (after.integerBits ?? 64) >= (before.integerBits ?? 64),
    'decimal' =>
      after.decimalPrecision != null &&
          before.decimalPrecision != null &&
          (after.decimalScale ?? 0) >= (before.decimalScale ?? 0) &&
          after.decimalPrecision! - (after.decimalScale ?? 0) >=
              before.decimalPrecision! - (before.decimalScale ?? 0),
    'time' || 'instant' || 'local_datetime' =>
      (after.temporalPrecision ?? 6) >= (before.temporalPrecision ?? 6),
    _ => false,
  };
}
