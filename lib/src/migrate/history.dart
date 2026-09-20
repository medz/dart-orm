import '../../driver.dart' show Backend, SqlCommand, SqlDialect;
import '../../runtime.dart'
    show
        MariadbTransaction,
        MysqlTransaction,
        PostgresTransaction,
        SqlDatabase,
        SqliteTransaction;
import '../../values.dart' show OrmException;
import 'backfill.dart' show BackfillBudget, parameterMarker;
import 'catalog.dart' show SchemaVerification, verifySchema;
import 'execute.dart' show executeStep;
import 'migration.dart' show Migration;
import 'mysql_recovery.dart' show applyRecoverableMysql, mysqlBaseline;
import 'mysql_schema.dart' show isMysqlFamily;
import 'progress.dart' show MigrationProgress;
import 'recovery.dart'
    show
        applyRecoverable,
        applyRecoverableSqlite,
        checkMigrationVersion,
        hasMigrationTable,
        historyDdl,
        loadMigrationProgress,
        migrationSession,
        migrationTransaction,
        needsRebuild,
        validateProgress;
import 'snapshot.dart' show SchemaSnapshot;
import 'step.dart' show Backfill, CheckedSql;
import 'validation.dart' show validateMigrations;

/// The identifier and recorded fingerprint of one fully applied migration.
final class MigrationStatus {
  /// Identifier of a fully applied migration.
  final String id;

  /// Fingerprint recorded when that migration was applied or baselined.
  final String checksum;

  /// Records a completed history entry without validating a bundled definition.
  const MigrationStatus(this.id, this.checksum);
}

/// Validates and executes a fixed history against one raw SQL runtime.
///
/// The caller owns [database] and closes it after migration work finishes.
/// Applying or baselining acquires the engine's migration lock. A migrator never
/// guesses a rename or silently accepts a changed applied migration.
final class Migrator {
  /// Runtime used for migration catalog reads and writes.
  final SqlDatabase<Backend> database;

  /// Maximum wait for the database's migration lock.
  final Duration lockTimeout;

  /// Uses an existing runtime; constructing a migrator performs no database I/O.
  const Migrator(
    this.database, {
    this.lockTimeout = const Duration(seconds: 30),
  });

  /// Registers a verified existing database without replaying creation SQL.
  Future<SchemaVerification> baseline(
    List<Migration> migrations, {
    required SchemaSnapshot expected,
  }) async {
    if (isMysqlFamily(database.dialect)) {
      return mysqlBaseline(this, migrations, expected);
    }
    validateMigrations(migrations, dialect: database.dialect);
    if (database.inTransaction) {
      throw const OrmException(
        'MIGRATION.SESSION',
        'Baseline requires an outer session.',
      );
    }
    if (migrations.isEmpty ||
        migrations.last.snapshot?.checksum !=
            expected.forDialect(database.dialect).checksum) {
      throw const OrmException(
        'MIGRATION.BASELINE',
        'The final migration must carry the expected baseline snapshot.',
      );
    }
    return migrationSession(
      database,
      lockTimeout,
      (session) => session.transaction(
        (tx) async {
          if ((await Migrator(tx).history()).isNotEmpty ||
              (await loadMigrationProgress(tx)).isNotEmpty) {
            throw const OrmException(
              'MIGRATION.BASELINE',
              'Migration history already exists.',
            );
          }
          final verification = await verifySchema(tx, expected);
          if (!verification.matches) {
            throw OrmException(
              'MIGRATION.DRIFT',
              verification.differences.join('\n'),
            );
          }
          await tx.execute(
            SqlCommand(
              'CREATE TABLE IF NOT EXISTS "_orm_migrations" (id TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TEXT NOT NULL)',
            ),
          );
          for (final migration in migrations) {
            await recordMigration(tx, migration);
          }
          return verification;
        },
        options: database.dialect == SqlDialect.sqlite
            ? const SqliteTransaction(mode: .immediate)
            : const PostgresTransaction(),
      ),
    );
  }

  /// Returns completed migrations in identifier order.
  ///
  /// An absent history table produces an empty list without creating it.
  Future<List<MigrationStatus>> history() async {
    if (!await hasMigrationTable(database, '_orm_migrations')) return [];
    final rows = await database.execute(
      SqlCommand('SELECT id, checksum FROM "_orm_migrations" ORDER BY id'),
    );
    return [
      for (final row in rows.rows)
        MigrationStatus(row[0] as String, row[1] as String),
    ];
  }

  /// Durable step checkpoints, including failed stages of partially applied migrations.
  Future<List<MigrationProgress>> progress() => loadMigrationProgress(database);

  /// Validates the supplied history and returns its unapplied suffix.
  ///
  /// Reads recorded checksums and recovery checkpoints without applying DDL.
  Future<List<Migration>> plan(List<Migration> migrations) async {
    validateMigrations(migrations, dialect: database.dialect);
    if (!database.inSession) await checkMigrationVersion(database);
    final applied = await history();
    _validateApplied(migrations, applied);
    validateProgress(migrations, applied, await progress(), database.dialect);
    return migrations.skip(applied.length).toList(growable: false);
  }

  /// Checks startup compatibility in one read snapshot. Defaults to the latest
  /// bundled migration; an explicit inclusive range supports compatible releases.
  /// Does not apply migrations, verify catalog drift or lock out later upgrades.
  Future<MigrationStatus> requireVersion(
    List<Migration> migrations, {
    String? minimum,
    String? maximum,
  }) {
    migrations = List.unmodifiable(migrations);
    validateMigrations(migrations, dialect: database.dialect);
    if (migrations.isEmpty) {
      throw ArgumentError(
        'Version compatibility requires a nonempty migration history.',
      );
    }
    final upper = migrations.indexWhere(
      (m) => m.id == (maximum ?? migrations.last.id),
    );
    final lower = migrations.indexWhere(
      (m) => m.id == (minimum ?? maximum ?? migrations.last.id),
    );
    if (lower < 0 || upper < lower) {
      throw ArgumentError(
        'Minimum/maximum must name an ordered range in the bundled history.',
      );
    }
    if (database.inTransaction) {
      throw const OrmException(
        'MIGRATION.SESSION',
        'Version compatibility requires an outer session for a consistent read snapshot.',
      );
    }
    return database.transaction(
      (tx) async {
        final reader = Migrator(tx);
        final applied = await reader.history();
        if (applied.length > migrations.length) {
          throw const OrmException(
            'MIGRATION.VERSION',
            'Database is newer than the bundled migration history.',
          );
        }
        _validateApplied(migrations, applied);
        final checkpoints = await reader.progress();
        final finished = applied.map((m) => m.id).toSet();
        for (final row in checkpoints) {
          if (!finished.contains(row.id)) {
            throw OrmException(
              'MIGRATION.INCOMPLETE',
              'Migration ${row.id} has unfinished recovery work; restore a completed version before starting the application.',
            );
          }
        }
        validateProgress(migrations, applied, checkpoints, tx.dialect);
        final current = applied.length - 1;
        if (current < lower || current > upper) {
          throw OrmException(
            'MIGRATION.VERSION',
            'Expected ${migrations[lower].id} through ${migrations[upper].id}; database is ${applied.lastOrNull?.id ?? "unversioned"}.',
          );
        }
        return applied.last;
      },
      options: switch (database.dialect) {
        SqlDialect.postgres => const PostgresTransaction(
          isolation: .repeatableRead,
          readOnly: true,
        ),
        SqlDialect.mysql => const MysqlTransaction(
          isolation: .repeatableRead,
          readOnly: true,
        ),
        SqlDialect.mariadb => const MariadbTransaction(
          isolation: .repeatableRead,
          readOnly: true,
        ),
        SqlDialect.sqlite => const SqliteTransaction(),
      },
    );
  }

  /// Applies pending migrations, returning the IDs completed by this call.
  /// SQLite/PostgreSQL batches of transactional steps are atomic. [CheckedSql]
  /// and [Backfill] opt their containing migration into durable per-step
  /// recovery. MySQL/MariaDB DDL uses checked, recoverable steps because the
  /// database can commit schema changes implicitly.
  ///
  /// [maxBackfillBatches] bounds nonempty data batches across this invocation.
  /// Reaching the limit returns normally with unfinished migrations still
  /// pending; completion verification can require a subsequent call.
  Future<List<String>> apply(
    List<Migration> migrations, {
    int? maxBackfillBatches,
  }) async {
    if (maxBackfillBatches != null && maxBackfillBatches < 1) {
      throw ArgumentError.value(maxBackfillBatches, 'maxBackfillBatches');
    }
    migrations = List.unmodifiable(migrations);
    if (database.inTransaction) {
      throw const OrmException(
        'MIGRATION.SESSION',
        'Migrations require a dedicated outer transaction.',
      );
    }
    validateMigrations(migrations, dialect: database.dialect);
    Future<List<String>> run(SqlDatabase<Backend> session) async {
      if (isMysqlFamily(session.dialect)) {
        return applyRecoverableMysql(
          session,
          migrations,
          BackfillBudget(maxBackfillBatches),
        );
      }
      if (migrations.any(
        (m) => m.steps.any((s) => s is CheckedSql || s is Backfill),
      )) {
        return session.dialect == SqlDialect.sqlite
            ? applyRecoverableSqlite(
                session,
                migrations,
                BackfillBudget(maxBackfillBatches),
              )
            : applyRecoverable(
                session,
                migrations,
                BackfillBudget(maxBackfillBatches),
              );
      }
      return migrationTransaction(session, (tx) async {
        await tx.execute(SqlCommand(historyDdl));
        final pending = await Migrator(tx).plan(migrations);
        for (final migration in pending) {
          for (final step in migration.steps) {
            await executeStep(tx, step);
          }
          await recordMigration(tx, migration);
        }
        return [for (final migration in pending) migration.id];
      }, rebuild: needsRebuild(migrations, session.dialect));
    }

    return migrationSession(database, lockTimeout, run);
  }
}

void _validateApplied(
  List<Migration> migrations,
  List<MigrationStatus> applied,
) {
  if (applied.length > migrations.length) {
    throw const OrmException(
      'MIGRATION.HISTORY',
      'Local history is missing applied migrations.',
    );
  }
  for (var i = 0; i < applied.length; i++) {
    if (applied[i].id != migrations[i].id ||
        applied[i].checksum != migrations[i].checksum) {
      throw OrmException(
        'MIGRATION.CHECKSUM',
        'Applied migration ${applied[i].id} differs from local history.',
      );
    }
  }
}

Future<void> recordMigration(SqlDatabase<Backend> db, Migration migration) => db
    .execute(
      SqlCommand(
        'INSERT INTO "_orm_migrations" (id, checksum, applied_at) VALUES (${[for (var i = 1; i <= 3; i++) parameterMarker(db.dialect, i)].join(', ')})',
        [
          migration.id,
          migration.checksum,
          DateTime.now().toUtc().toIso8601String(),
        ],
      ),
    )
    .then((_) {});

// Only classifies transaction control. The database remains the SQL parser.
