import 'dart:convert';
import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    test(
      'CLI $backend imports reviews generates and baselines existing data without replacing files',
      () async {
        final directory = await Directory('.dart_tool/orm-import-cli-$backend')
            .create(recursive: true);
        final path = '${directory.path}/data.sqlite';
        final source = '${directory.path}/schema.dart';
        final tables = File('${directory.path}/tables.json');
        await tables.writeAsString('["existing"]');
        final options = backend == 'sqlite'
            ? ['--sqlite', path]
            : [
                '--postgres-env',
                'ORM_TEST_POSTGRES',
                '--tls',
                'disable',
                '--database-schema',
                'orm_import_cli_tests',
              ];
        late Database<Backend> db;
        Future<ProcessResult> cli(List<String> args, {int code = 0}) async {
          final result = await Process.run(Platform.resolvedExecutable, [
            'run',
            'bin/orm.dart',
            ...args,
          ]);
          expect(
            result.exitCode,
            code,
            reason:
                '${args.take(2).join(' ')}: ${result.stdout}\n${result.stderr}',
          );
          return result;
        }

        try {
          if (backend == 'sqlite') {
            await cli([
              'db',
              'import',
              ...options,
              '--output',
              source,
            ], code: 1);
            expect(await File(path).exists(), false);
            expect(await File(source).exists(), false);
            db = await sqlite(SqliteOptions.file(path));
          } else {
            db = postgres(
              PostgresOptions(
                url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                tls: .disable,
                schema: 'orm_import_cli_tests',
              ),
            );
            await db.execute(
              SqlCommand('DROP SCHEMA IF EXISTS orm_import_cli_tests CASCADE'),
            );
            await db.execute(SqlCommand('CREATE SCHEMA orm_import_cli_tests'));
          }
          try {
            await db.execute(
              SqlCommand(
                'CREATE TABLE existing (id ${backend == 'sqlite' ? 'INTEGER' : 'BIGINT'} NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
              ),
            );
            await db.execute(
              SqlCommand(
                "INSERT INTO existing(id, value) VALUES (7, 'retained')",
              ),
            );
            final imported = await cli([
              'db',
              'import',
              ...options,
              '--output',
              source,
              '--tables',
              tables.path,
            ]);
            final report =
                jsonDecode(imported.stdout as String) as Map<String, Object?>;
            expect(report['issues'], isEmpty);
            expect(
              await File('${directory.path}/schema.import.json').exists(),
              true,
            );
            final original = await File(source).readAsString();
            await cli([
              'db',
              'import',
              ...options,
              '--output',
              source,
            ], code: 64);
            expect(await File(source).readAsString(), original);
            final migrations = '${directory.path}/migrations';
            await cli(['generate', source]);
            await cli([
              'migration',
              'create',
              '0001_imported',
              '--schema',
              '${directory.path}/schema.orm.json',
              '--dir',
              migrations,
            ]);
            final baseline = await cli([
              'db',
              'baseline',
              ...options,
              '--dir',
              migrations,
            ]);
            expect(
              (jsonDecode(baseline.stdout as String) as Map)['matches'],
              true,
            );
            await cli([
              'db',
              'verify',
              ...options,
              '--schema',
              '${directory.path}/schema.orm.json',
            ]);
            expect(
              (await db.execute(SqlCommand('SELECT id, value FROM existing')))
                  .rows,
              [
                [7, 'retained'],
              ],
            );

            final blockedSource = '${directory.path}/blocked.dart';
            await tables.writeAsString('["missing"]');
            final blocked = await cli([
              'db',
              'import',
              ...options,
              '--output',
              blockedSource,
              '--tables',
              tables.path,
            ], code: 2);
            expect(
              (jsonDecode(blocked.stdout as String) as Map)['issues'],
              isNotEmpty,
            );
            expect(await File(blockedSource).exists(), true);
            await tables.writeAsString('["existing", "existing"]');
            await cli([
              'db',
              'import',
              ...options,
              '--output',
              '${directory.path}/invalid.dart',
              '--tables',
              tables.path,
            ], code: 64);
            expect(
              await File('${directory.path}/invalid.dart').exists(),
              false,
            );
          } finally {
            await db.close();
          }
        } finally {
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
