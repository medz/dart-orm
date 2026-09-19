part of '../../migrate.dart';

Migration _mysqlDiff(
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
    for (final table in from.tables) table.name: _mysqlPhysicalTable(table),
  };
  final target = {
    for (final table in to.tables) table.name: _mysqlPhysicalTable(table),
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

  bool same(Object? a, Object? b) => _hash(a) == _hash(b);
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
          !_sameStorage(prior, after);
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
                    same(_foreignKeyJson(key), _foreignKeyJson(candidate)),
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
        'ALTER TABLE ${_quote(before.name)} ${drop.map((key) => 'DROP FOREIGN KEY ${_quote(_mysqlForeignName(before.name, key))}').join(', ')}',
        before,
        _mysqlCopy(
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
    append('DROP TABLE ${_quote(before.name)}', before, null);
  }
  for (final entry in renames.tables.entries) {
    final before = state[entry.key]!;
    final changes = [
      for (final key in before.uniqueKeys)
        'RENAME INDEX ${_quote(_mysqlUniqueName(entry.key, key))} TO ${_quote(_mysqlUniqueName(entry.value, key))}',
      'RENAME TO ${_quote(entry.value)}',
    ];
    append(
      'ALTER TABLE ${_quote(before.name)} ${changes.join(', ')}',
      before,
      _mysqlCopy(before, name: entry.value),
    );
  }
  for (final after in target.values) {
    final before = state[after.name];
    if (before == null) {
      final created = _mysqlCopy(after, foreignKeys: []);
      append(_mysqlCreateTable(created, dialect), null, created);
      continue;
    }
    final names = renames.columns[after.name] ?? const <String, String>{};
    String renamed(String name) => names[name] ?? name;
    final operations = <String>[];
    final desired = _mysqlCopy(after, foreignKeys: before.foreignKeys);
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
        operations.add('DROP COLUMN ${_quote(column.name)}');
        continue;
      }
      if (column.generated != next.generated) {
        throw const OrmException(
          'MIGRATION.IDENTITY',
          'Identity changes require a reviewed manual migration.',
        );
      }
      if (!_sameStorage(column, next) && !_mysqlSafeWiden(column, next)) {
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
          'CHANGE COLUMN ${_quote(column.name)} ${_mysqlColumn(next, dialect)}',
        );
      } else if (!same(_columnJson(column), _columnJson(next))) {
        operations.add('MODIFY COLUMN ${_mysqlColumn(next, dialect)}');
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
      operations.add('ADD COLUMN ${_mysqlColumn(column, dialect)}');
    }
    if (!same(before.primaryKey.map(renamed).toList(), after.primaryKey)) {
      if (before.primaryKey.isNotEmpty) operations.add('DROP PRIMARY KEY');
      if (after.primaryKey.isNotEmpty) {
        operations.add(
          'ADD PRIMARY KEY (${after.primaryKey.map(_quote).join(', ')})',
        );
      }
    }
    final pendingUnique = after.uniqueKeys.toList();
    for (final key in before.uniqueKeys) {
      final mapped = key.map(renamed).toList();
      final i = pendingUnique.indexWhere((k) => same(k, mapped));
      final oldName = _mysqlUniqueName(after.name, key);
      if (i < 0) {
        operations.add('DROP INDEX ${_quote(oldName)}');
      } else {
        final nextName = _mysqlUniqueName(after.name, mapped);
        if (oldName != nextName) {
          operations.add(
            'RENAME INDEX ${_quote(oldName)} TO ${_quote(nextName)}',
          );
        }
        pendingUnique.removeAt(i);
      }
    }
    for (final key in pendingUnique) {
      operations.add(
        'ADD CONSTRAINT ${_quote(_mysqlUniqueName(after.name, key))} UNIQUE (${key.map(_quote).join(', ')})',
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
        (candidate) => same(_indexJson(mapped), _indexJson(candidate)),
      );
      if (i < 0) {
        operations.add('DROP INDEX ${_quote(index.name)}');
      } else {
        pendingIndexes.removeAt(i);
      }
    }
    for (final index in pendingIndexes) {
      operations.add(
        'ADD ${index.unique ? 'UNIQUE ' : ''}INDEX ${_quote(index.name)} (${index.columns.map(_quote).join(', ')})',
      );
    }
    final checks = _checkDelta(before.checks, after.checks, dialect);
    for (final check in checks.removed) {
      if (check.name == null) {
        throw const OrmException(
          'MIGRATION.CHECK',
          'Removing an unnamed MySQL/MariaDB check requires a reviewed step with its catalog name.',
        );
      }
      operations.add(
        'DROP ${dialect == SqlDialect.mysql ? 'CHECK' : 'CONSTRAINT'} ${_quote(check.name!)}',
      );
    }
    for (final check in checks.added) {
      operations.add('ADD ${_checkDefinition(check, dialect)}');
    }
    if (operations.isNotEmpty) {
      append(
        'ALTER TABLE ${_quote(after.name)} ${operations.join(', ')}',
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
            (old) => same(_foreignKeyJson(old), _foreignKeyJson(key)),
          ),
        )
        .toList();
    if (add.isNotEmpty) {
      append(
        'ALTER TABLE ${_quote(after.name)} ${add.map((key) => _mysqlAddForeign(after.name, key)).join(', ')}',
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
