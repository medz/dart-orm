@Tags(['database'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/cli.dart';

void main() {
  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    test(
      'CLI $backend imports and reports issues without replacing files or changing rows',
      () async {
        final schema =
            'orm_import_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        final directory = await Directory.systemTemp.createTemp(
          'orm-import-cli-',
        );
        final path = '${directory.path}/database.sqlite';
        final source = '${directory.path}/imported.dart';
        final options = backend == 'sqlite'
            ? ['--sqlite', path]
            : [
                '--postgres-env',
                'ORM_TEST_POSTGRES',
                '--tls',
                'disable',
                '--database-schema',
                schema,
              ];
        late Database<Backend> db;
        Future<CliResult> cli(List<String> args, {int code = 0}) async {
          final result = await runCli([...args, '--json']);
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
                schema: schema,
              ),
            );
            await db.execute(
              SqlCommand('DROP SCHEMA IF EXISTS $schema CASCADE'),
            );
            await db.execute(SqlCommand('CREATE SCHEMA $schema'));
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
              '--table',
              'existing',
            ]);
            final report = jsonDecode(imported.stdout) as Map<String, Object?>;
            expect(report['issues'], isEmpty);
            expect(
              await File('${directory.path}/imported.import.json').exists(),
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
            expect(
              (await db.execute(SqlCommand('SELECT id, value FROM existing')))
                  .rows,
              [
                [7, 'retained'],
              ],
            );

            final blockedSource = '${directory.path}/blocked.dart';
            final blocked = await cli([
              'db',
              'import',
              ...options,
              '--output',
              blockedSource,
              '--table',
              'missing',
            ], code: 2);
            expect((jsonDecode(blocked.stdout) as Map)['issues'], isNotEmpty);
            expect(await File(blockedSource).exists(), true);
            await cli([
              'db',
              'import',
              ...options,
              '--output',
              '${directory.path}/invalid.dart',
              '--table',
              'existing',
              '--table',
              'existing',
            ], code: 64);
            expect(
              await File('${directory.path}/invalid.dart').exists(),
              false,
            );
          } finally {
            if (backend == 'postgres') {
              await db.execute(SqlCommand('DROP SCHEMA $schema CASCADE'));
            }
            await db.close();
          }
        } finally {
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
      tags: backend,
    );
  }
}
