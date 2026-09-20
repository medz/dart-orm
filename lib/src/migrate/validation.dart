// Validation of immutable histories and executable migration statements.

import '../../driver.dart' show SqlDialect;
import '../../schema_model.dart' show TableSchema;
import '../../values.dart' show OrmException;
import 'migration.dart' show Migration;
import 'mysql_recovery.dart' show validateMysqlStatement;
import 'mysql_schema.dart' show isMysqlFamily;
import 'schema.dart' show validateSchema;
import 'step.dart'
    show
        Backfill,
        CheckedSql,
        CheckedTableSql,
        DropConstraint,
        DropTable,
        ExecuteSql,
        RebuildTable;

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
    if (isMysqlFamily(dialect) && migration.id.length > 191) {
      throw const OrmException(
        'MIGRATION.ID',
        'MySQL migration IDs must not exceed 191 characters.',
      );
    }
    for (final step in migration.steps) {
      if (step is CheckedTableSql) {
        if (!isMysqlFamily(dialect)) {
          throw const OrmException(
            'MIGRATION.TARGET',
            'CheckedTableSql requires MySQL or MariaDB.',
          );
        }
        for (final table in [
          step.before,
          step.after,
        ].whereType<TableSchema>()) {
          validateSchema([table], dialect);
        }
        _validateSql(step.sql, transactional: false);
        validateMysqlStatement(step.sql);
        if (!{
          'CREATE',
          'ALTER',
          'DROP',
          'RENAME',
        }.contains(sqlWords(step.sql).first)) {
          throw const OrmException(
            'MIGRATION.DDL',
            'CheckedTableSql must contain a reviewed table DDL statement.',
          );
        }
        continue;
      }
      if (step is Backfill) {
        validateSchema([step.table], dialect);
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
          if (sqlWords(probe).firstOrNull != 'SELECT') {
            throw const OrmException(
              'MIGRATION.PROBE',
              'Recovery conditions must be SELECT queries.',
            );
          }
        }
        continue;
      }
      if (step is DropTable) {
        if (isMysqlFamily(dialect)) {
          throw const OrmException(
            'MIGRATION.RECOVERY',
            'MySQL table removal requires CheckedTableSql with its before schema.',
          );
        }
        continue;
      }
      if (step is RebuildTable) {
        if (dialect != SqlDialect.sqlite) {
          throw const OrmException(
            'MIGRATION.TARGET',
            'Table rebuilds are SQLite operations.',
          );
        }
        validateSchema([step.before], dialect);
        validateSchema([step.after], dialect);
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
      final sql = (step as ExecuteSql).sql;
      _validateSql(sql, transactional: true);
      if (isMysqlFamily(dialect)) {
        validateMysqlStatement(sql);
      }
      if (isMysqlFamily(dialect) &&
          !{
            'INSERT',
            'UPDATE',
            'DELETE',
            'REPLACE',
          }.contains(sqlWords(sql).first)) {
        throw const OrmException(
          'MIGRATION.RECOVERY',
          'MySQL ExecuteSql accepts DML only. DDL requires CheckedTableSql with reviewed before/after schemas.',
        );
      }
    }
  }
}

void _validateSql(String sql, {required bool transactional}) {
  final words = sqlWords(sql);
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

List<String> sqlWords(String sql) {
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
