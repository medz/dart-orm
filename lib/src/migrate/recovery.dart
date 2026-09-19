part of '../../migrate.dart';

/// PostgreSQL autocommit SQL with explicit recovery conditions. Both checks must
/// return exactly one boolean. They describe durable state, not an object name alone.
final class CheckedSql extends MigrationStep {
  final String sql;
  final String readyWhen;
  final String doneWhen;
  const CheckedSql(this.sql, {required this.readyWhen, required this.doneWhen});

  /// A concurrent, ascending B-tree index with default collation/opclasses.
  /// The completion check compares its definition as well as ready/valid state.
  factory CheckedSql.createIndex(String table, IndexSchema index) {
    if (index.columns.isEmpty) throw ArgumentError('An index needs columns.');
    final source = _literal(table), name = _literal(index.name);
    final columns = 'ARRAY[${index.columns.map(_literal).join(', ')}]::text[]';
    return CheckedSql(
      _createIndex(table, index).replaceFirst('INDEX ', 'INDEX CONCURRENTLY '),
      readyWhen: '''SELECT NOT EXISTS (
SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = current_schema() AND c.relname = $name)''',
      doneWhen:
          '''SELECT EXISTS (
SELECT 1 FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_am am ON am.oid = c.relam
WHERE n.nspname = current_schema() AND c.relname = $name AND t.relname = $source
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

String _literal(String value) {
  var tag = r'$orm$';
  while (value.contains(tag)) {
    tag = '${tag.substring(0, tag.length - 1)}_\$';
  }
  return '$tag$value$tag';
}

enum MigrationStepState { running, complete, failed }

final class MigrationProgress {
  final String id;
  final String checksum;
  final int step;
  final MigrationStepState state;
  final String phase;
  final String? failure;
  final BackfillProgress? backfill;
  const MigrationProgress(
    this.id,
    this.checksum,
    this.step,
    this.state,
    this.phase,
    this.failure, {
    this.backfill,
  });
  Map<String, Object?> toJson() => {
    'id': id,
    'checksum': checksum,
    'step': step,
    'state': state.name,
    'phase': phase,
    if (failure != null) 'failure': failure,
    if (backfill != null) 'backfill': backfill!.toJson(),
  };
}

// The history schema owns these TEXT cells. MySQL can expose a binary-collated
// TEXT field as bytes; this does not change decoding of application BLOB values.
String? _migrationText(Object? value) =>
    value is List<int> ? utf8.decode(value) : value as String?;

Future<List<MigrationProgress>> _progress(SqlDatabase<Backend> db) async {
  if (!await _hasMigrationTable(db, '_orm_migration_steps')) {
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
            : BackfillProgress._read(jsonDecode(_migrationText(row[data])!)),
      ),
  ];
}

void _validateProgress(
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

Future<R> _migrationSession<R>(
  SqlDatabase<Backend> database,
  Duration lockTimeout,
  Future<R> Function(SqlDatabase<Backend>) action,
) {
  if (lockTimeout.isNegative) {
    throw ArgumentError.value(lockTimeout, 'lockTimeout');
  }
  Future<R> run(SqlDatabase<Backend> session) async {
    await _checkMigrationVersion(session);
    return _isMysql(session.dialect)
        ? _mysqlMigrationLock(session, lockTimeout, () => action(session))
        : session.dialect == SqlDialect.postgres
        ? _withMigrationLock(session, lockTimeout, () => action(session))
        : action(session);
  }

  return database.inSession ? run(database) : database.session(run);
}

// Generated PostgreSQL DDL/catalog behavior is supported on 18+. Check the
// actual server before locks, journal creation or recoverable partial commits.
Future<void> _checkMigrationVersion(SqlDatabase<Backend> db) async {
  if (_isMysql(db.dialect)) {
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

Future<List<String>> _applyRecoverable(
  SqlDatabase<Backend> session,
  List<Migration> migrations,
  _BackfillBudget budget,
) async {
  final pending = await Migrator(session).plan(migrations);
  if (pending.isEmpty) return [];
  await session.transaction(_recoveryTables);
  final progress = {
    for (final p in await _progress(session)) (p.id, p.step): p,
  };
  final atomic = <Migration>[];
  final completed = <String>[];
  Future<void> flush() async {
    if (atomic.isEmpty) return;
    await session.transaction((tx) async {
      for (final migration in atomic) {
        for (final step in migration.steps) {
          await _executeStep(tx, step);
        }
        await _recordMigration(tx, migration);
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
        await _checkpoint(session, migration, i, .running, phase);
        if (step is Backfill) {
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
        } else if (step is CheckedSql) {
          if (!await _probe(session, step.doneWhen)) {
            if (!await _probe(session, step.readyWhen)) {
              throw const OrmException(
                'MIGRATION.RECOVERY',
                'Neither completion nor safe-to-run condition holds. Inspect and repair the database before retrying this unchanged migration.',
              );
            }
            phase = 'execute';
            await _checkpoint(session, migration, i, .running, phase);
            await session.execute(SqlCommand(step.sql));
            phase = 'verify';
            await _checkpoint(session, migration, i, .running, phase);
            if (!await _probe(session, step.doneWhen)) {
              throw const OrmException(
                'MIGRATION.POSTCONDITION',
                'Nontransactional SQL did not establish its declared completion condition.',
              );
            }
          }
          phase = 'record';
          await _checkpoint(session, migration, i, .complete, 'complete');
        } else {
          await session.transaction((tx) async {
            await _executeStep(tx, step);
            await _checkpoint(tx, migration, i, .complete, 'complete');
          });
        }
      } catch (error, stack) {
        if (error is _BackfillPaused) return completed;
        try {
          // Never overwrite a completion record after an uncertain commit.
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
    await session.transaction((tx) => _recordMigration(tx, migration));
    completed.add(migration.id);
  }
  await flush();
  return completed;
}

bool _needsRebuild(List<Migration> migrations, SqlDialect dialect) =>
    dialect == SqlDialect.sqlite &&
    migrations.any(
      (m) => m.steps.any((s) => s is RebuildTable || s is DropTable),
    );

Future<R> _migrationTransaction<R>(
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
Future<List<String>> _applyRecoverableSqlite(
  SqlDatabase<Backend> session,
  List<Migration> migrations,
  _BackfillBudget budget,
) async {
  await _migrationTransaction(session, (tx) async {
    await Migrator(tx).plan(migrations);
    await _recoveryTables(tx);
  });
  final atomic = <Migration>[], completed = <String>[];
  Future<void> flush() async {
    if (atomic.isEmpty) return;
    final applied = await _migrationTransaction(session, (tx) async {
      final pending = (await Migrator(tx).plan(migrations))
          .map((m) => m.id)
          .toSet();
      final applied = <String>[];
      for (final migration in atomic) {
        if (!pending.contains(migration.id)) continue;
        for (final step in migration.steps) {
          await _executeStep(tx, step);
        }
        await _recordMigration(tx, migration);
        applied.add(migration.id);
      }
      return applied;
    }, rebuild: _needsRebuild(atomic, SqlDialect.sqlite));
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
        while (!await _migrationTransaction(session, (tx) async {
          final pending = await Migrator(tx).plan(migrations);
          if (!pending.any((m) => m.id == migration.id)) return true;
          final current = (await _progress(tx))
              .where((p) => p.id == migration.id && p.step == i)
              .firstOrNull;
          if (current?.state == .complete) return true;
          if (current == null) {
            await _checkpoint(tx, migration, i, .running, 'inspect');
            return false;
          }
          if (step is Backfill) {
            if (!verified) {
              phase = 'inspect';
              await _verifyBackfill(tx, step);
              verified = true;
            }
            return _backfillChunk(
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
          await _executeStep(tx, step);
          phase = 'record';
          await _checkpoint(tx, migration, i, .complete, 'complete');
          return true;
        }, rebuild: step is RebuildTable || step is DropTable)) {}
      } catch (error, stack) {
        if (error is _BackfillPaused) return completed;
        try {
          await _migrationTransaction(
            session,
            (tx) => _checkpoint(
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
    final recorded = await _migrationTransaction(session, (tx) async {
      if (!(await Migrator(tx).plan(migrations))
          .any((m) => m.id == migration.id)) {
        return false;
      }
      await _recordMigration(tx, migration);
      return true;
    });
    if (recorded) completed.add(migration.id);
  }
  await flush();
  return completed;
}

Future<bool> _probe(SqlDatabase<Backend> db, String sql) async {
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

Future<void> _checkpoint(
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
VALUES (${[for (var i = 1; i <= 7; i++) _mark(db.dialect, i)].join(', ')})
${_isMysql(db.dialect) ? "ON DUPLICATE KEY UPDATE phase = IF(state = 'complete', phase, VALUES(phase)), failure = IF(state = 'complete', failure, VALUES(failure)), backfill = IF(state = 'complete', backfill, COALESCE(VALUES(backfill), backfill)), state = IF(state = 'complete', state, VALUES(state))" : "ON CONFLICT (migration_id, step) DO UPDATE SET state = EXCLUDED.state, phase = EXCLUDED.phase, failure = EXCLUDED.failure, backfill = coalesce(EXCLUDED.backfill, \"_orm_migration_steps\".backfill) WHERE \"_orm_migration_steps\".state <> 'complete'"} ''',
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
  await tx.execute(SqlCommand(_historyDdl));
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

Future<BackfillProgress?> _savedBackfill(
  SqlDatabase<Backend> tx,
  String id,
  int step,
) async {
  final row = await tx.execute(
    SqlCommand(
      'SELECT backfill FROM "_orm_migration_steps" WHERE migration_id = ${_mark(tx.dialect, 1)} AND step = ${_mark(tx.dialect, 2)}',
      [id, step],
    ),
  );
  final data = row.rows.single.single;
  return data == null
      ? null
      : BackfillProgress._read(jsonDecode(_migrationText(data)!));
}

const _historyDdl =
    'CREATE TABLE IF NOT EXISTS "_orm_migrations" (id TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TEXT NOT NULL)';
Future<bool> _hasMigrationTable(SqlDatabase<Backend> db, String table) async {
  if (_isMysql(db.dialect)) {
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
        SqlCommand('SHOW CREATE TABLE ${_quote(table)}'),
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
