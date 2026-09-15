part of '../../migrate.dart';

/// One reviewed plan for one database engine. A history cannot change engines.
final class Migration {
  final String id;
  final SqlDialect dialect;
  final List<MigrationStep> steps;
  final SchemaSnapshot? snapshot;
  final String? previous;
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

  factory Migration.create(
    String id,
    List<TableSchema> schema, {
    required SqlDialect dialect,
  }) => Migration(
    id,
    [for (final command in createSchema(schema, dialect)) command.sql],
    dialect: dialect,
    snapshot: SchemaSnapshot(schema),
  );

  factory Migration.diff(
    String id, {
    required SqlDialect dialect,
    required SchemaSnapshot from,
    required SchemaSnapshot to,
    SchemaRenames renames = const SchemaRenames(),
    String? previous,
    bool allowDestructive = false,
    Map<String, Map<String, String>> using = const {},
  }) => _diff(
    id,
    dialect: dialect,
    from: from.forDialect(dialect),
    to: to.forDialect(dialect),
    renames: renames,
    previous: previous,
    allowDestructive: allowDestructive,
    using: using,
  );

  Map<String, Object?> toJson() => {
    'format': 3,
    'id': id,
    'dialect': dialect.name,
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (previous != null) 'previous': previous,
    'steps': [for (final step in steps) step.toJson()],
  };
  late final String checksum = _hash(toJson());
}

MigrationStep _targetStep(MigrationStep step, SqlDialect dialect) =>
    switch (step) {
      RebuildTable() => RebuildTable(
        _targetTable(step.before, dialect),
        _targetTable(step.after, dialect),
        copy: step.copy,
      ),
      Backfill() => Backfill(
        _targetTable(step.table, dialect),
        set: step.set,
        where: step.where,
        doneWhen: step.doneWhen,
        batchSize: step.batchSize,
      ),
      _ => step,
    };

final class MigrationStatus {
  final String id;
  final String checksum;
  const MigrationStatus(this.id, this.checksum);
}

final class Migrator {
  final Database<Backend> database;
  final Duration lockTimeout;
  const Migrator(
    this.database, {
    this.lockTimeout = const Duration(seconds: 30),
  });

  /// Registers a verified existing database without replaying creation SQL.
  Future<SchemaVerification> baseline(
    List<Migration> migrations, {
    required SchemaSnapshot expected,
  }) async {
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
    return _migrationSession(
      database,
      lockTimeout,
      (session) => session.transaction(
        (tx) async {
          if ((await Migrator(tx).history()).isNotEmpty ||
              (await _progress(tx)).isNotEmpty) {
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
            await _recordMigration(tx, migration);
          }
          return verification;
        },
        options: database.dialect == SqlDialect.sqlite
            ? const SqliteTransaction(mode: .immediate)
            : const PostgresTransaction(),
      ),
    );
  }

  Future<List<MigrationStatus>> history() async {
    if (!await _hasMigrationTable(database, '_orm_migrations')) return [];
    final rows = await database.execute(
      SqlCommand('SELECT id, checksum FROM "_orm_migrations" ORDER BY id'),
    );
    return [
      for (final row in rows.rows)
        MigrationStatus(row[0] as String, row[1] as String),
    ];
  }

  /// Durable step checkpoints, including failed stages of partially applied migrations.
  Future<List<MigrationProgress>> progress() => _progress(database);

  Future<List<Migration>> plan(List<Migration> migrations) async {
    validateMigrations(migrations, dialect: database.dialect);
    if (!database.inSession) await _checkMigrationVersion(database);
    final applied = await history();
    _validateApplied(migrations, applied);
    _validateProgress(migrations, applied, await progress(), database.dialect);
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
        _validateProgress(migrations, applied, checkpoints, tx.dialect);
        final current = applied.length - 1;
        if (current < lower || current > upper) {
          throw OrmException(
            'MIGRATION.VERSION',
            'Expected ${migrations[lower].id} through ${migrations[upper].id}; database is ${applied.lastOrNull?.id ?? "unversioned"}.',
          );
        }
        return applied.last;
      },
      options: database.dialect == SqlDialect.postgres
          ? const PostgresTransaction(
              isolation: .repeatableRead,
              readOnly: true,
            )
          : const SqliteTransaction(),
    );
  }

  /// Applies pending migrations, returning the IDs completed by this call.
  /// Ordinary migration batches are atomic. [CheckedSql] and [Backfill] opt
  /// their containing migration into durable per-step recovery.
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
    Future<List<String>> run(Database<Backend> session) async {
      if (migrations.any(
        (m) => m.steps.any((s) => s is CheckedSql || s is Backfill),
      )) {
        return session.dialect == SqlDialect.sqlite
            ? _applyRecoverableSqlite(
                session,
                migrations,
                _BackfillBudget(maxBackfillBatches),
              )
            : _applyRecoverable(
                session,
                migrations,
                _BackfillBudget(maxBackfillBatches),
              );
      }
      return _migrationTransaction(session, (tx) async {
        await tx.execute(SqlCommand(_historyDdl));
        final pending = await Migrator(tx).plan(migrations);
        for (final migration in pending) {
          for (final step in migration.steps) {
            await _executeStep(tx, step);
          }
          await _recordMigration(tx, migration);
        }
        return [for (final migration in pending) migration.id];
      }, rebuild: _needsRebuild(migrations, session.dialect));
    }

    return _migrationSession(database, lockTimeout, run);
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

/// Validates local ordering, checksum links and operations without opening a database.
void validateMigrations(
  List<Migration> migrations, {
  required SqlDialect dialect,
}) {
  String? last;
  String? previousChecksum;
  for (final migration in migrations) {
    if (last != null && last.compareTo(migration.id) >= 0) {
      throw const OrmException(
        'MIGRATION.ORDER',
        'Migration IDs must be unique and strictly ordered.',
      );
    }
    last = migration.id;
    if (migration.previous != null && migration.previous != previousChecksum) {
      throw const OrmException(
        'MIGRATION.CHAIN',
        'Migration previous-checksum chain is broken.',
      );
    }
    previousChecksum = migration.checksum;
    if (migration.dialect != dialect) {
      throw OrmException(
        'MIGRATION.TARGET',
        '${migration.id} targets ${migration.dialect.name}, but this history requires ${dialect.name}.',
      );
    }
    for (final step in migration.steps) {
      if (step is Backfill) {
        _validateSchema([step.table], dialect);
        continue;
      }
      if (step is CheckedSql) {
        if (dialect != SqlDialect.postgres) {
          throw const OrmException(
            'MIGRATION.TARGET',
            'Recoverable autocommit migrations currently require PostgreSQL.',
          );
        }
        _validateSql(step.sql, transactional: false);
        for (final probe in [step.readyWhen, step.doneWhen]) {
          if (_sqlWords(probe).firstOrNull != 'SELECT') {
            throw const OrmException(
              'MIGRATION.PROBE',
              'Recovery conditions must be SELECT queries.',
            );
          }
        }
        continue;
      }
      if (step is DropTable) continue;
      if (step is RebuildTable) {
        if (dialect != SqlDialect.sqlite) {
          throw const OrmException(
            'MIGRATION.TARGET',
            'Table rebuilds are SQLite operations.',
          );
        }
        _validateSchema([step.before], dialect);
        _validateSchema([step.after], dialect);
        continue;
      }
      if (step is DropConstraint) {
        if (dialect != SqlDialect.postgres) {
          throw const OrmException(
            'MIGRATION.TARGET',
            'Constraint resolution is a PostgreSQL operation.',
          );
        }
        continue;
      }
      _validateSql((step as ExecuteSql).sql, transactional: true);
    }
  }
}

void _validateSql(String sql, {required bool transactional}) {
  final words = _sqlWords(sql);
  if (words.isEmpty) {
    throw const OrmException(
      'MIGRATION.EMPTY',
      'Migration contains an empty statement.',
    );
  }
  if ({
        'BEGIN',
        'COMMIT',
        'ROLLBACK',
        'END',
        'SAVEPOINT',
        'RELEASE',
        'PRAGMA',
        'START',
        'ABORT',
      }.contains(words.first) ||
      (transactional &&
          (words.first == 'VACUUM' || words.contains('CONCURRENTLY')))) {
    throw const OrmException(
      'MIGRATION.TRANSACTION',
      'Transaction control belongs to the runner; autocommit operations need CheckedSql.',
    );
  }
}

Future<void> _recordMigration(Database<Backend> db, Migration migration) => db
    .execute(
      SqlCommand(
        'INSERT INTO "_orm_migrations" (id, checksum, applied_at) VALUES (${db.dialect == SqlDialect.sqlite ? '?1, ?2, ?3' : '\$1, \$2, \$3'})',
        [
          migration.id,
          migration.checksum,
          DateTime.now().toUtc().toIso8601String(),
        ],
      ),
    )
    .then((_) {});

// Only classifies transaction control. The database remains the SQL parser.
List<String> _sqlWords(String sql) {
  final words = <String>[];
  var i = 0;
  while (i < sql.length) {
    if (sql.startsWith('--', i)) {
      final end = sql.indexOf('\n', i + 2);
      i = end < 0 ? sql.length : end + 1;
    } else if (sql.startsWith('/*', i)) {
      var depth = 1;
      i += 2;
      while (i < sql.length && depth > 0) {
        if (sql.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (sql.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
    } else if (sql[i] == "'" || sql[i] == '"') {
      final quote = sql[i++];
      while (i < sql.length) {
        if (sql[i++] == quote) {
          if (i < sql.length && sql[i] == quote) {
            i++;
          } else {
            break;
          }
        }
      }
    } else if (sql[i] == r'$') {
      final tag = RegExp(r'^\$[a-zA-Z0-9_]*\$')
          .firstMatch(sql.substring(i))
          ?.group(0);
      if (tag == null) {
        i++;
      } else {
        final end = sql.indexOf(tag, i + tag.length);
        i = end < 0 ? sql.length : end + tag.length;
      }
    } else if (RegExp(r'[a-zA-Z_]').hasMatch(sql[i])) {
      final start = i++;
      while (i < sql.length && RegExp(r'[a-zA-Z0-9_]').hasMatch(sql[i])) {
        i++;
      }
      words.add(sql.substring(start, i).toUpperCase());
    } else {
      i++;
    }
  }
  return words;
}
