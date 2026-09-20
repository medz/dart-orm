// Immutable, engine-specific migration plans and schema differences.

import '../../driver.dart' show SqlDialect;
import '../../schema_model.dart' show TableSchema;
import 'diff.dart' show SchemaRenames, diffSchema;
import 'mysql_schema.dart' show isMysqlFamily, mysqlCreateSteps;
import 'schema.dart' show createSchema;
import 'snapshot.dart' show SchemaSnapshot, targetTable;
import 'sql_utils.dart' show migrationHash;
import 'step.dart'
    show Backfill, CheckedTableSql, ExecuteSql, MigrationStep, RebuildTable;

/// One reviewed plan for one database engine. A history cannot change engines.
final class Migration {
  /// Ordered identifier, such as `0001_create_users`.
  final String id;

  /// The only database engine on which this plan can run.
  final SqlDialect dialect;

  /// Immutable operations, executed in their reviewed order.
  final List<MigrationStep> steps;

  /// Physical schema expected after all steps complete, when recorded.
  final SchemaSnapshot? snapshot;

  /// Checksum of the immediately preceding migration, when recorded.
  final String? previous;

  /// Builds a plan from transactional SQL statements.
  ///
  /// Use [Migration.steps] for rebuilds, checked DDL, or bounded backfills.
  Migration(
    String id,
    List<String> statements, {
    required SqlDialect dialect,
    SchemaSnapshot? snapshot,
    String? previous,
  }) : this.steps(
         id,
         statements.map(ExecuteSql.new).toList(),
         dialect: dialect,
         snapshot: snapshot,
         previous: previous,
       );

  /// Builds a plan with explicit operations and freezes its engine-specific schema.
  Migration.steps(
    this.id,
    List<MigrationStep> steps, {
    required this.dialect,
    SchemaSnapshot? snapshot,
    this.previous,
  }) : steps = List.unmodifiable(steps.map((s) => _targetStep(s, dialect))),
       snapshot = snapshot?.forDialect(dialect) {
    if (!RegExp(r'^[0-9]+_[a-z][a-z0-9_]*$').hasMatch(id)) {
      throw ArgumentError(
        'Migration IDs use a numeric prefix and lowercase name.',
      );
    }
  }

  /// Plans creation of a new schema for [dialect], without database access.
  factory Migration.create(
    String id,
    List<TableSchema> schema, {
    required SqlDialect dialect,
  }) => Migration.steps(
    id,
    isMysqlFamily(dialect)
        ? mysqlCreateSteps(schema, dialect)
        : [
            for (final command in createSchema(schema, dialect))
              ExecuteSql(command.sql),
          ],
    dialect: dialect,
    snapshot: SchemaSnapshot(schema),
  );

  /// Plans the transition from [from] to [to], without applying any changes.
  ///
  /// Renames must be explicit in [renames]. Potential data loss requires
  /// [allowDestructive]; [using] supplies reviewed conversion SQL by table and
  /// column. Review the returned steps before adding the plan to a history.
  factory Migration.diff(
    String id, {
    required SqlDialect dialect,
    required SchemaSnapshot from,
    required SchemaSnapshot to,
    SchemaRenames renames = const SchemaRenames(),
    String? previous,
    bool allowDestructive = false,
    Map<String, Map<String, String>> using = const {},
  }) => diffSchema(
    id,
    dialect: dialect,
    from: from.forDialect(dialect),
    to: to.forDialect(dialect),
    renames: renames,
    previous: previous,
    allowDestructive: allowDestructive,
    using: using,
  );

  /// Canonical operation data used for reporting and checksum calculation.
  ///
  /// Saved migration files remain Dart source; this is not a persistence format.
  Map<String, Object?> toJson() => {
    'format': 3,
    'id': id,
    'dialect': dialect.name,
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (previous != null) 'previous': previous,
    'steps': [for (final step in steps) step.toJson()],
  };

  /// Stable fingerprint of SQL, operations, schema, engine, and prior checksum.
  late final String checksum = migrationHash(toJson());
}

MigrationStep _targetStep(MigrationStep step, SqlDialect dialect) =>
    switch (step) {
      CheckedTableSql() => CheckedTableSql(
        step.sql,
        before: step.before == null ? null : targetTable(step.before!, dialect),
        after: step.after == null ? null : targetTable(step.after!, dialect),
      ),
      RebuildTable() => RebuildTable(
        targetTable(step.before, dialect),
        targetTable(step.after, dialect),
        copy: step.copy,
      ),
      Backfill() => Backfill(
        targetTable(step.table, dialect),
        set: step.set,
        where: step.where,
        doneWhen: step.doneWhen,
        batchSize: step.batchSize,
      ),
      _ => step,
    };
