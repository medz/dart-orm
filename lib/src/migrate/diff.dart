import '../../driver.dart' show SqlDialect;
import '../../schema_model.dart'
    show Column, ComputedStorage, ForeignKey, IndexSchema, TableSchema;
import '../../values.dart' show OrmException;
import 'checks.dart' show checkDelta, withChecks;
import 'computed.dart' show materializedColumns;
import 'migration.dart' show Migration;
import 'mysql_diff.dart' show mysqlDiff;
import 'mysql_schema.dart' show isMysqlFamily;
import 'schema.dart'
    show
        checkDefinition,
        coerceColumn,
        columnDefinition,
        columnStorageType,
        createIndexSql,
        createTable,
        foreignKey,
        sameStorage;
import 'snapshot.dart'
    show SchemaSnapshot, columnJson, foreignKeyJson, indexJson;
import 'sql_utils.dart' show migrationHash, quoteIdentifier, quoteQualified;
import 'step.dart'
    show DropConstraint, DropTable, ExecuteSql, MigrationStep, RebuildTable;

/// Explicit physical renames. Column maps are keyed by the final table name.
/// Swaps and chains need separate migrations to make intermediate names explicit.
final class SchemaRenames {
  /// Existing physical table names mapped to their intended new names.
  final Map<String, String> tables;

  /// Old-to-new column names, grouped by the table's final physical name.
  final Map<String, Map<String, String>> columns;

  /// Declares intentional renames without inferring them from schema similarity.
  ///
  /// Maps are retained as provided. Diff generation validates targets and rejects
  /// swaps or chains that need explicit intermediate migration steps.
  const SchemaRenames({this.tables = const {}, this.columns = const {}});
}

Migration diffSchema(
  String id, {
  required SqlDialect dialect,
  required SchemaSnapshot from,
  required SchemaSnapshot to,
  required SchemaRenames renames,
  required String? previous,
  required bool allowDestructive,
  required Map<String, Map<String, String>> using,
}) {
  if (isMysqlFamily(dialect)) {
    return mysqlDiff(
      id,
      dialect: dialect,
      from: from,
      to: to,
      renames: renames,
      previous: previous,
      allowDestructive: allowDestructive,
      using: using,
    );
  }
  final sourceTables = {for (final t in from.tables) t.identity: t};
  final targetTables = {for (final t in to.tables) t.identity: t};
  String quoted(TableSchema table) =>
      quoteQualified(table.name, table.namespace);
  String tableSql(String identity) =>
      quoted(targetTables[identity] ?? sourceTables[identity]!);
  final renameSql = <MigrationStep>[];
  if (dialect == SqlDialect.postgres) {
    final previousNamespaces = from.tables.map((t) => t.namespace).toSet();
    final namespaces =
        to.tables
            .map((t) => t.namespace)
            .nonNulls
            .toSet()
            .difference(previousNamespaces.nonNulls.toSet())
            .toList()
          ..sort();
    for (final namespace in namespaces) {
      renameSql.add(
        ExecuteSql('CREATE SCHEMA IF NOT EXISTS ${quoteIdentifier(namespace)}'),
      );
    }
  }
  final oldNames = from.tables.map((t) => t.identity).toSet();
  final newNames = to.tables.map((t) => t.identity).toSet();
  void validateRenames(
    Map<String, String> map,
    Set<String> old,
    Set<String> next,
  ) {
    if (map.values.toSet().length != map.length ||
        map.entries.any(
          (e) =>
              !old.contains(e.key) ||
              old.contains(e.value) ||
              !next.contains(e.value),
        )) {
      throw const OrmException(
        'MIGRATION.RENAME',
        'Rename sources must exist, targets must be new, and targets cannot overlap.',
      );
    }
  }

  validateRenames(renames.tables, oldNames, newNames);
  for (final entry in renames.tables.entries) {
    final old = sourceTables[entry.key]!, next = targetTables[entry.value]!;
    var namespace = old.namespace;
    if (old.namespace != next.namespace) {
      if (dialect != SqlDialect.postgres || next.namespace == null) {
        throw const OrmException(
          'MIGRATION.RENAME',
          'A schema move requires an explicit PostgreSQL target namespace.',
        );
      }
      renameSql.add(
        ExecuteSql(
          'ALTER TABLE ${quoted(old)} SET SCHEMA ${quoteIdentifier(next.namespace!)}',
        ),
      );
      namespace = next.namespace;
    }
    if (old.name != next.name) {
      renameSql.add(
        ExecuteSql(
          'ALTER TABLE ${quoteQualified(old.name, namespace)} RENAME TO ${quoteIdentifier(next.name)}',
        ),
      );
    }
  }
  final renamedTables = {
    for (final t in from.tables) renames.tables[t.identity] ?? t.identity: t,
  };
  for (final entry in renames.columns.entries) {
    final old = renamedTables[entry.key],
        next = to.tables.where((t) => t.identity == entry.key).firstOrNull;
    if (old == null || next == null) {
      throw const OrmException(
        'MIGRATION.RENAME',
        'Column rename references a missing table.',
      );
    }
    validateRenames(
      entry.value,
      old.columns.map((c) => c.name).toSet(),
      next.columns.map((c) => c.name).toSet(),
    );
    for (final rename in entry.value.entries) {
      renameSql.add(
        ExecuteSql(
          'ALTER TABLE ${tableSql(entry.key)} RENAME COLUMN ${quoteIdentifier(rename.key)} TO ${quoteIdentifier(rename.value)}',
        ),
      );
    }
  }
  String tableName(String name) => renames.tables[name] ?? name;
  String columnName(String table, String column) =>
      renames.columns[tableName(table)]?[column] ?? column;
  final computedRenames = from.tables
      .where(
        (t) =>
            t.columns.any((c) => c.computed != null) &&
            (renames.tables.containsKey(t.identity) ||
                (renames.columns[tableName(t.identity)]?.isNotEmpty ?? false)),
      )
      .toList();
  // CHECK SQL is deliberately not rewritten as text. Remove it before native
  // renames, then validate the explicitly declared target expressions afterward.
  final checkedRenames = from.tables
      .where(
        (t) =>
            t.checks.isNotEmpty &&
            (renames.tables.containsKey(t.identity) ||
                (renames.columns[tableName(t.identity)]?.isNotEmpty ?? false)),
      )
      .toList();
  final before = {
    for (final table in from.tables)
      tableName(table.identity): TableSchema(
        (targetTables[tableName(table.identity)] ?? table).name,
        namespace: (targetTables[tableName(table.identity)] ?? table).namespace,
        checks: checkedRenames.contains(table) ? const [] : table.checks,
        columns: [
          for (final c in table.columns)
            Column<Object?>(
              columnName(table.identity, c.name),
              c.codec,
              nullable: c.nullable,
              generated: c.generated,
              defaultSql: c.defaultSql,
              computed: c.computed,
              integerBits: c.integerBits,
              decimalPrecision: c.decimalPrecision,
              decimalScale: c.decimalScale,
              temporalPrecision: c.temporalPrecision,
            ),
        ],
        primaryKey: table.primaryKey
            .map((c) => columnName(table.identity, c))
            .toList(),
        uniqueKeys: [
          for (final key in table.uniqueKeys)
            key.map((c) => columnName(table.identity, c)).toList(),
        ],
        indexes: [
          for (final index in table.indexes)
            IndexSchema(
              index.name,
              index.columns.map((c) => columnName(table.identity, c)).toList(),
              unique: index.unique,
            ),
        ],
        foreignKeys: [
          for (final key in table.foreignKeys)
            ForeignKey(
              key.columns.map((c) => columnName(table.identity, c)).toList(),
              (targetTables[tableName(key.targetIdentity)]?.name ?? key.target),
              targetNamespace:
                  targetTables[tableName(key.targetIdentity)]?.namespace ??
                  key.targetNamespace,
              key.targetColumns
                  .map((c) => columnName(key.targetIdentity, c))
                  .toList(),
              onDelete: key.onDelete,
            ),
        ],
      ),
  };
  final after = targetTables;
  final removedTables = before.keys.toSet().difference(after.keys.toSet());
  final addedTables = after.keys.toSet().difference(before.keys.toSet());
  final shared = before.keys.toSet().intersection(after.keys.toSet());
  final dropped = <String>[...removedTables];
  for (final name in shared) {
    final next = after[name]!;
    dropped.addAll(
      before[name]!.columns
          .where((c) => !next.columns.any((n) => c.name == n.name))
          .map((c) => '$name.${c.name}'),
    );
  }
  if (dropped.isNotEmpty && !allowDestructive) {
    throw OrmException(
      'MIGRATION.DESTRUCTIVE',
      'Explicit renames or allowDestructive are required for: ${dropped.join(', ')}.',
    );
  }
  for (final name in shared) {
    final old = {for (final c in before[name]!.columns) c.name: c};
    for (final c in after[name]!.columns) {
      final prior = old[c.name];
      if (prior == null &&
          c.computed == null &&
          (c.generated || (!c.nullable && c.defaultSql == null))) {
        throw OrmException(
          'MIGRATION.BACKFILL',
          '$name.${c.name} requires an explicit backfill before becoming required.',
        );
      }
      if (prior != null && prior.generated != c.generated) {
        throw OrmException(
          'MIGRATION.IDENTITY',
          '$name.${c.name} identity changes require a manual migration.',
        );
      }
      if (dialect == SqlDialect.sqlite &&
          prior != null &&
          prior.computed == null &&
          c.computed != null &&
          !allowDestructive) {
        throw OrmException(
          'MIGRATION.DESTRUCTIVE',
          '$name.${c.name} replaces stored values with a computed expression; review and allowDestructive explicitly.',
        );
      }
      if (dialect == SqlDialect.postgres &&
          prior != null &&
          ((prior.computed == null && c.computed != null) ||
              (prior.computed != null &&
                  c.computed != null &&
                  prior.computed!.storage != c.computed!.storage) ||
              (prior.computed?.storage == ComputedStorage.virtual &&
                  c.computed == null))) {
        throw OrmException(
          'MIGRATION.COMPUTED',
          '$name.${c.name} needs a reviewed PostgreSQL replacement/materialization migration for this computed-mode change.',
        );
      }
      if (prior != null && c.computed == null && !sameStorage(prior, c)) {
        if (using[name]?[c.name] == null) {
          throw OrmException(
            'MIGRATION.CAST',
            '$name.${c.name} needs an explicit ${dialect.name} conversion expression.',
          );
        }
      }
    }
  }
  for (final table in using.entries) {
    for (final entry in table.value.entries) {
      final old = before[table.key]?.columns
          .where((c) => c.name == entry.key)
          .firstOrNull;
      final next = after[table.key]?.columns
          .where((c) => c.name == entry.key)
          .firstOrNull;
      if (old == null ||
          next == null ||
          next.computed != null ||
          sameStorage(old, next) ||
          entry.value.trim().isEmpty) {
        throw OrmException(
          'MIGRATION.CAST',
          '${table.key}.${entry.key} conversion must correspond to an actual type change.',
        );
      }
    }
  }
  final steps = <MigrationStep>[];
  for (final table in {
    ...checkedRenames,
    if (dialect == SqlDialect.sqlite) ...computedRenames,
  }) {
    if (dialect == SqlDialect.sqlite) {
      var target = withChecks(table, const []);
      if (computedRenames.contains(table)) {
        target = materializedColumns(target);
      }
      steps.add(
        RebuildTable(
          table,
          target,
          copy: {
            for (final c in table.columns) c.name: quoteIdentifier(c.name),
          },
        ),
      );
    } else {
      for (final check in table.checks) {
        steps.add(
          DropConstraint(table.name, {
            'kind': 'c',
            'name': check.name,
            'expression': check.expression(dialect),
          }, namespace: table.namespace),
        );
      }
    }
  }
  steps.addAll(renameSql);
  final addedForeignKeys = <(String, ForeignKey)>[];
  if (dialect == SqlDialect.postgres) {
    bool keysChanged(String name) {
      final a = before[name], b = after[name];
      return a == null ||
          b == null ||
          migrationHash([
                a.primaryKey,
                a.uniqueKeys,
                a.indexes.where((i) => i.unique).map(indexJson).toList(),
              ]) !=
              migrationHash([
                b.primaryKey,
                b.uniqueKeys,
                b.indexes.where((i) => i.unique).map(indexJson).toList(),
              ]);
    }

    bool typesChanged(String name) {
      final a = before[name], b = after[name];
      return a == null ||
          b == null ||
          a.columns.any(
            (c) => b.columns.any((n) => c.name == n.name && !sameStorage(c, n)),
          );
    }

    for (final old in before.values) {
      final next = after[old.identity];
      for (final key in old.foreignKeys) {
        final retained =
            next?.foreignKeys.any((k) => _sameForeignKey(k, key)) ?? false;
        if (!retained ||
            keysChanged(key.targetIdentity) ||
            typesChanged(key.targetIdentity) ||
            typesChanged(old.identity)) {
          steps.add(
            DropConstraint(old.name, {
              'kind': 'f',
              ...foreignKeyJson(key),
            }, namespace: old.namespace),
          );
          if (retained) addedForeignKeys.add((old.identity, key));
        }
      }
      if (next != null) {
        for (final key in next.foreignKeys) {
          if (!old.foreignKeys.any((k) => _sameForeignKey(k, key))) {
            addedForeignKeys.add((old.identity, key));
          }
        }
      }
    }
  }
  for (final name in removedTables) {
    steps.add(
      DropTable(before[name]!.name, namespace: before[name]!.namespace),
    );
  }
  for (final name in addedTables) {
    final table = after[name]!;
    steps.add(ExecuteSql(createTable(table, dialect)));
    for (final index in table.indexes) {
      steps.add(
        ExecuteSql(
          createIndexSql(
            after[name]!.name,
            index,
            namespace: after[name]!.namespace,
          ),
        ),
      );
    }
    if (dialect == SqlDialect.postgres) {
      addedForeignKeys.addAll(table.foreignKeys.map((k) => (name, k)));
    }
  }
  for (final name in shared) {
    var old = before[name]!;
    if (dialect == SqlDialect.sqlite &&
        computedRenames.any((t) => tableName(t.identity) == name)) {
      old = materializedColumns(old);
    }
    final next = after[name]!;
    final oldColumns = {for (final c in old.columns) c.name: c};
    final newColumns = {for (final c in next.columns) c.name: c};
    final removed = oldColumns.keys.toSet().difference(newColumns.keys.toSet());
    final added = newColumns.keys.toSet().difference(oldColumns.keys.toSet());
    final changed = oldColumns.keys
        .toSet()
        .intersection(newColumns.keys.toSet())
        .where(
          (c) =>
              migrationHash(columnJson(oldColumns[c]!)) !=
              migrationHash(columnJson(newColumns[c]!)),
        )
        .toList();
    final keysChanged =
        migrationHash([
          old.primaryKey,
          old.uniqueKeys,
          old.foreignKeys.map(foreignKeyJson).toList(),
        ]) !=
        migrationHash([
          next.primaryKey,
          next.uniqueKeys,
          next.foreignKeys.map(foreignKeyJson).toList(),
        ]);
    final checks = checkDelta(old.checks, next.checks, dialect);
    if (dialect == SqlDialect.sqlite &&
        (removed.isNotEmpty ||
            changed.isNotEmpty ||
            keysChanged ||
            checks.removed.isNotEmpty ||
            checks.added.isNotEmpty ||
            added.any((c) => !_canAddSqlite(newColumns[c]!)))) {
      steps.add(
        RebuildTable(
          old,
          next,
          copy: {
            for (final column in newColumns.keys.where(
              (c) =>
                  oldColumns.containsKey(c) && newColumns[c]!.computed == null,
            ))
              column: using[name]?[column] ?? quoteIdentifier(column),
          },
        ),
      );
      continue;
    }
    if (dialect == SqlDialect.postgres) {
      for (final check in checks.removed) {
        steps.add(
          DropConstraint(next.name, {
            'kind': 'c',
            'name': check.name,
            'expression': check.expression(dialect),
          }, namespace: next.namespace),
        );
      }
      if (migrationHash(old.primaryKey) != migrationHash(next.primaryKey) &&
          old.primaryKey.isNotEmpty) {
        steps.add(
          DropConstraint(next.name, {
            'kind': 'p',
            'columns': old.primaryKey,
          }, namespace: next.namespace),
        );
      }
      for (final key in old.uniqueKeys) {
        if (!next.uniqueKeys.any(
          (k) => migrationHash(k) == migrationHash(key),
        )) {
          steps.add(
            DropConstraint(next.name, {
              'kind': 'u',
              'columns': key,
            }, namespace: next.namespace),
          );
        }
      }
    }
    for (final index in old.indexes) {
      if (!next.indexes.any(
        (i) => migrationHash(indexJson(i)) == migrationHash(indexJson(index)),
      )) {
        steps.add(
          ExecuteSql(
            'DROP INDEX ${quoteQualified(index.name, next.namespace)}',
          ),
        );
      }
    }
    for (final column in removed) {
      steps.add(
        ExecuteSql(
          'ALTER TABLE ${tableSql(name)} DROP COLUMN ${quoteIdentifier(column)}',
        ),
      );
    }
    for (final column in added) {
      steps.add(
        ExecuteSql(
          'ALTER TABLE ${tableSql(name)} ADD COLUMN ${columnDefinition(newColumns[column]!, dialect)}',
        ),
      );
    }
    for (final column in changed) {
      final a = oldColumns[column]!, b = newColumns[column]!;
      final prefix =
          'ALTER TABLE ${tableSql(name)} ALTER COLUMN ${quoteIdentifier(column)}';
      final typeChanged = !sameStorage(a, b);
      if (a.computed != null && b.computed == null) {
        steps.add(ExecuteSql('$prefix DROP EXPRESSION'));
      }
      if (typeChanged && a.defaultSql != null) {
        steps.add(ExecuteSql('$prefix DROP DEFAULT'));
      }
      if (typeChanged) {
        steps.add(
          ExecuteSql(
            '$prefix TYPE ${columnStorageType(b, dialect)}'
            '${b.computed != null ? '' : ' USING (${using[name]![column]})'}',
          ),
        );
      }
      if (b.computed != null &&
          (a.computed?.expression(dialect) != b.computed!.expression(dialect) ||
              typeChanged)) {
        steps.add(
          ExecuteSql(
            '$prefix SET EXPRESSION AS (${coerceColumn(b.computed!.expression(dialect), b, dialect)}\n)',
          ),
        );
      }
      if (a.nullable != b.nullable) {
        steps.add(
          ExecuteSql('$prefix ${b.nullable ? 'DROP' : 'SET'} NOT NULL'),
        );
      }
      if (a.defaultSql != b.defaultSql ||
          (typeChanged && b.defaultSql != null)) {
        steps.add(
          ExecuteSql(
            '$prefix ${b.defaultSql == null ? 'DROP DEFAULT' : 'SET DEFAULT (${b.defaultSql})'}',
          ),
        );
      }
    }
    if (dialect == SqlDialect.postgres) {
      if (checks.added.isNotEmpty) {
        steps.add(
          ExecuteSql(
            'ALTER TABLE ${tableSql(name)} '
            '${checks.added.map((c) => 'ADD ${checkDefinition(c, dialect)}').join(', ')}',
          ),
        );
      }
      if (migrationHash(old.primaryKey) != migrationHash(next.primaryKey) &&
          next.primaryKey.isNotEmpty) {
        steps.add(
          ExecuteSql(
            'ALTER TABLE ${tableSql(name)} ADD PRIMARY KEY (${next.primaryKey.map(quoteIdentifier).join(', ')})',
          ),
        );
      }
      for (final key in next.uniqueKeys) {
        if (!old.uniqueKeys.any(
          (k) => migrationHash(k) == migrationHash(key),
        )) {
          steps.add(
            ExecuteSql(
              'ALTER TABLE ${tableSql(name)} ADD UNIQUE (${key.map(quoteIdentifier).join(', ')})',
            ),
          );
        }
      }
    }
    for (final index in next.indexes) {
      if (!old.indexes.any(
        (i) => migrationHash(indexJson(i)) == migrationHash(indexJson(index)),
      )) {
        steps.add(
          ExecuteSql(
            createIndexSql(
              after[name]!.name,
              index,
              namespace: after[name]!.namespace,
            ),
          ),
        );
      }
    }
  }
  for (final (name, key) in addedForeignKeys) {
    steps.add(
      ExecuteSql('ALTER TABLE ${tableSql(name)} ADD ${foreignKey(key)}'),
    );
  }
  return Migration.steps(
    id,
    steps,
    dialect: dialect,
    snapshot: to,
    previous: previous,
  );
}

bool _sameForeignKey(ForeignKey a, ForeignKey b) =>
    migrationHash(foreignKeyJson(a)) == migrationHash(foreignKeyJson(b));
bool _canAddSqlite(Column<Object?> column) => column.computed != null
    ? column.computed!.storage == ComputedStorage.virtual
    : column.defaultSql == null ||
          RegExp(
            r"^(NULL|TRUE|FALSE|[+-]?[0-9]+(\.[0-9]+)?|'([^']|'')*'|[xX]'[0-9a-fA-F]*')$",
            caseSensitive: false,
          ).hasMatch(column.defaultSql!.trim());
