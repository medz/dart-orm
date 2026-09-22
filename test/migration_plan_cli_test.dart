@Tags(['core'])
library;

import 'package:orm/migrate.dart';
import 'package:orm/src/cli/migration.dart';
import 'package:orm/runtime.dart';
import 'package:test/test.dart';

import 'support/cli.dart';

void main() {
  for (final dialect in SqlDialect.values) {
    test('${dialect.name} CLI reports the generated DDL atomicity', () async {
      final migration = Migration.create('0001_initial', [
        TableSchema(
          'items',
          columns: [Column('id', Codecs.integer)],
          primaryKey: ['id'],
        ),
      ], dialect: dialect);
      final driver = _CatalogDriver(dialect);
      final result = await captureCli(
        () => runMigrationCommand(
          ['plan'],
          history: MigrationHistory([
            (migration, migration.checksum),
          ], dialect: dialect),
          directory: 'unused',
          connect: ({required readOnly}) {
            expect(readOnly, isTrue);
            return SqlDatabase(driver);
          },
        ),
      );
      expect(result.exitCode, 0, reason: result.stderr);
      final report = cliReport(result);
      expect(report['pending'], hasLength(1));
      expect(
        report['atomic'],
        dialect == SqlDialect.sqlite || dialect == SqlDialect.postgres,
      );
      expect(driver.closed, isTrue);
    });
  }
}

/// Only protocol metadata is needed: the simulated server has no migration
/// history tables. Any attempted DDL fails instead of being silently accepted.
final class _CatalogDriver(final SqlDialect dialect)
    implements Driver<Backend> {
  bool closed = false;
  @override
  late final capabilities = Capabilities(dialect: dialect, maxParameters: 999);
  @override
  Future<T> run<T>(Future<T> Function(SqlConnection) action) =>
      action(_CatalogConnection(dialect));
  @override
  Future<void> close() async => closed = true;
}

final class _CatalogConnection(final SqlDialect dialect)
    implements SqlConnection {
  @override
  bool get transactionActive => false;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    if (command.sql == 'SELECT VERSION()') {
      return SqlResult([
        [dialect == SqlDialect.mysql ? '8.4.0' : '11.8.0-MariaDB'],
      ]);
    }
    if (command.sql == 'SHOW server_version_num') {
      return const SqlResult([
        ['180000'],
      ]);
    }
    if (!command.sql.startsWith('SELECT')) {
      throw StateError('Migration plan must not execute DDL: ${command.sql}');
    }
    return dialect == SqlDialect.postgres
        ? const SqlResult([
            [false, true],
          ])
        : const SqlResult([]);
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => throw UnsupportedError('Migration plan does not open cursors.');
  @override
  Future<void> invalidate() async {}
}
