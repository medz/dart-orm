import 'dart:io';

import 'package:orm/drivers/mysql.dart';
import 'package:orm/drivers/mariadb.dart';
import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/runtime.dart';
import 'package:test/test.dart';

void main() {
  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    group(
      'catalog import $engine',
      () {
        late SqlDatabase<Backend> db;
        late Directory directory;
        final table = 'orm_import_${pid}_$engine';
        setUp(() async {
          db = SqlDatabase(
            engine == 'mysql'
                ? await MysqlDriver.open(
                    MysqlOptions(url: Uri.parse(address!), tls: tls),
                  )
                : await MariadbDriver.open(
                    MariadbOptions(url: Uri.parse(address!), tls: tls),
                  ),
          );
          directory = await Directory('.dart_tool').createTemp('mysql-import-');
        });
        tearDown(() async {
          try {
            await db.execute(SqlCommand('DROP TABLE IF EXISTS `$table`'));
          } finally {
            await db.close();
            await directory.delete(recursive: true);
          }
        });

        test('supported storage imports nominal classes and reproduces physical metadata', () async {
          final schema = TableSchema(
            table,
            columns: [
              Column('id', Codecs.integer, generated: true),
              Column('title', Codecs.text),
              Column('active', Codecs.boolean, defaultSql: 'false'),
              Column(
                'amount',
                Codecs.decimal,
                decimalPrecision: 12,
                decimalScale: 2,
              ),
              Column('created', Codecs.localDateTime, temporalPrecision: 3),
              Column(
                'document',
                Codecs.jsonDocument.nullable(),
                nullable: true,
              ),
            ],
            primaryKey: ['id'],
          );
          for (final command in createSchema([schema], db.dialect)) {
            await db.execute(command);
          }
          final imported = await importSchema(db, tables: [table]);
          expect(
            imported.hasBlockingIssues,
            false,
            reason: imported.toJson().toString(),
          );
          expect(imported.dart, contains('model('));
          expect(imported.dart, contains('.identity()'));
          expect(imported.dart, contains('localDateTime('));
          expect(
            imported.issues.map((i) => i.code),
            contains('IMPORT.TEMPORAL_SEMANTICS'),
          );
          expect(
            imported.issues.map((i) => i.code),
            contains('IMPORT.BOOLEAN_SEMANTICS'),
          );
          final source = File('${directory.path}/schema.dart');
          await source.writeAsString(imported.dart);
          final generated = await generateSchema(source.path);
          final verification = await verifySchema(db, generated.snapshot);
          expect(verification.differences, isEmpty);
        });

        test(
          'unsigned and binary text types cannot become guessed codecs',
          () async {
            await db.execute(
              SqlCommand('''CREATE TABLE `$table` (
  id BIGINT UNSIGNED NOT NULL,
  token VARBINARY(16) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin'''),
            );
            final imported = await importSchema(db, tables: [table]);
            expect(imported.hasBlockingIssues, true);
            expect(imported.entities, isEmpty);
            expect(
              imported.issues.where((i) => i.code == 'IMPORT.TYPE'),
              hasLength(2),
            );
          },
        );

        test('named SQL checks structure without pretending to infer storage types', () async {
          final source = File('${directory.path}/queries.dart');
          await source.writeAsString('''
import 'package:orm/schema.dart';
final probe = sqlQuery(result: (value: integer(),), parameters: (minimum: integer(),), $engine: 'query.sql');
''');
          await File('${directory.path}/query.sql')
              .writeAsString('SELECT :minimum AS value');
          final generated = await generateQueries(source.path);
          final checked = await checkSqlQueries(db, generated);
          expect(checked.single['structureChecked'], true);
          expect(checked.single['storageTypesChecked'], false);
          expect(checked.single['nullabilityChecked'], false);
        });

        test('named SQL preparation never executes stored functions', () async {
          final function = '${table}_effect';
          await db.execute(
            SqlCommand('CREATE TABLE `$table` (n INT NOT NULL)'),
          );
          await db.execute(
            SqlCommand('''CREATE FUNCTION `$function`() RETURNS INT
DETERMINISTIC MODIFIES SQL DATA
BEGIN INSERT INTO `$table` VALUES (1); RETURN 1; END; /* final delimiter */'''),
          );
          try {
            final source = File('${directory.path}/queries.dart');
            await source.writeAsString('''
import 'package:orm/schema.dart';
final probe = sqlQuery(result: (value: integer(),), parameters: (minimum: integer(),), $engine: 'query.sql');
''');
            final sql = File('${directory.path}/query.sql');
            await sql.writeAsString('SELECT `$function`() + :minimum AS value');
            final generated = await generateQueries(source.path);
            expect(
              (await checkSqlQueries(db, generated)).single['structureChecked'],
              true,
            );
            expect(
              (await db.execute(SqlCommand('SELECT COUNT(*) FROM `$table`')))
                  .rows
                  .single
                  .single,
              0,
            );

            await sql.writeAsString(
              'SELECT `$function`() + :minimum AS wrong_alias',
            );
            final invalid = await generateQueries(source.path);
            await expectLater(
              checkSqlQueries(db, invalid),
              throwsA(isA<GenerationException>()),
            );
            // A rejected PREPARE also cleans up its session state and keeps the
            // connection usable without running the function during checking.
            expect(
              (await db.execute(SqlCommand('SELECT COUNT(*) FROM `$table`')))
                  .rows
                  .single
                  .single,
              0,
            );
          } finally {
            await db.execute(SqlCommand('DROP FUNCTION IF EXISTS `$function`'));
          }
        });
      },
      skip: address == null ? 'Set $variable to a disposable database.' : false,
    );
  }
}
