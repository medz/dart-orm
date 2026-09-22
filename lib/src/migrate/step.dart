// Reviewed operation definitions. All subtypes stay with the sealed base.

import '../../schema_model.dart' show IndexSchema, TableSchema;
import '../../values.dart' show OrmException;
import 'schema.dart' show createIndexSql;
import 'snapshot.dart' show SchemaSnapshot, tableJson;
import 'sql_utils.dart' show freezeMigrationValue, postgresLiteral;
import 'validation.dart' show sqlWords;

/// An explicit operation in a reviewed migration.
sealed class MigrationStep {
  const MigrationStep();

  /// Stable operation data used in migration checksums and reports.
  Map<String, Object?> toJson();
}

/// One trusted SQL statement executed by the migration's transaction runner.
final class ExecuteSql(
  /// Trusted SQL statement whose exact text participates in the checksum.
  final String sql,
) extends MigrationStep {
  /// Prepares one statement for transactional migration execution.
  this;

  @override
  Map<String, Object?> toJson() => {'kind': 'sql', 'sql': sql};
}

/// A reviewed table removal. The SQLite runner checks foreign keys before commit.
final class DropTable(
  /// Physical table name to remove; the runner quotes it as an identifier.
  final String table, {

  /// PostgreSQL schema containing the table; null preserves historical scope.
  final String? namespace,
}) extends MigrationStep {
  /// Records a reviewed table removal without executing it.
  this;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'dropTable',
    'table': table,
    if (namespace != null) 'namespace': namespace,
  };
}

/// SQLite's copy-and-replace operation. Expressions are trusted migration SQL.
/// Both snapshots are after any explicit table/column renames.
final class RebuildTable extends MigrationStep {
  /// Reviewed table shape before copying rows.
  final TableSchema before;

  /// Reviewed replacement shape after copying rows.
  final TableSchema after;

  /// Target column names mapped to trusted SQL expressions over the old row.
  final Map<String, String> copy;

  /// Freezes an explicit copy map between two shapes of the same SQLite table.
  ///
  /// The map must be nonempty and may target only existing, noncomputed columns.
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
    'before': tableJson(before),
    'after': tableJson(after),
    'copy': copy,
  };
}

/// Resolves the actual PostgreSQL name by a constraint signature. This also
/// works for baselined databases whose constraint names were chosen elsewhere.
final class DropConstraint extends MigrationStep {
  /// Physical PostgreSQL table whose matching constraint will be removed.
  final String table;

  /// PostgreSQL schema containing the table; null preserves historical scope.
  final String? namespace;

  /// Immutable constraint signature used to find its actual catalog name.
  final Map<String, Object?> constraint;

  /// Freezes a reviewed signature; execution requires exactly one catalog match.
  DropConstraint(this.table, Map<String, Object?> constraint, {this.namespace})
    : constraint = freezeMigrationValue(constraint) as Map<String, Object?>;
  @override
  Map<String, Object?> toJson() => {
    'kind': 'dropConstraint',
    'table': table,
    if (namespace != null) 'namespace': namespace,
    'constraint': constraint,
  };
}

/// PostgreSQL autocommit SQL with explicit recovery conditions. Both checks must
/// return exactly one boolean. They describe durable state, not an object name alone.
final class CheckedSql extends MigrationStep {
  /// Trusted PostgreSQL statement executed outside a transaction.
  final String sql;

  /// SELECT returning one boolean that confirms execution is safe to start.
  final String readyWhen;

  /// SELECT returning one boolean that confirms the durable result.
  final String doneWhen;

  /// Pairs autocommit SQL with explicit readiness and completion probes.
  const CheckedSql(this.sql, {required this.readyWhen, required this.doneWhen});

  /// A concurrent, ascending B-tree index with default collation/opclasses.
  /// The completion check compares its definition as well as ready/valid state.
  factory CheckedSql.createIndex(
    String table,
    IndexSchema index, {
    String? namespace,
  }) {
    if (index.columns.isEmpty) throw ArgumentError('An index needs columns.');
    final source = postgresLiteral(table), name = postgresLiteral(index.name);
    final scope = namespace == null
        ? 'current_schema()'
        : postgresLiteral(namespace);
    final columns =
        'ARRAY[${index.columns.map(postgresLiteral).join(', ')}]::text[]';
    return CheckedSql(
      createIndexSql(
        table,
        index,
        namespace: namespace,
      ).replaceFirst('INDEX ', 'INDEX CONCURRENTLY '),
      readyWhen: '''SELECT NOT EXISTS (
SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = $scope AND c.relname = $name)''',
      doneWhen:
          '''SELECT EXISTS (
SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_am am ON am.oid = c.relam
WHERE n.nspname = $scope AND c.relname = $name AND t.relname = $source
AND t.relnamespace = n.oid AND i.indisvalid AND i.indisready AND i.indislive
AND i.indisunique = ${index.unique} AND NOT i.indisprimary AND NOT i.indisexclusion
AND i.indexprs IS NULL AND i.indpred IS NULL AND i.indnatts = i.indnkeyatts
AND am.amname = 'btree' AND c.reloptions IS NULL
AND NOT EXISTS (SELECT 1 FROM pg_constraint constraint_row WHERE constraint_row.conindid = i.indexrelid AND constraint_row.contype IN ('p', 'u', 'x'))
AND NOT coalesce((to_jsonb(i)->>'indnullsnotdistinct')::boolean, false)
AND NOT EXISTS (SELECT 1 FROM unnest(i.indoption) v WHERE v <> 0)
AND NOT EXISTS (SELECT 1 FROM unnest(i.indclass) v JOIN pg_opclass o ON o.oid = v WHERE NOT o.opcdefault)
AND NOT EXISTS (SELECT 1 FROM unnest(i.indkey, i.indcollation) k(num, collation_oid)
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.num WHERE k.collation_oid <> a.attcollation)
AND ARRAY(SELECT a.attname::text FROM unnest(i.indkey) WITH ORDINALITY k(num, ord)
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.num ORDER BY k.ord) = $columns)''',
    );
  }
  @override
  Map<String, Object?> toJson() => {
    'kind': 'checkedSql',
    'sql': sql,
    'readyWhen': readyWhen,
    'doneWhen': doneWhen,
  };
}

/// One reviewed MySQL/MariaDB DDL statement and its complete physical table
/// pre/postconditions. DDL is autocommit; each successful step is checkpointed.
/// A null before means create, a null after means drop, differing names rename.
final class CheckedTableSql extends MigrationStep {
  /// One trusted MySQL/MariaDB DDL statement executed with recovery checkpoints.
  final String sql;

  /// Reviewed states before and after DDL; null denotes absence on that side.
  ///
  /// Null [before] describes creation, null [after] describes removal, and
  /// different names describe a rename. At least one state must be present.
  final TableSchema? before, after;

  /// Records DDL with table-state conditions instead of assuming DDL is atomic.
  CheckedTableSql(this.sql, {this.before, this.after}) {
    if (before == null && after == null) {
      throw ArgumentError(
        'A checked table step needs a before or after schema.',
      );
    }
  }
  @override
  Map<String, Object?> toJson() => {
    'kind': 'checkedTableSql',
    'sql': sql,
    if (before != null) 'before': tableJson(before!),
    if (after != null) 'after': tableJson(after!),
  };
}

/// A reviewed, bounded update using this migration's historical table definition.
/// Expressions and completion SQL are trusted migration code. Primary keys must
/// remain immutable, including in application writes and triggers.
final class Backfill extends MigrationStep {
  /// Frozen physical table definition from this migration.
  final TableSchema table;

  /// Non-key target columns mapped to trusted SQL expressions.
  final Map<String, String> set;

  /// Trusted SQL predicate selecting rows that still need an update.
  final String where;

  /// SELECT returning one boolean to verify completion after scanning.
  final String doneWhen;

  /// Maximum rows updated in each committed batch.
  final int batchSize;

  /// Prepares bounded updates over an immutable, non-null historical primary key.
  ///
  /// Assignments must be nonempty, target writable non-key columns, and use
  /// trusted SQL. [batchSize] must be positive; [doneWhen] must be a SELECT probe.
  Backfill(
    this.table, {
    required Map<String, String> set,
    this.where = 'TRUE',
    required this.doneWhen,
    this.batchSize = 1000,
  }) : set = Map.unmodifiable(set) {
    SchemaSnapshot([table]);
    if (batchSize < 1 ||
        set.isEmpty ||
        where.trim().isEmpty ||
        set.entries.any(
          (e) =>
              e.value.trim().isEmpty ||
              !table.columns.any(
                (c) => c.name == e.key && !c.generated && c.computed == null,
              ) ||
              table.primaryKey.contains(e.key),
        )) {
      throw ArgumentError(
        'Backfill needs a positive batch size and assignments to existing non-key columns.',
      );
    }
    if (table.primaryKey.isEmpty ||
        table.columns
            .where((c) => table.primaryKey.contains(c.name))
            .any((c) => c.nullable || c.codec.sqlType == 'json')) {
      throw const OrmException(
        'MIGRATION.BACKFILL_KEY',
        'Backfill requires a non-null primary key with lossless cursor storage; JSON keys are unsupported.',
      );
    }
    if (sqlWords(doneWhen).firstOrNull != 'SELECT') {
      throw const OrmException(
        'MIGRATION.PROBE',
        'Backfill completion must be a SELECT returning one boolean.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'backfill',
    'table': tableJson(table),
    'set': set,
    'where': where,
    'doneWhen': doneWhen,
    'batchSize': batchSize,
  };
}
