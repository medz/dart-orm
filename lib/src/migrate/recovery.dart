// Migration locking, checkpoints, and PostgreSQL/SQLite recovery.

import 'dart:convert' show jsonDecode, jsonEncode, utf8;

import '../../driver.dart' show Backend, SqlCommand, SqlDialect;
import '../../runtime.dart'
    show PostgresTransaction, SqlDatabase, SqliteTransaction;
import '../../values.dart' show OrmException;
import 'backfill.dart'
    show
        BackfillBudget,
        BackfillPaused,
        BackfillProgress,
        backfillChunk,
        parameterMarker,
        readBackfillProgress,
        verifyBackfill;
import 'execute.dart' show executeStep;
import 'history.dart' show MigrationStatus, Migrator, recordMigration;
import 'migration.dart' show Migration;
import 'mysql_recovery.dart' show mysqlMigrationLock;
import 'mysql_schema.dart' show isMysqlFamily;
import 'progress.dart' show MigrationProgress, MigrationStepState;
import 'sql_utils.dart' show quoteIdentifier;
import 'step.dart' show Backfill, CheckedSql, DropTable, RebuildTable;

// The history schema owns these TEXT cells. MySQL can expose a binary-collated
// TEXT field as bytes; this does not change decoding of application BLOB values.
String? _migrationText(Object? value) =>
    value is List<int> ? utf8.decode(value) : value as String?;

Future<List<MigrationProgress>> loadMigrationProgress(
  SqlDatabase<Backend> db,
) async {
  if (!await hasMigrationTable(db, '_orm_migration_steps')) {
    return [];
  }
  final result = await db.execute(
    SqlCommand(
      'SELECT * FROM "_orm_migration_steps" ORDER BY migration_id, step',
    ),
  );
  final fields = [
    for (final name in [
      'migration_id',
      'checksum',
      'step',
      'state',
      'phase',
      'failure',
    ])
      result.columns.indexOf(name),
  ];
  if (fields.any((i) => i < 0)) {
    throw const OrmException(
      'MIGRATION.HISTORY',
      'Migration checkpoint table is missing required columns.',
    );
  }
  final data = result.columns.indexOf('backfill');
  return [
    for (final row in result.rows)
      MigrationProgress(
        row[fields[0]] as String,
        row[fields[1]] as String,
        row[fields[2]] as int,
        MigrationStepState.values.byName(row[fields[3]] as String),
        row[fields[4]] as String,
        _migrationText(row[fields[5]]),
        backfill: data < 0 || row[data] == null
            ? null
            : readBackfillProgress(jsonDecode(_migrationText(row[data])!)),
      ),
  ];
}

void validateProgress(
  List<Migration> migrations,
  List<MigrationStatus> applied,
  List<MigrationProgress> progress,
  SqlDialect dialect,
) {
  final local = {for (final m in migrations) m.id: m},
      finished = applied.map((m) => m.id).toSet();
  final next = migrations.length > applied.length
      ? migrations[applied.length].id
      : null;
  final grouped = <String, List<MigrationProgress>>{};
  for (final row in progress) {
    final migration = local[row.id];
    if (migration == null || migration.checksum != row.checksum) {
      throw OrmException(
        'MIGRATION.CHECKSUM',
        'Attempted migration ${row.id} differs from local history.',
      );
    }
    if (row.step < 0 ||
        row.step >= migration.steps.length ||
        (!finished.contains(row.id) && row.id != next)) {
      throw const OrmException(
        'MIGRATION.HISTORY',
        'Migration checkpoint does not match the next pending migration.',
      );
    }
    if (row.backfill != null && migration.steps[row.step] is! Backfill) {
      throw const OrmException(
        'MIGRATION.HISTORY',
        'Backfill cursor belongs to a different step kind.',
      );
    }
    final step = migration.steps[row.step];
    if (step is Backfill &&
        ((row.state == .complete && row.backfill == null) ||
            row.backfill?.upperKey != null &&
                row.backfill!.upperKey!.length !=
                    step.table.primaryKey.length ||
            row.backfill?.lastKey != null &&
                row.backfill!.lastKey!.length !=
                    step.table.primaryKey.length)) {
      throw const OrmException(
        'MIGRATION.HISTORY',
        'Backfill checkpoint does not match its primary key or completion state.',
      );
    }
    (grouped[row.id] ??= []).add(row);
  }
  for (final entry in grouped.entries) {
    final rows = entry.value;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].step != i ||
          (i < rows.length - 1 && rows[i].state != .complete)) {
        throw const OrmException(
          'MIGRATION.HISTORY',
          'Migration checkpoints must form a completed prefix followed by at most one unfinished step.',
        );
      }
    }
    if (finished.contains(entry.key) &&
        (rows.length != local[entry.key]!.steps.length ||
            rows.last.state != .complete)) {
      throw const OrmException(
        'MIGRATION.HISTORY',
        'Applied migration has unfinished checkpoints.',
      );
    }
  }
}

Future<R> migrationSession<R>(
  SqlDatabase<Backend> database,
  Duration lockTimeout,
  Future<R> Function(SqlDatabase<Backend>) action,
) {
  if (lockTimeout.isNegative) {
    throw ArgumentError.value(lockTimeout, 'lockTimeout');
  }
  Future<R> run(SqlDatabase<Backend> session) async {
    await checkMigrationVersion(session);
    return isMysqlFamily(session.dialect)
        ? mysqlMigrationLock(session, lockTimeout, () => action(session))
        : session.dialect == SqlDialect.postgres
        ? _withMigrationLock(session, lockTimeout, () => action(session))
        : action(session);
  }

  return database.inSession ? run(database) : database.session(run);
}

// Generated PostgreSQL DDL/catalog behavior is supported on 18+. Check the
// actual server before locks, journal creation or recoverable partial commits.
Future<void> checkMigrationVersion(SqlDatabase<Backend> db) async {
  if (isMysqlFamily(db.dialect)) {
    final raw =
        '${(await db.execute(SqlCommand('SELECT VERSION()'))).rows.single.single}';
    final maria = raw.toLowerCase().contains('mariadb');
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(raw);
    final major = match == null ? 0 : int.parse(match[1]!);
    final minor = match == null ? 0 : int.parse(match[2]!);
    if (maria != (db.dialect == SqlDialect.mariadb) ||
        (maria
            ? major < 11 || major == 11 && minor < 8
            : major < 8 || major == 8 && minor < 4)) {
      throw const OrmException(
        'CAPABILITY.VERSION',
        'Migrations require MySQL 8.4+ or MariaDB 11.8+ with the matching driver.',
      );
    }
    return;
  }
  if (db.dialect != SqlDialect.postgres) return; // SQLite driver checks 3.35+.
  final result = await db.execute(SqlCommand('SHOW server_version_num'));
  final version = int.tryParse('${result.rows.single.single}');
  if (version == null || version < 180000) {
    throw const OrmException(
      'CAPABILITY.VERSION',
      'PostgreSQL migrations require server version 18 or newer.',
    );
  }
}

Future<R> _withMigrationLock<R>(
  SqlDatabase<Backend> session,
  Duration timeout,
  Future<R> Function() action,
) async {
  final schemaKey =
      (await session.execute(SqlCommand('SELECT hashtext(current_schema())')))
              .rows
              .single
              .single
          as int?;
  if (schemaKey == null) {
    throw const OrmException(
      'MIGRATION.SCHEMA',
      'A current PostgreSQL schema is required.',
    );
  }
  final watch = Stopwatch()..start();
  var delay = 10;
  while (true) {
    bool locked;
    try {
      locked =
          (await session.execute(
                SqlCommand(r'SELECT pg_try_advisory_lock(182983479, $1)', [
                  schemaKey,
                ]),
              )).rows.single.single
              as bool;
    } catch (_) {
      await session.discard();
      rethrow;
    }
    if (locked) break;
    if (watch.elapsed >= timeout) {
      throw const OrmException(
        'MIGRATION.LOCK_TIMEOUT',
        'Timed out waiting for the migration runner lock.',
      );
    }
    final remaining = (timeout - watch.elapsed).inMilliseconds.clamp(1, delay);
    // No database transaction/snapshot remains open while waiting. A blocking
    // advisory-lock SELECT can deadlock CREATE INDEX CONCURRENTLY snapshot waits.
    await Future<void>.delayed(Duration(milliseconds: remaining));
    delay = (delay * 2).clamp(10, 250);
  }
  Object? primaryFailure;
  try {
    return await action();
  } catch (error) {
    primaryFailure = error;
    rethrow;
  } finally {
    try {
      final unlocked = await session.execute(
        SqlCommand(r'SELECT pg_advisory_unlock(182983479, $1)', [schemaKey]),
      );
      if (unlocked.rows.single.single != true) {
        throw const OrmException(
          'MIGRATION.LOCK',
          'Migration lock was not held.',
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

Future<List<String>> applyRecoverable(
  SqlDatabase<Backend> session,
  List<Migration> migrations,
  BackfillBudget budget,
) async {
  final pending = await Migrator(session).plan(migrations);
  if (pending.isEmpty) return [];
  await session.transaction(_recoveryTables);
  final progress = {
    for (final p in await loadMigrationProgress(session)) (p.id, p.step): p,
  };
  final atomic = <Migration>[];
  final completed = <String>[];
  Future<void> flush() async {
    if (atomic.isEmpty) return;
    await session.transaction((tx) async {
      for (final migration in atomic) {
        for (final step in migration.steps) {
          await executeStep(tx, step);
        }
        await recordMigration(tx, migration);
      }
    });
    completed.addAll(atomic.map((m) => m.id));
    atomic.clear();
  }

  for (final migration in pending) {
    final steps = migration.steps;
    if (!steps.any((s) => s is CheckedSql || s is Backfill)) {
      atomic.add(migration);
      continue;
    }
    await flush();
    for (var i = 0; i < steps.length; i++) {
      if (progress[(migration.id, i)]?.state == .complete) continue;
      final step = steps[i];
      var phase = step is CheckedSql || step is Backfill
          ? 'inspect'
          : 'execute';
      try {
        await checkpoint(session, migration, i, .running, phase);
        if (step is Backfill) {
          await verifyBackfill(session, step);
          while (!await session.transaction(
            (tx) async => backfillChunk(
              tx,
              migration,
              i,
              step,
              await savedBackfill(tx, migration.id, i),
              budget,
              (value) => phase = value,
            ),
          )) {}
        } else if (step is CheckedSql) {
          if (!await probe(session, step.doneWhen)) {
            if (!await probe(session, step.readyWhen)) {
              throw const OrmException(
                'MIGRATION.RECOVERY',
                'Neither completion nor safe-to-run condition holds. Inspect and repair the database before retrying this unchanged migration.',
              );
            }
            phase = 'execute';
            await checkpoint(session, migration, i, .running, phase);
            await session.execute(SqlCommand(step.sql));
            phase = 'verify';
            await checkpoint(session, migration, i, .running, phase);
            if (!await probe(session, step.doneWhen)) {
              throw const OrmException(
                'MIGRATION.POSTCONDITION',
                'Nontransactional SQL did not establish its declared completion condition.',
              );
            }
          }
          phase = 'record';
          await checkpoint(session, migration, i, .complete, 'complete');
        } else {
          await session.transaction((tx) async {
            await executeStep(tx, step);
            await checkpoint(tx, migration, i, .complete, 'complete');
          });
        }
      } catch (error, stack) {
        if (error is BackfillPaused) return completed;
        try {
          // Never overwrite a completion record after an uncertain commit.
          await checkpoint(
            session,
            migration,
            i,
            .failed,
            phase,
            failure: error is OrmException
                ? error.code
                : error.runtimeType.toString(),
          );
        } catch (_) {
          /* The durable running checkpoint remains recoverable. */
        }
        Error.throwWithStackTrace(
          OrmException(
            'MIGRATION.STEP',
            '${migration.id} step $i failed during $phase. Inspect migration progress before retrying.',
            cause: error,
          ),
          stack,
        );
      }
    }
    await session.transaction((tx) => recordMigration(tx, migration));
    completed.add(migration.id);
  }
  await flush();
  return completed;
}

bool needsRebuild(List<Migration> migrations, SqlDialect dialect) =>
    dialect == SqlDialect.sqlite &&
    migrations.any(
      (m) => m.steps.any((s) => s is RebuildTable || s is DropTable),
    );

Future<R> migrationTransaction<R>(
  SqlDatabase<Backend> session,
  Future<R> Function(SqlDatabase<Backend>) action, {
  bool rebuild = false,
}) async {
  int? foreignKeys;
  try {
    if (rebuild) {
      foreignKeys =
          (await session.execute(SqlCommand('PRAGMA foreign_keys')))
                  .rows
                  .single
                  .single
              as int;
      await session.execute(SqlCommand('PRAGMA foreign_keys = OFF'));
      if ((await session.execute(SqlCommand('PRAGMA foreign_keys')))
              .rows
              .single
              .single !=
          0) {
        throw const OrmException(
          'MIGRATION.SESSION',
          'Foreign keys must be disabled before a rebuild transaction.',
        );
      }
    }
    return await session.transaction(
      (tx) async {
        final result = await action(tx);
        if (rebuild &&
            (await tx.execute(SqlCommand('PRAGMA foreign_key_check')))
                .rows
                .isNotEmpty) {
          throw const OrmException(
            'MIGRATION.FOREIGN_KEY',
            'Rebuilt schema contains foreign key violations.',
          );
        }
        return result;
      },
      options: session.dialect == SqlDialect.sqlite
          ? const SqliteTransaction(mode: .immediate)
          : const PostgresTransaction(),
    );
  } finally {
    if (foreignKeys != null) {
      try {
        await session.execute(
          SqlCommand(
            'PRAGMA foreign_keys = ${foreignKeys == 1 ? 'ON' : 'OFF'}',
          ),
        );
        if ((await session.execute(SqlCommand('PRAGMA foreign_keys')))
                .rows
                .single
                .single !=
            foreignKeys) {
          throw const OrmException(
            'MIGRATION.SESSION',
            'Failed to restore SQLite foreign keys.',
          );
        }
      } catch (_) {
        await session.discard();
        rethrow;
      }
    }
  }
}

/// SQLite serializes each chunk using BEGIN IMMEDIATE. Re-read durable history
/// inside that lock, so other workers may contribute chunks without replaying any.
Future<List<String>> applyRecoverableSqlite(
  SqlDatabase<Backend> session,
  List<Migration> migrations,
  BackfillBudget budget,
) async {
  await migrationTransaction(session, (tx) async {
    await Migrator(tx).plan(migrations);
    await _recoveryTables(tx);
  });
  final atomic = <Migration>[], completed = <String>[];
  Future<void> flush() async {
    if (atomic.isEmpty) return;
    final applied = await migrationTransaction(session, (tx) async {
      final pending = (await Migrator(tx).plan(migrations))
          .map((m) => m.id)
          .toSet();
      final applied = <String>[];
      for (final migration in atomic) {
        if (!pending.contains(migration.id)) continue;
        for (final step in migration.steps) {
          await executeStep(tx, step);
        }
        await recordMigration(tx, migration);
        applied.add(migration.id);
      }
      return applied;
    }, rebuild: needsRebuild(atomic, SqlDialect.sqlite));
    completed.addAll(applied);
    atomic.clear();
  }

  for (final migration in migrations) {
    final steps = migration.steps;
    if (!steps.any((s) => s is Backfill)) {
      atomic.add(migration);
      continue;
    }
    await flush();
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      var verified = false, phase = 'inspect';
      try {
        while (!await migrationTransaction(session, (tx) async {
          final pending = await Migrator(tx).plan(migrations);
          if (!pending.any((m) => m.id == migration.id)) return true;
          final current = (await loadMigrationProgress(tx))
              .where((p) => p.id == migration.id && p.step == i)
              .firstOrNull;
          if (current?.state == .complete) return true;
          if (current == null) {
            await checkpoint(tx, migration, i, .running, 'inspect');
            return false;
          }
          if (step is Backfill) {
            if (!verified) {
              phase = 'inspect';
              await verifyBackfill(tx, step);
              verified = true;
            }
            return backfillChunk(
              tx,
              migration,
              i,
              step,
              current.backfill,
              budget,
              (value) => phase = value,
            );
          }
          phase = 'execute';
          await executeStep(tx, step);
          phase = 'record';
          await checkpoint(tx, migration, i, .complete, 'complete');
          return true;
        }, rebuild: step is RebuildTable || step is DropTable)) {}
      } catch (error, stack) {
        if (error is BackfillPaused) return completed;
        try {
          await migrationTransaction(
            session,
            (tx) => checkpoint(
              tx,
              migration,
              i,
              .failed,
              phase,
              failure: error is OrmException
                  ? error.code
                  : error.runtimeType.toString(),
            ),
          );
        } catch (_) {
          /* An existing durable checkpoint remains resumable. */
        }
        Error.throwWithStackTrace(
          OrmException(
            'MIGRATION.STEP',
            '${migration.id} step $i failed during $phase. Inspect migration progress before retrying.',
            cause: error,
          ),
          stack,
        );
      }
    }
    final recorded = await migrationTransaction(session, (tx) async {
      if (!(await Migrator(tx).plan(migrations))
          .any((m) => m.id == migration.id)) {
        return false;
      }
      await recordMigration(tx, migration);
      return true;
    });
    if (recorded) completed.add(migration.id);
  }
  await flush();
  return completed;
}

Future<bool> probe(SqlDatabase<Backend> db, String sql) async {
  final result = await db.execute(SqlCommand(sql));
  if (result.rows.length != 1 ||
      result.rows.single.length != 1 ||
      !(result.rows.single.single is bool ||
          db.dialect != SqlDialect.postgres &&
              result.rows.single.single is int &&
              {0, 1}.contains(result.rows.single.single))) {
    throw const OrmException(
      'MIGRATION.PROBE',
      'A recovery condition must return exactly one boolean.',
    );
  }
  return result.rows.single.single == true || result.rows.single.single == 1;
}

Future<void> checkpoint(
  SqlDatabase<Backend> db,
  Migration migration,
  int step,
  MigrationStepState state,
  String phase, {
  String? failure,
  BackfillProgress? backfill,
}) async {
  await db.execute(
    SqlCommand(
      '''
INSERT INTO "_orm_migration_steps" (migration_id, checksum, step, state, phase, failure, backfill)
VALUES (${[for (var i = 1; i <= 7; i++) parameterMarker(db.dialect, i)].join(', ')})
${isMysqlFamily(db.dialect) ? "ON DUPLICATE KEY UPDATE phase = IF(state = 'complete', phase, VALUES(phase)), failure = IF(state = 'complete', failure, VALUES(failure)), backfill = IF(state = 'complete', backfill, COALESCE(VALUES(backfill), backfill)), state = IF(state = 'complete', state, VALUES(state))" : "ON CONFLICT (migration_id, step) DO UPDATE SET state = EXCLUDED.state, phase = EXCLUDED.phase, failure = EXCLUDED.failure, backfill = coalesce(EXCLUDED.backfill, \"_orm_migration_steps\".backfill) WHERE \"_orm_migration_steps\".state <> 'complete'"} ''',
      [
        migration.id,
        migration.checksum,
        step,
        state.name,
        phase,
        failure,
        backfill == null ? null : jsonEncode(backfill.toJson()),
      ],
    ),
  );
}

Future<void> _recoveryTables(SqlDatabase<Backend> tx) async {
  await tx.execute(SqlCommand(historyDdl));
  await tx.execute(
    SqlCommand('''CREATE TABLE IF NOT EXISTS "_orm_migration_steps" (
 migration_id TEXT NOT NULL, checksum TEXT NOT NULL, step INTEGER NOT NULL,
 state TEXT NOT NULL, phase TEXT NOT NULL, failure TEXT, backfill TEXT,
 PRIMARY KEY(migration_id, step))'''),
  );
  final shape = await tx.execute(
    SqlCommand('SELECT * FROM "_orm_migration_steps" LIMIT 0'),
  );
  if (!shape.columns.contains('backfill')) {
    await tx.execute(
      SqlCommand('ALTER TABLE "_orm_migration_steps" ADD COLUMN backfill TEXT'),
    );
  }
}

Future<BackfillProgress?> savedBackfill(
  SqlDatabase<Backend> tx,
  String id,
  int step,
) async {
  final row = await tx.execute(
    SqlCommand(
      'SELECT backfill FROM "_orm_migration_steps" WHERE migration_id = ${parameterMarker(tx.dialect, 1)} AND step = ${parameterMarker(tx.dialect, 2)}',
      [id, step],
    ),
  );
  final data = row.rows.single.single;
  return data == null
      ? null
      : readBackfillProgress(jsonDecode(_migrationText(data)!));
}

const historyDdl =
    'CREATE TABLE IF NOT EXISTS "_orm_migrations" (id TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TEXT NOT NULL)';
Future<bool> hasMigrationTable(SqlDatabase<Backend> db, String table) async {
  if (isMysqlFamily(db.dialect)) {
    final rows = await db.execute(
      SqlCommand(
        'SELECT TABLE_TYPE, ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
        [table],
      ),
    );
    if (rows.rows.any((r) => r[0] != 'BASE TABLE' || r[1] != 'InnoDB')) {
      throw const OrmException(
        'MIGRATION.SESSION',
        'Durable migration metadata must use InnoDB base tables.',
      );
    }
    if (rows.rows.isNotEmpty) {
      final definition = await db.execute(
        SqlCommand('SHOW CREATE TABLE ${quoteIdentifier(table)}'),
      );
      if ((definition.rows.single[1] as String).toUpperCase().startsWith(
        'CREATE TEMPORARY TABLE',
      )) {
        throw const OrmException(
          'MIGRATION.SESSION',
          'A temporary table shadows durable migration metadata.',
        );
      }
    }
    return rows.rows.isNotEmpty;
  }
  if (db.dialect == SqlDialect.sqlite) {
    final rows = await db.execute(
      SqlCommand(
        "SELECT name, CASE WHEN type = 'table' THEN 0 ELSE 2 END FROM main.sqlite_schema WHERE name = ?1 COLLATE NOCASE UNION ALL SELECT name, 1 FROM sqlite_temp_schema WHERE name = ?1 COLLATE NOCASE",
        [table],
      ),
    );
    if (rows.rows.any((r) => r[1] != 0)) {
      throw const OrmException(
        'MIGRATION.SESSION',
        'A temporary or non-table object shadows durable migration metadata.',
      );
    }
    return rows.rows.isNotEmpty;
  }
  final rows = await db.execute(
    SqlCommand(
      r'''SELECT
 EXISTS(SELECT 1 FROM pg_catalog.pg_tables WHERE schemaname = current_schema() AND tablename::text = $1),
 coalesce((SELECT n.nspname = current_schema() AND c.relkind IN ('r', 'p') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.oid = to_regclass(quote_ident($1))), true)''',
      [table],
    ),
  );
  if (rows.rows.single[1] != true) {
    throw const OrmException(
      'MIGRATION.SESSION',
      'Another schema shadows durable migration metadata.',
    );
  }
  return rows.rows.single[0] == true;
}
