part of '../../migrate.dart';

final class Migration {
  final String id;
  final Map<SqlDialect, List<MigrationStep>> steps;
  final SchemaSnapshot? snapshot;
  final String? previous;
  Migration(
    String id,
    Map<SqlDialect, List<String>> statements, {
    SchemaSnapshot? snapshot,
    String? previous,
  }) : this.steps(
         id,
         {
           for (final entry in statements.entries)
             entry.key: entry.value.map(ExecuteSql.new).toList(),
         },
         snapshot: snapshot,
         previous: previous,
       );
  Migration.steps(
    this.id,
    Map<SqlDialect, List<MigrationStep>> steps, {
    this.snapshot,
    this.previous,
  }) : steps = Map.unmodifiable(
         steps.map(
           (key, value) =>
               MapEntry(key, List<MigrationStep>.unmodifiable(value)),
         ),
       ) {
    if (!RegExp(r'^[0-9]+_[a-z][a-z0-9_]*$').hasMatch(id)) {
      throw ArgumentError(
        'Migration IDs use a numeric prefix and lowercase name.',
      );
    }
  }
  factory Migration.create(String id, List<TableSchema> schema) =>
      Migration(id, {
        for (final dialect in SqlDialect.values)
          dialect: [
            for (final command in createSchema(schema, dialect)) command.sql,
          ],
      }, snapshot: SchemaSnapshot(schema));
  factory Migration.diff(
    String id, {
    required SchemaSnapshot from,
    required SchemaSnapshot to,
    SchemaRenames renames = const SchemaRenames(),
    String? previous,
    bool allowDestructive = false,
    Map<SqlDialect, Map<String, Map<String, String>>> using = const {},
  }) => _diff(
    id,
    from: from,
    to: to,
    renames: renames,
    previous: previous,
    allowDestructive: allowDestructive,
    using: using,
  );
  factory Migration.fromJson(Map<String, Object?> json) {
    if (json['format'] != 2) {
      throw const OrmException(
        'MIGRATION.FORMAT',
        'Unsupported migration format.',
      );
    }
    final steps = json['steps'] as Map<String, Object?>;
    return Migration.steps(
      json['id'] as String,
      {
        for (final entry in steps.entries)
          SqlDialect.values.byName(entry.key): [
            for (final step in entry.value as List<Object?>)
              MigrationStep.fromJson(step as Map<String, Object?>),
          ],
      },
      snapshot: json['snapshot'] == null
          ? null
          : SchemaSnapshot.fromJson(json['snapshot'] as Map<String, Object?>),
      previous: json['previous'] as String?,
    );
  }
  Map<String, Object?> toJson() => {
    'format': 2,
    'id': id,
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (previous != null) 'previous': previous,
    'steps': {
      for (final entry in steps.entries)
        entry.key.name: [for (final step in entry.value) step.toJson()],
    },
  };
  String get checksum => _hash(toJson());
}

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
        migrations.last.snapshot?.checksum != expected.checksum) {
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
    final applied = await history();
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
    _validateProgress(migrations, applied, await progress(), database.dialect);
    return migrations.skip(applied.length).toList(growable: false);
  }

  /// Transactional batches are atomic. CheckedSql explicitly opts a migration
  /// into durable per-step checkpoints with recoverable autocommit SQL.
  Future<List<String>> apply(List<Migration> migrations) async {
    if (database.inTransaction) {
      throw const OrmException(
        'MIGRATION.SESSION',
        'Migrations require a dedicated outer transaction.',
      );
    }
    validateMigrations(migrations, dialect: database.dialect);
    Future<List<String>> run(Database<Backend> session) async {
      if (session.dialect == SqlDialect.postgres &&
          migrations.any(
            (m) => m.steps[SqlDialect.postgres]!.any((s) => s is CheckedSql),
          )) {
        return _applyRecoverable(session, migrations);
      }
      final rebuild =
          database.dialect == SqlDialect.sqlite &&
          migrations.any(
            (m) => m.steps[SqlDialect.sqlite]!.any(
              (s) => s is RebuildTable || s is DropTable,
            ),
          );
      int? foreignKeys;
      if (rebuild) {
        foreignKeys =
            (await session.execute(SqlCommand('PRAGMA foreign_keys')))
                    .rows
                    .single
                    .single
                as int;
      }
      try {
        if (rebuild) {
          await session.execute(SqlCommand('PRAGMA foreign_keys = OFF'));
          if ((await session.execute(SqlCommand('PRAGMA foreign_keys')))
                  .rows
                  .single
                  .single !=
              0) {
            throw const OrmException(
              'MIGRATION.SESSION',
              'Foreign keys must be disabled before the rebuild transaction.',
            );
          }
        }
        return await session.transaction(
          (tx) async {
            await tx.execute(
              SqlCommand(
                'CREATE TABLE IF NOT EXISTS "_orm_migrations" (id TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TEXT NOT NULL)',
              ),
            );
            final pending = await Migrator(tx).plan(migrations);
            for (final migration in pending) {
              for (final step in migration.steps[tx.dialect]!) {
                await _executeStep(tx, step);
              }
              await _recordMigration(tx, migration);
            }
            if (rebuild &&
                (await tx.execute(SqlCommand('PRAGMA foreign_key_check')))
                    .rows
                    .isNotEmpty) {
              throw const OrmException(
                'MIGRATION.FOREIGN_KEY',
                'Rebuilt schema contains foreign key violations.',
              );
            }
            return [for (final migration in pending) migration.id];
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

    return _migrationSession(database, lockTimeout, run);
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
    final steps = migration.steps[dialect];
    if (steps == null) {
      throw OrmException(
        'MIGRATION.TARGET',
        '${migration.id} has no SQL for ${dialect.name}.',
      );
    }
    for (final step in steps) {
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
