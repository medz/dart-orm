part of '../../migrate.dart';

/// One reviewed MySQL/MariaDB DDL statement and its complete physical table
/// pre/postconditions. DDL is autocommit; each successful step is checkpointed.
/// A null before means create, a null after means drop, differing names rename.
final class CheckedTableSql extends MigrationStep {
  final String sql;
  final TableSchema? before, after;
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
    if (before != null) 'before': _tableJson(before!),
    if (after != null) 'after': _tableJson(after!),
  };
}

Future<bool> _mysqlExists(SqlDatabase<Backend> db, String table) async =>
    (await db.execute(
      SqlCommand(
        'SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=?',
        [table],
      ),
    )).rows.isNotEmpty;

Future<bool> _mysqlStateMatches(
  SqlDatabase<Backend> db,
  TableSchema? present,
  TableSchema? other,
) async {
  if (present == null) return !await _mysqlExists(db, other!.name);
  if (!await _mysqlExists(db, present.name)) return false;
  if (other != null &&
      other.name != present.name &&
      await _mysqlExists(db, other.name)) {
    return false;
  }
  final verified = await _mysqlVerifySchema(db, SchemaSnapshot([present]));
  return verified.matches && verified.unmanaged.isEmpty;
}

Future<R> _mysqlMigrationLock<R>(
  SqlDatabase<Backend> session,
  Duration timeout,
  Future<R> Function() action,
) async {
  final name =
      (await session.execute(SqlCommand('SELECT DATABASE()')))
              .rows
              .single
              .single
          as String?;
  if (name == null) {
    throw const OrmException(
      'MIGRATION.SCHEMA',
      'Select a MySQL/MariaDB database before migrating.',
    );
  }
  final key = 'orm_migrate_${_hash(name).substring(0, 48)}';
  Object? primaryFailure;
  try {
    final locked = (await session.execute(
      SqlCommand('SELECT GET_LOCK(?, ?)', [
        key,
        timeout.inMicroseconds / 1000000,
      ]),
    )).rows.single.single;
    if (locked != 1) {
      throw const OrmException(
        'MIGRATION.LOCK',
        'Could not acquire the database migration lock.',
      );
    }
  } catch (_) {
    // A timed out transport can have acquired the server-side lock; discard it.
    await session.discard();
    rethrow;
  }
  try {
    return await action();
  } catch (error) {
    primaryFailure = error;
    rethrow;
  } finally {
    try {
      if ((await session.execute(SqlCommand('SELECT RELEASE_LOCK(?)', [key])))
              .rows
              .single
              .single !=
          1) {
        throw const OrmException(
          'MIGRATION.LOCK',
          'Migration lock release could not be confirmed.',
        );
      }
    } catch (_) {
      try {
        await session.discard();
      } catch (_) {}
      if (primaryFailure == null) rethrow;
    }
  }
}

Future<List<String>> _applyRecoverableMysql(
  SqlDatabase<Backend> session,
  List<Migration> migrations,
  _BackfillBudget budget,
) async {
  final pending = await Migrator(session).plan(migrations);
  if (pending.isEmpty) return [];
  await _mysqlRecoveryTables(session);
  final progress = {
    for (final value in await _progress(session)) (value.id, value.step): value,
  };
  final completed = <String>[];
  for (final migration in pending) {
    for (var i = 0; i < migration.steps.length; i++) {
      if (progress[(migration.id, i)]?.state == .complete) continue;
      final step = migration.steps[i];
      var phase = 'inspect';
      try {
        await _checkpoint(session, migration, i, .running, phase);
        if (step is CheckedTableSql) {
          final done = await _mysqlStateMatches(
            session,
            step.after,
            step.before,
          );
          if (!done) {
            if (!await _mysqlStateMatches(session, step.before, step.after)) {
              throw const OrmException(
                'MIGRATION.RECOVERY',
                'The table matches neither reviewed precondition nor postcondition. Repair drift before retrying this unchanged step.',
              );
            }
            phase = 'execute';
            await _checkpoint(session, migration, i, .running, phase);
            await session.execute(SqlCommand(step.sql));
            phase = 'verify';
            if (!await _mysqlStateMatches(session, step.after, step.before)) {
              throw const OrmException(
                'MIGRATION.POSTCONDITION',
                'DDL did not establish its reviewed physical table definition.',
              );
            }
          }
          phase = 'record';
          await _checkpoint(session, migration, i, .complete, 'complete');
        } else if (step is Backfill) {
          await _verifyBackfill(session, step);
          while (!await session.transaction(
            (tx) async => _backfillChunk(
              tx,
              migration,
              i,
              step,
              await _savedBackfill(tx, migration.id, i),
              budget,
              (value) => phase = value,
            ),
          )) {}
        } else {
          // validateMigrations accepts only DML ExecuteSql here. The write and
          // its checkpoint share the same InnoDB transaction.
          phase = 'execute';
          await session.transaction((tx) async {
            await _executeStep(tx, step);
            await _checkpoint(tx, migration, i, .complete, 'complete');
          });
        }
      } catch (error, stack) {
        if (error is _BackfillPaused) return completed;
        try {
          await _checkpoint(
            session,
            migration,
            i,
            .failed,
            phase,
            failure: error is OrmException
                ? error.code
                : error.runtimeType.toString(),
          );
        } catch (_) {} // Keep a prior running/completed checkpoint intact.
        Error.throwWithStackTrace(
          OrmException(
            'MIGRATION.STEP',
            '${migration.id} step $i failed during $phase. Inspect progress and retry the unchanged history.',
            cause: error,
          ),
          stack,
        );
      }
    }
    if (migration.snapshot != null) {
      final verified = await _mysqlVerifySchema(session, migration.snapshot!);
      if (!verified.matches || verified.unmanaged.isNotEmpty) {
        throw OrmException(
          'MIGRATION.DRIFT',
          'Final schema does not match ${migration.id}: ${verified.differences.join(', ')}; unmanaged=${verified.unmanaged.map((o) => o.name).join(', ')}.',
        );
      }
    }
    await session.transaction((tx) => _recordMigration(tx, migration));
    completed.add(migration.id);
  }
  return completed;
}

Future<void> _mysqlRecoveryTables(SqlDatabase<Backend> db) async {
  await db.execute(
    SqlCommand('''CREATE TABLE IF NOT EXISTS "_orm_migrations" (
 id VARCHAR(191) NOT NULL PRIMARY KEY, checksum CHAR(64) NOT NULL, applied_at VARCHAR(40) NOT NULL
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin'''),
  );
  await db.execute(
    SqlCommand('''CREATE TABLE IF NOT EXISTS "_orm_migration_steps" (
 migration_id VARCHAR(191) NOT NULL, checksum CHAR(64) NOT NULL, step INT NOT NULL,
 state VARCHAR(16) NOT NULL, phase VARCHAR(32) NOT NULL, failure TEXT, backfill LONGTEXT,
 PRIMARY KEY(migration_id, step)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin'''),
  );
  // MySQL omits temporary-only tables from information_schema during the first
  // history check. Validate the resolved names again after creating the durable
  // tables, before any application DDL or history/checkpoint writes.
  for (final table in ['_orm_migrations', '_orm_migration_steps']) {
    if (!await _hasMigrationTable(db, table)) {
      throw const OrmException(
        'MIGRATION.SESSION',
        'Durable migration metadata tables could not be established.',
      );
    }
  }
}

Future<SchemaVerification> _mysqlBaseline(
  Migrator migrator,
  List<Migration> migrations,
  SchemaSnapshot expected,
) async {
  validateMigrations(migrations, dialect: migrator.database.dialect);
  if (migrator.database.inTransaction) {
    throw const OrmException(
      'MIGRATION.SESSION',
      'Baseline needs an outer session.',
    );
  }
  if (migrations.isEmpty ||
      migrations.last.snapshot?.checksum !=
          expected.forDialect(migrator.database.dialect).checksum) {
    throw const OrmException(
      'MIGRATION.BASELINE',
      'The final migration must carry the expected baseline snapshot.',
    );
  }
  return _migrationSession(migrator.database, migrator.lockTimeout, (
    session,
  ) async {
    if ((await Migrator(session).history()).isNotEmpty ||
        (await _progress(session)).isNotEmpty) {
      throw const OrmException(
        'MIGRATION.BASELINE',
        'Migration history already exists.',
      );
    }
    final verified = await verifySchema(session, expected);
    if (!verified.matches) {
      throw OrmException('MIGRATION.DRIFT', verified.differences.join('\n'));
    }
    await _mysqlRecoveryTables(session);
    await session.transaction((tx) async {
      for (final migration in migrations) {
        await _recordMigration(tx, migration);
      }
    });
    return verified;
  });
}

// Migration steps are single reviewed statements. Executable comments may hide
// session/DDL operations from the transaction classifier and are not accepted.
void _validateMysqlStatement(String sql) {
  final tokens = _sqliteTokens(sql);
  var offset = 0;
  for (var i = 0; i <= tokens.length; i++) {
    final end = i == tokens.length ? sql.length : tokens[i].start;
    final gap = sql.substring(offset, end);
    if (RegExp(r'/\*(?:!|M!)', caseSensitive: false).hasMatch(gap) ||
        RegExp(r'--(?=\S)').hasMatch(gap)) {
      throw const OrmException(
        'MIGRATION.SQL',
        'Executable comments and ambiguous MySQL comment delimiters are not supported in migration steps.',
      );
    }
    if (i == tokens.length) break;
    if (tokens[i].text == '#' ||
        tokens[i].text == ';' && i != tokens.length - 1) {
      throw const OrmException(
        'MIGRATION.SQL',
        'Each migration step must contain one SQL statement; use standard SQL comments.',
      );
    }
    offset = tokens[i].end;
  }
}
