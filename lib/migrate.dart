/// Reviewed schema changes and immutable migration histories written in Dart.
///
/// Build a [Migration] for one database engine, record its checksum in a
/// [MigrationHistory], then apply the validated history with [Migrator].
/// [SchemaSnapshot] stores physical schema facts without importing live models.
///
/// See the migration guide in `doc/migrations.md` for creation, review, recovery,
/// and deployment workflows.
///
/// {@category Migrations}
/// {@canonicalFor backfill.BackfillProgress}
/// {@canonicalFor catalog.CatalogObject}
/// {@canonicalFor catalog.SchemaVerification}
/// {@canonicalFor catalog.TableInfo}
/// {@canonicalFor catalog.inspectTable}
/// {@canonicalFor catalog.verifySchema}
/// {@canonicalFor checks.CheckInfo}
/// {@canonicalFor columns.ColumnInfo}
/// {@canonicalFor columns.inspectColumns}
/// {@canonicalFor columns.verifyColumns}
/// {@canonicalFor diff.SchemaRenames}
/// {@canonicalFor history.MigrationStatus}
/// {@canonicalFor history.Migrator}
/// {@canonicalFor migration.Migration}
/// {@canonicalFor progress.MigrationProgress}
/// {@canonicalFor progress.MigrationStepState}
/// {@canonicalFor schema.createSchema}
/// {@canonicalFor snapshot.SchemaSnapshot}
/// {@canonicalFor source.MigrationHistory}
/// {@canonicalFor source.migrationHistorySource}
/// {@canonicalFor source.migrationSource}
/// {@canonicalFor source.schemaSource}
/// {@canonicalFor step.Backfill}
/// {@canonicalFor step.CheckedSql}
/// {@canonicalFor step.CheckedTableSql}
/// {@canonicalFor step.DropConstraint}
/// {@canonicalFor step.DropTable}
/// {@canonicalFor step.ExecuteSql}
/// {@canonicalFor step.MigrationStep}
/// {@canonicalFor step.RebuildTable}
/// {@canonicalFor validation.validateMigrations}
library;

export 'schema_model.dart'
    show
        SqlDialect,
        TableSchema,
        Column,
        Codec,
        Codecs,
        ComputedColumn,
        ComputedStorage,
        CheckSchema,
        ForeignKey,
        IndexSchema,
        OrmException;
export 'src/migrate/backfill.dart' show BackfillProgress;
export 'src/migrate/catalog.dart'
    show
        CatalogObject,
        SchemaVerification,
        TableInfo,
        inspectTable,
        verifySchema;
export 'src/migrate/checks.dart' show CheckInfo;
export 'src/migrate/columns.dart'
    show ColumnInfo, inspectColumns, verifyColumns;
export 'src/migrate/diff.dart' show SchemaRenames;
export 'src/migrate/history.dart' show MigrationStatus, Migrator;
export 'src/migrate/migration.dart' show Migration;
export 'src/migrate/progress.dart' show MigrationProgress, MigrationStepState;
export 'src/migrate/schema.dart' show createSchema;
export 'src/migrate/snapshot.dart' show SchemaSnapshot;
export 'src/migrate/source.dart'
    show
        MigrationHistory,
        migrationHistorySource,
        migrationSource,
        schemaSource;
export 'src/migrate/step.dart'
    show
        Backfill,
        CheckedSql,
        CheckedTableSql,
        DropConstraint,
        DropTable,
        ExecuteSql,
        MigrationStep,
        RebuildTable;
export 'src/migrate/validation.dart' show validateMigrations;
