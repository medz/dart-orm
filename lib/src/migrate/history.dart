part of '../../migrate.dart';

final class Migration {
  final String id;
  final Map<SqlDialect, List<String>> statements;
  final SchemaSnapshot? snapshot;
  final String? previous;
  Migration(
    this.id,
    Map<SqlDialect, List<String>> statements, {
    this.snapshot,
    this.previous,
  }) : statements = Map.unmodifiable(
         statements.map(
           (key, value) => MapEntry(key, List<String>.unmodifiable(value)),
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
  factory Migration.fromJson(Map<String, Object?> json) {
    if (json['format'] != 1) {
      throw const OrmException(
        'MIGRATION.FORMAT',
        'Unsupported migration format.',
      );
    }
    final sql = json['sql'] as Map<String, Object?>;
    return Migration(
      json['id'] as String,
      {
        for (final entry in sql.entries)
          SqlDialect.values.byName(entry.key): (entry.value as List<Object?>)
              .cast<String>(),
      },
      snapshot: json['snapshot'] == null
          ? null
          : SchemaSnapshot.fromJson(json['snapshot'] as Map<String, Object?>),
      previous: json['previous'] as String?,
    );
  }
  Map<String, Object?> toJson() => {
    'format': 1,
    'id': id,
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (previous != null) 'previous': previous,
    'sql': {
      for (final entry in statements.entries) entry.key.name: entry.value,
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
  const Migrator(this.database);

  /// Registers a verified existing database without replaying creation SQL.
  Future<SchemaVerification> baseline(
    List<Migration> migrations, {
    required SchemaSnapshot expected,
  }) async {
    _validate(migrations);
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
    return database.transaction(
      (tx) async {
        if (tx.dialect == SqlDialect.postgres) {
          await tx.execute(
            SqlCommand(
              'SELECT pg_advisory_xact_lock(182983479, hashtext(current_schema()))',
            ),
          );
        }
        if ((await Migrator(tx).history()).isNotEmpty) {
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
    );
  }

  Future<List<MigrationStatus>> history() async {
    final exists = database.dialect == SqlDialect.sqlite
        ? SqlCommand(
            "SELECT name FROM sqlite_schema WHERE type = 'table' AND name = '_orm_migrations'",
          )
        : SqlCommand(
            "SELECT tablename FROM pg_catalog.pg_tables WHERE schemaname = current_schema() AND tablename = '_orm_migrations'",
          );
    if ((await database.execute(exists)).rows.isEmpty) return [];
    final rows = await database.execute(
      SqlCommand('SELECT id, checksum FROM "_orm_migrations" ORDER BY id'),
    );
    return [
      for (final row in rows.rows)
        MigrationStatus(row[0] as String, row[1] as String),
    ];
  }

  Future<List<Migration>> plan(List<Migration> migrations) async {
    _validate(migrations);
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
    return migrations.skip(applied.length).toList(growable: false);
  }

  /// The complete pending batch is atomic. A later failure also rolls back
  /// earlier DDL and history records from this invocation.
  Future<List<String>> apply(List<Migration> migrations) async {
    if (database.inTransaction) {
      throw const OrmException(
        'MIGRATION.SESSION',
        'Migrations require a dedicated outer transaction.',
      );
    }
    _validate(migrations);
    return database.transaction(
      (tx) async {
        if (database.dialect == SqlDialect.postgres) {
          await tx.execute(
            SqlCommand(
              'SELECT pg_advisory_xact_lock(182983479, hashtext(current_schema()))',
            ),
          );
        }
        await tx.execute(
          SqlCommand(
            'CREATE TABLE IF NOT EXISTS "_orm_migrations" '
            '(id TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TEXT NOT NULL)',
          ),
        );
        final pending = await Migrator(tx).plan(migrations);
        for (final migration in pending) {
          for (final statement in migration.statements[database.dialect]!) {
            await tx.execute(SqlCommand(statement));
          }
          await _recordMigration(tx, migration);
        }
        return [for (final migration in pending) migration.id];
      },
      options: database.dialect == SqlDialect.sqlite
          ? const SqliteTransaction(mode: SqliteTransactionMode.immediate)
          : const PostgresTransaction(),
    );
  }

  void _validate(List<Migration> migrations) {
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
      if (migration.previous != null &&
          migration.previous != previousChecksum) {
        throw const OrmException(
          'MIGRATION.CHAIN',
          'Migration previous-checksum chain is broken.',
        );
      }
      previousChecksum = migration.checksum;
      final statements = migration.statements[database.dialect];
      if (statements == null) {
        throw OrmException(
          'MIGRATION.TARGET',
          '${migration.id} has no SQL for ${database.dialect.name}.',
        );
      }
      for (final sql in statements) {
        // Transaction control belongs to the runner. Nontransactional operations
        // require a separate recoverable execution mode, not silent autocommit.
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
              'VACUUM',
              'PRAGMA',
              'START',
              'ABORT',
            }.contains(words.first) ||
            words.contains('CONCURRENTLY')) {
          throw const OrmException(
            'MIGRATION.TRANSACTION',
            'This operation requires an explicitly nontransactional migration.',
          );
        }
      }
    }
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
