part of '../../migrate.dart';

/// An explicit operation in a reviewed migration.
sealed class MigrationStep {
  const MigrationStep();
  Map<String, Object?> toJson();
}

final class ExecuteSql(final String sql) extends MigrationStep {
  @override
  Map<String, Object?> toJson() => {'kind': 'sql', 'sql': sql};
}

/// A reviewed table removal. The SQLite runner checks foreign keys before commit.
final class DropTable(final String table) extends MigrationStep {
  @override
  Map<String, Object?> toJson() => {'kind': 'dropTable', 'table': table};
}

/// SQLite's copy-and-replace operation. Expressions are trusted migration SQL.
/// Both snapshots are after any explicit table/column renames.
final class RebuildTable extends MigrationStep {
  final TableSchema before;
  final TableSchema after;
  final Map<String, String> copy;
  RebuildTable(this.before, this.after, {required Map<String, String> copy})
    : copy = Map.unmodifiable(copy) {
    if (before.name != after.name ||
        copy.isEmpty ||
        copy.keys.any(
          (key) =>
              !after.columns.any((c) => c.name == key && c.computed == null),
        )) {
      throw const OrmException(
        'MIGRATION.REBUILD',
        'Rebuild requires the same table name and an explicit target-column copy map.',
      );
    }
  }
  @override
  Map<String, Object?> toJson() => {
    'kind': 'rebuild',
    'before': _tableJson(before),
    'after': _tableJson(after),
    'copy': copy,
  };
}

/// Resolves the actual PostgreSQL name by a constraint signature. This also
/// works for baselined databases whose constraint names were chosen elsewhere.
final class DropConstraint extends MigrationStep {
  final String table;
  final Map<String, Object?> constraint;
  DropConstraint(this.table, Map<String, Object?> constraint)
    : constraint = _freezeJson(constraint) as Map<String, Object?>;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'dropConstraint',
    'table': table,
    'constraint': constraint,
  };
}

Future<void> _executeStep(Database<Backend> db, MigrationStep step) async {
  switch (step) {
    case CheckedSql() || Backfill():
      throw const OrmException(
        'MIGRATION.TRANSACTION',
        'This step requires the recovery runner.',
      );
    case ExecuteSql():
      await db.execute(SqlCommand(step.sql));
    case DropTable():
      await db.execute(SqlCommand('DROP TABLE ${_quote(step.table)}'));
    case RebuildTable():
      await _rebuild(db, step);
    case DropConstraint():
      if (step.constraint['kind'] == 'c') {
        await _dropCheck(db, step.table, _readCheck(step.constraint));
        return;
      }
      final rows = await db.execute(
        SqlCommand(
          r'''
SELECT c.conname, c.contype::text,
 ARRAY(SELECT a.attname::text FROM unnest(c.conkey) WITH ORDINALITY k(num, ord)
 JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.num ORDER BY k.ord),
 t.relname,
 ARRAY(SELECT a.attname::text FROM unnest(c.confkey) WITH ORDINALITY k(num, ord)
 JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.num ORDER BY k.ord),
 c.confdeltype::text
FROM pg_constraint c JOIN pg_class r ON r.oid = c.conrelid
JOIN pg_namespace n ON n.oid = r.relnamespace
LEFT JOIN pg_class t ON t.oid = c.confrelid
WHERE n.nspname = current_schema() AND r.relname = $1''',
          [step.table],
        ),
      );
      final matches = rows.rows
          .where(
            (row) =>
                _hash({
                  'kind': row[1],
                  'columns': row[2],
                  if (row[1] == 'f') ...{
                    'target': row[3],
                    'targetColumns': row[4],
                    'onDelete': switch (row[5]) {
                      'a' => 'NO ACTION',
                      'r' => 'RESTRICT',
                      'c' => 'CASCADE',
                      'n' => 'SET NULL',
                      'd' => 'SET DEFAULT',
                      _ => '',
                    },
                  },
                }) ==
                _hash(step.constraint),
          )
          .toList();
      if (matches.length != 1) {
        throw OrmException(
          'MIGRATION.DRIFT',
          'Expected exactly one matching constraint on ${step.table}; found ${matches.length}.',
        );
      }
      await db.execute(
        SqlCommand(
          'ALTER TABLE ${_quote(step.table)} DROP CONSTRAINT ${_quote(matches.single.first as String)}',
        ),
      );
  }
}

Future<void> _rebuild(Database<Backend> db, RebuildTable step) async {
  final before = step.before, after = step.after, name = after.name;
  final actual = await inspectTable(db, name);
  final checkMatches = await _matchChecks(
    db,
    name,
    before.checks,
    actual.checks,
  );
  if (actual.checks.length > checkMatches.whereType<int>().length) {
    throw OrmException(
      'MIGRATION.UNMANAGED',
      '$name has undeclared CHECK constraints.',
    );
  }
  final unsupported = actual.unmanaged
      .where((o) => !{'index', 'trigger', 'view'}.contains(o.kind))
      .toList();
  if (unsupported.isNotEmpty ||
      actual.columns.any((c) => c.generated && c.computed == null)) {
    throw OrmException(
      'MIGRATION.UNMANAGED',
      '$name has unmodeled table constraints/options; provide a manual migration to preserve them.',
    );
  }
  final check = await verifySchema(db, SchemaSnapshot([before]));
  final differences = check.differences
      .where((d) => d != '$name indexes differs')
      .toList();
  for (final index in before.indexes) {
    if (!actual.indexes.any(
      (i) => _hash(_indexJson(i)) == _hash(_indexJson(index)),
    )) {
      differences.add('$name.${index.name} index differs');
    }
  }
  if (differences.isNotEmpty) {
    throw OrmException('MIGRATION.DRIFT', differences.join('\n'));
  }
  final removed = before.columns
      .map((c) => c.name)
      .toSet()
      .difference(after.columns.map((c) => c.name).toSet());
  if (removed.isNotEmpty && actual.unmanaged.any((o) => o.kind == 'trigger')) {
    throw OrmException(
      'MIGRATION.UNMANAGED',
      '$name has triggers and removed columns; update them in a manual migration.',
    );
  }
  final objects = await db.execute(
    SqlCommand(
      "SELECT type, name, sql FROM sqlite_schema WHERE tbl_name = ?1 AND type IN ('index', 'trigger') AND sql IS NOT NULL ORDER BY type, name",
      [name],
    ),
  );
  final managedIndexes = before.indexes.map((i) => i.name).toSet();
  final targetIndexes = after.indexes.map((i) => i.name).toSet();
  for (final row in objects.rows) {
    if (row[0] == 'index' &&
        !managedIndexes.contains(row[1]) &&
        targetIndexes.contains(row[1])) {
      throw OrmException(
        'MIGRATION.UNMANAGED',
        'New index ${row[1]} conflicts with an unmanaged index.',
      );
    }
  }
  final temporary = '_orm_rebuild_$name';
  await db.execute(
    SqlCommand(_createTable(after, SqlDialect.sqlite, name: temporary)),
  );
  await db.execute(
    SqlCommand(
      'INSERT INTO ${_quote(temporary)} (${step.copy.keys.map(_quote).join(', ')}) '
      'SELECT ${step.copy.entries.map((e) => _coerceColumn(e.value, after.columns.firstWhere((c) => c.name == e.key), db.dialect)).join(', ')} FROM ${_quote(name)}',
    ),
  );
  await db.execute(SqlCommand('DROP TABLE ${_quote(name)}'));
  // Views remain present while their source is temporarily absent. Legacy mode
  // prevents SQLite from reparsing those views during this one rename.
  final legacy = (await db.execute(SqlCommand('PRAGMA legacy_alter_table')))
      .rows
      .single
      .single;
  try {
    await db.execute(SqlCommand('PRAGMA legacy_alter_table = ON'));
    await db.execute(
      SqlCommand('ALTER TABLE ${_quote(temporary)} RENAME TO ${_quote(name)}'),
    );
  } finally {
    await db.execute(
      SqlCommand('PRAGMA legacy_alter_table = ${legacy == 1 ? 'ON' : 'OFF'}'),
    );
  }
  for (final index in after.indexes) {
    await db.execute(SqlCommand(_createIndex(name, index)));
  }
  for (final row in objects.rows) {
    if (row[0] == 'index' && managedIndexes.contains(row[1])) continue;
    await db.execute(SqlCommand(row[2] as String));
  }
  for (final view in actual.unmanaged.where((o) => o.kind == 'view')) {
    await db.execute(SqlCommand('SELECT * FROM ${_quote(view.name)} LIMIT 0'));
  }
}
