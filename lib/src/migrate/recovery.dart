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
  const MigrationProgress(
    this.id,
    this.checksum,
    this.step,
    this.state,
    this.phase,
    this.failure,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'checksum': checksum,
    'step': step,
    'state': state.name,
    'phase': phase,
    if (failure != null) 'failure': failure,
  };
}

Future<List<MigrationProgress>> _progress(Database<Backend> db) async {
  if (db.dialect != SqlDialect.postgres ||
      !await _hasMigrationTable(db, '_orm_migration_steps')) {
    return [];
  }
  final result = await db.execute(
    SqlCommand(
      'SELECT migration_id, checksum, step, state, phase, failure FROM "_orm_migration_steps" ORDER BY migration_id, step',
    ),
  );
  return [
    for (final row in result.rows)
      MigrationProgress(
        row[0] as String,
        row[1] as String,
        row[2] as int,
        MigrationStepState.values.byName(row[3] as String),
        row[4] as String,
        row[5] as String?,
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
        row.step >= migration.steps[dialect]!.length ||
        (!finished.contains(row.id) && row.id != next)) {
      throw const OrmException(
        'MIGRATION.HISTORY',
        'Migration checkpoint does not match the next pending migration.',
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
        (rows.length != local[entry.key]!.steps[dialect]!.length ||
            rows.last.state != .complete)) {
      throw const OrmException(
        'MIGRATION.HISTORY',
        'Applied migration has unfinished checkpoints.',
      );
    }
  }
}

Future<R> _migrationSession<R>(
  Database<Backend> database,
  Duration lockTimeout,
  Future<R> Function(Database<Backend>) action,
) {
  if (lockTimeout.isNegative) {
    throw ArgumentError.value(lockTimeout, 'lockTimeout');
  }
  Future<R> run(Database<Backend> session) =>
      session.dialect == SqlDialect.postgres
      ? _withMigrationLock(session, lockTimeout, () => action(session))
      : action(session);
  return database.inSession ? run(database) : database.session(run);
}

Future<R> _withMigrationLock<R>(
  Database<Backend> session,
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
  Database<Backend> session,
  List<Migration> migrations,
) async {
  final pending = await Migrator(session).plan(migrations);
  if (pending.isEmpty) return [];
  await session.transaction((tx) async {
    await tx.execute(SqlCommand(_historyDdl));
    await tx.execute(
      SqlCommand('''CREATE TABLE IF NOT EXISTS "_orm_migration_steps" (
 migration_id TEXT NOT NULL, checksum TEXT NOT NULL, step INTEGER NOT NULL,
 state TEXT NOT NULL, phase TEXT NOT NULL, failure TEXT,
 PRIMARY KEY(migration_id, step))'''),
    );
  });
  final progress = {
    for (final p in await _progress(session)) (p.id, p.step): p,
  };
  final atomic = <Migration>[];
  Future<void> flush() async {
    if (atomic.isEmpty) return;
    await session.transaction((tx) async {
      for (final migration in atomic) {
        for (final step in migration.steps[SqlDialect.postgres]!) {
          await _executeStep(tx, step);
        }
        await _recordMigration(tx, migration);
      }
    });
    atomic.clear();
  }

  for (final migration in pending) {
    final steps = migration.steps[SqlDialect.postgres]!;
    if (!steps.any((s) => s is CheckedSql)) {
      atomic.add(migration);
      continue;
    }
    await flush();
    for (var i = 0; i < steps.length; i++) {
      if (progress[(migration.id, i)]?.state == .complete) continue;
      final step = steps[i];
      var phase = step is CheckedSql ? 'inspect' : 'execute';
      try {
        await _checkpoint(session, migration, i, .running, phase);
        if (step is CheckedSql) {
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
  }
  await flush();
  return pending.map((m) => m.id).toList();
}

Future<bool> _probe(Database<Backend> db, String sql) async {
  final result = await db.execute(SqlCommand(sql));
  if (result.rows.length != 1 ||
      result.rows.single.length != 1 ||
      result.rows.single.single is! bool) {
    throw const OrmException(
      'MIGRATION.PROBE',
      'A recovery condition must return exactly one boolean.',
    );
  }
  return result.rows.single.single as bool;
}

Future<void> _checkpoint(
  Database<Backend> db,
  Migration migration,
  int step,
  MigrationStepState state,
  String phase, {
  String? failure,
}) async {
  await db.execute(
    SqlCommand(
      r'''
INSERT INTO "_orm_migration_steps" (migration_id, checksum, step, state, phase, failure)
VALUES ($1, $2, $3, $4, $5, $6)
ON CONFLICT (migration_id, step) DO UPDATE SET state = EXCLUDED.state, phase = EXCLUDED.phase, failure = EXCLUDED.failure
WHERE "_orm_migration_steps".state <> 'complete' ''',
      [migration.id, migration.checksum, step, state.name, phase, failure],
    ),
  );
}

const _historyDdl =
    'CREATE TABLE IF NOT EXISTS "_orm_migrations" (id TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TEXT NOT NULL)';
Future<bool> _hasMigrationTable(
  Database<Backend> db,
  String table,
) async => (await db.execute(
  db.dialect == SqlDialect.sqlite
      ? SqlCommand(
          "SELECT name FROM sqlite_schema WHERE type = 'table' AND name = ?1",
          [table],
        )
      : SqlCommand(
          r"SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = current_schema() AND tablename = $1",
          [table],
        ),
)).rows.isNotEmpty;
