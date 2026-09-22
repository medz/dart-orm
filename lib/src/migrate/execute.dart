// Transactional execution of reviewed SQL and SQLite table rebuilds.

import '../../driver.dart' show Backend, SqlCommand, SqlDialect;
import '../../runtime.dart' show SqlDatabase;
import '../../schema_model.dart' show CheckSchema;
import '../../values.dart' show OrmException;
import 'catalog.dart' show inspectTable, verifySchema;
import 'checks.dart' show dropCheck, matchChecks;
import 'schema.dart' show coerceColumn, createIndexSql, createTable;
import 'snapshot.dart' show SchemaSnapshot, indexJson;
import 'sql_utils.dart' show migrationHash, quoteIdentifier, quoteQualified;
import 'step.dart'
    show
        Backfill,
        CheckedSql,
        CheckedTableSql,
        DropConstraint,
        DropTable,
        ExecuteSql,
        MigrationStep,
        RebuildTable;

Future<void> executeStep(SqlDatabase<Backend> db, MigrationStep step) async {
  switch (step) {
    case CheckedSql() || CheckedTableSql() || Backfill():
      throw const OrmException(
        'MIGRATION.TRANSACTION',
        'This step requires the recovery runner.',
      );
    case ExecuteSql():
      await db.execute(SqlCommand(step.sql));
    case DropTable():
      await db.execute(
        SqlCommand('DROP TABLE ${quoteQualified(step.table, step.namespace)}'),
      );
    case RebuildTable():
      await _rebuild(db, step);
    case DropConstraint():
      if (step.constraint['kind'] == 'c') {
        await dropCheck(
          db,
          step.table,
          CheckSchema(
            step.constraint['name'] as String?,
            step.constraint['expression'] as String,
          ),
          namespace: step.namespace,
        );
        return;
      }
      final rows = await db.execute(
        SqlCommand(
          r'''
SELECT c.conname, c.contype::text,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY k(num, ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.num ORDER BY k.ord),
 t.relname,
 ARRAY(SELECT a.attname::text FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY k(num, ord)
 JOIN pg_catalog.pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.num ORDER BY k.ord),
 c.confdeltype::text, tn.nspname
FROM pg_catalog.pg_constraint c JOIN pg_catalog.pg_class r ON r.oid = c.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid = r.relnamespace
LEFT JOIN pg_catalog.pg_class t ON t.oid = c.confrelid
LEFT JOIN pg_catalog.pg_namespace tn ON tn.oid = t.relnamespace
WHERE n.nspname = coalesce($2::text, pg_catalog.current_schema()) AND r.relname = $1''',
          [step.table, step.namespace],
        ),
      );
      final matches = rows.rows
          .where(
            (row) =>
                migrationHash({
                  'kind': row[1],
                  'columns': row[2],
                  if (row[1] == 'f') ...{
                    'target': row[3],
                    if (step.constraint.containsKey('targetNamespace'))
                      'targetNamespace': row[6],
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
                migrationHash(step.constraint),
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
          'ALTER TABLE ${quoteQualified(step.table, step.namespace)} DROP CONSTRAINT ${quoteIdentifier(matches.single.first as String)}',
        ),
      );
  }
}

Future<void> _rebuild(SqlDatabase<Backend> db, RebuildTable step) async {
  final before = step.before, after = step.after, name = after.name;
  final actual = await inspectTable(db, name);
  final checkMatches = await matchChecks(
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
      (i) => migrationHash(indexJson(i)) == migrationHash(indexJson(index)),
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
    SqlCommand(createTable(after, SqlDialect.sqlite, name: temporary)),
  );
  await db.execute(
    SqlCommand(
      'INSERT INTO ${quoteIdentifier(temporary)} (${step.copy.keys.map(quoteIdentifier).join(', ')}) '
      'SELECT ${step.copy.entries.map((e) => coerceColumn(e.value, after.columns.firstWhere((c) => c.name == e.key), db.dialect)).join(', ')} FROM ${quoteIdentifier(name)}',
    ),
  );
  await db.execute(SqlCommand('DROP TABLE ${quoteIdentifier(name)}'));
  // Views remain present while their source is temporarily absent. Legacy mode
  // prevents SQLite from reparsing those views during this one rename.
  final legacy = (await db.execute(SqlCommand('PRAGMA legacy_alter_table')))
      .rows
      .single
      .single;
  try {
    await db.execute(SqlCommand('PRAGMA legacy_alter_table = ON'));
    await db.execute(
      SqlCommand(
        'ALTER TABLE ${quoteIdentifier(temporary)} RENAME TO ${quoteIdentifier(name)}',
      ),
    );
  } finally {
    await db.execute(
      SqlCommand('PRAGMA legacy_alter_table = ${legacy == 1 ? 'ON' : 'OFF'}'),
    );
  }
  for (final index in after.indexes) {
    await db.execute(SqlCommand(createIndexSql(name, index)));
  }
  for (final row in objects.rows) {
    if (row[0] == 'index' && managedIndexes.contains(row[1])) continue;
    await db.execute(SqlCommand(row[2] as String));
  }
  for (final view in actual.unmanaged.where((o) => o.kind == 'view')) {
    await db.execute(
      SqlCommand('SELECT * FROM ${quoteIdentifier(view.name)} LIMIT 0'),
    );
  }
}
