import 'dart:io';

import 'package:orm/drivers/mysql.dart';
import 'package:orm/drivers/mariadb.dart';
import 'package:orm/runtime.dart';
import 'package:test/test.dart';

Matcher _code(String code) =>
    isA<OrmException>().having((error) => error.code, 'code', code);

void main() {
  for (final dialect in [SqlDialect.mysql, SqlDialect.mariadb]) {
    group('${dialect.name} boundary without server status', () {
      for (final sql in [
        'CREATE TABLE unsafe (id INT)',
        'CREATE TEMPORARY TABLE unsafe (id INT)',
        'ALTER TABLE data ADD COLUMN extra INT',
        'DROP TABLE data',
        'TRUNCATE TABLE data',
        'COMMIT',
        'ROLLBACK',
        'BEGIN',
        'START TRANSACTION',
        'SAVEPOINT user_savepoint',
        'RELEASE SAVEPOINT user_savepoint',
        'SET AUTOCOMMIT = 1',
        'SET SESSION sql_mode = ""',
        'CALL might_commit()',
        'PREPARE stmt FROM "COMMIT"',
        'EXECUTE stmt',
        'EXECUTE IMMEDIATE "COMMIT"',
        'LOCK TABLES data WRITE',
        'UNLOCK TABLES',
        'ANALYZE TABLE data',
        'SELECT 1; COMMIT',
        'SELECT 1; /* comment */ SET AUTOCOMMIT=1',
        'SELECT 1;;',
        '/*!80000 COMMIT */',
        '/*M!100100 COMMIT */',
        'SELECT 1 /*! INTO OUTFILE "/tmp/unsafe" */',
        'SELECT 1; /*! COMMIT */',
        'SELECT 1; /*M! COMMIT */',
        "SELECT 'unterminated",
        'SELECT 1 /* unterminated',
        '/* nested /* comment */ SELECT 1 */',
        r"SELECT 'ambiguous\'; COMMIT; -- '",
        '# comment only',
      ]) {
        test('rejects $sql before execution', () async {
          final driver = _Driver(dialect);
          final db = SqlDatabase(driver);
          await expectLater(
            db.transaction((tx) => tx.execute(SqlCommand(sql))),
            throwsA(_code('TRANSACTION.STATEMENT')),
          );
          expect(driver.connection.commands, ['START TRANSACTION', 'ROLLBACK']);
          await db.close();
        });
      }

      test('permits data statements, comments and quoted semicolons', () async {
        final driver = _Driver(dialect);
        final db = SqlDatabase(driver);
        final statements = [
          '/* ordinary */ -- comment\n SELECT 1; # trailing comment',
          "SELECT '; COMMIT', 'it''s fine', `a``;b`, \"a\"\";b\"",
          "SELECT '/*! COMMIT */', '/*M! COMMIT */'",
          'SELECT 1--1',
          'SELECT /*+ MAX_EXECUTION_TIME(1000) */ 1',
          'WITH result AS (SELECT 1 AS n) SELECT n FROM result',
          'INSERT INTO data VALUES (?)',
          'UPDATE data SET id = ?',
          'DELETE FROM data WHERE id = ?',
          'REPLACE INTO data VALUES (?)',
          'SHOW TABLES',
          'DESCRIBE data',
          'DESC data',
          'EXPLAIN SELECT 1',
        ];
        await db.transaction((tx) async {
          for (final sql in statements) {
            await tx.execute(SqlCommand(sql));
          }
        });
        expect(driver.connection.commands, [
          'START TRANSACTION',
          ...statements,
          'COMMIT',
        ]);
        await db.close();
      });

      test('run connections cannot bypass checks or swallow failure', () async {
        final driver = _Driver(dialect);
        final db = SqlDatabase(driver);
        await expectLater(
          db.transaction((tx) async {
            await tx.run((connection) async {
              await expectLater(
                connection.execute(SqlCommand('COMMIT')),
                throwsA(_code('TRANSACTION.STATEMENT')),
              );
            });
          }),
          throwsA(_code('TRANSACTION.FAILED')),
        );
        expect(driver.connection.commands, ['START TRANSACTION', 'ROLLBACK']);
        await db.close();
      });

      test('executeOn cannot bypass checks with a raw connection', () async {
        final driver = _Driver(dialect);
        final db = SqlDatabase(driver);
        await expectLater(
          db.transaction(
            (tx) => tx.executeOn(driver.connection, SqlCommand('COMMIT')),
          ),
          throwsA(_code('TRANSACTION.STATEMENT')),
        );
        expect(driver.connection.commands, ['START TRANSACTION', 'ROLLBACK']);
        await db.close();
      });

      test(
        'cursor entry rejects control SQL before reaching the driver',
        () async {
          final driver = _Driver(dialect);
          final db = SqlDatabase(driver);
          await expectLater(
            db.transaction(
              (tx) => tx.run(
                (connection) => connection.openCursor(SqlCommand('COMMIT')),
              ),
            ),
            throwsA(_code('TRANSACTION.STATEMENT')),
          );
          expect(driver.connection.commands, ['START TRANSACTION', 'ROLLBACK']);
          await db.close();
        },
      );

      test('borrowed transaction connection expires with its owner', () async {
        final driver = _Driver(dialect);
        final db = SqlDatabase(driver);
        late SqlConnection saved;
        await db.transaction(
          (tx) => tx.run((connection) async {
            saved = connection;
            await connection.execute(SqlCommand('SELECT 1'));
          }),
        );
        await expectLater(
          saved.execute(SqlCommand('SELECT 2')),
          throwsA(_code('SESSION.CLOSED')),
        );
        expect(driver.connection.commands, [
          'START TRANSACTION',
          'SELECT 1',
          'COMMIT',
        ]);
        await db.close();
      });
    });
  }

  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    group(
      '$engine real transaction boundary',
      () {
        late SqlDatabase<Backend> db;
        final events = <QueryEvent>[];
        Future<void> insert(SqlDatabase<Backend> session, int id) async {
          await session.execute(
            SqlCommand('INSERT INTO orm_transaction_boundary (id) VALUES (?)', [
              id,
            ]),
          );
        }

        Future<List<Object?>> ids() async => (await db.execute(
          SqlCommand('SELECT id FROM orm_transaction_boundary ORDER BY id'),
        )).rows.map((row) => row.single).toList();
        setUp(() async {
          final Driver<Backend> driver = engine == 'mysql'
              ? await MysqlDriver.open(
                  MysqlOptions(url: Uri.parse(address!), tls: tls),
                )
              : await MariadbDriver.open(
                  MariadbOptions(url: Uri.parse(address!), tls: tls),
                );
          db = SqlDatabase(driver, onQuery: events.add);
          await db.execute(
            SqlCommand('DROP TABLE IF EXISTS orm_transaction_boundary'),
          );
          await db.execute(
            SqlCommand(
              'CREATE TABLE orm_transaction_boundary (id BIGINT PRIMARY KEY) ENGINE=InnoDB',
            ),
          );
          events.clear();
        });
        tearDown(() async {
          await db.execute(
            SqlCommand('DROP TABLE IF EXISTS orm_transaction_boundary'),
          );
          await db.close();
        });

        test('DDL cannot commit previously inserted rows', () async {
          await expectLater(
            db.transaction((tx) async {
              await insert(tx, 1);
              await tx.execute(
                SqlCommand(
                  'ALTER TABLE orm_transaction_boundary ADD COLUMN unsafe INT',
                ),
              );
            }),
            throwsA(_code('TRANSACTION.STATEMENT')),
          );
          expect(await ids(), isEmpty);
          final columns = await db.execute(
            SqlCommand('SHOW COLUMNS FROM orm_transaction_boundary'),
          );
          expect(columns.rows.map((row) => row.first), ['id']);
          expect(events.any((event) => event.error is OrmException), isTrue);
        });

        test('caught raw COMMIT still rolls back the transaction', () async {
          await expectLater(
            db.transaction((tx) async {
              await insert(tx, 1);
              await tx.run((connection) async {
                await expectLater(
                  connection.execute(SqlCommand('COMMIT')),
                  throwsA(_code('TRANSACTION.STATEMENT')),
                );
              });
            }),
            throwsA(_code('TRANSACTION.FAILED')),
          );
          expect(await ids(), isEmpty);
        });

        test(
          'caught driver error through run cannot commit a partial batch',
          () async {
            await expectLater(
              db.transaction((tx) async {
                await insert(tx, 1);
                await tx.run((connection) async {
                  await expectLater(
                    connection.execute(
                      SqlCommand(
                        'INSERT INTO orm_transaction_boundary (id) VALUES (1)',
                      ),
                    ),
                    throwsA(isA<SqlFailure>()),
                  );
                });
              }),
              throwsA(_code('TRANSACTION.FAILED')),
            );
            expect(await ids(), isEmpty);
          },
        );

        test(
          'savepoint rejection rolls back only the child and preserves events',
          () async {
            await db.transaction((tx) async {
              await insert(tx, 1);
              await expectLater(
                tx.savepoint((child) async {
                  await insert(child, 2);
                  await child.run(
                    (connection) =>
                        connection.execute(SqlCommand('SET AUTOCOMMIT = 1')),
                  );
                }),
                throwsA(_code('TRANSACTION.STATEMENT')),
              );
              await tx.savepoint((child) async {
                await insert(child, 3);
                final result = await child.execute(
                  SqlCommand(
                    "/* harmless */ SELECT '; COMMIT', 'it''s safe'; -- done\n",
                  ),
                );
                expect(result.rows.single, ['; COMMIT', "it's safe"]);
              });
            });
            expect(await ids(), [1, 3]);
            expect(
              events.map((event) => event.sql),
              containsAllInOrder([
                'START TRANSACTION',
                'SAVEPOINT orm_sp_0',
                'ROLLBACK TO SAVEPOINT orm_sp_0',
                'RELEASE SAVEPOINT orm_sp_0',
                'SAVEPOINT orm_sp_1',
                'RELEASE SAVEPOINT orm_sp_1',
                'COMMIT',
              ]),
            );
          },
        );
      },
      skip: address == null
          ? 'Set $variable for live database validation.'
          : false,
    );
  }
}

final class _Driver(final SqlDialect dialect) implements Driver<Backend> {
  final connection = _Connection();
  @override
  late final capabilities = Capabilities(
    dialect: dialect,
    maxParameters: 65535,
  );
  @override
  Future<T> run<T>(Future<T> Function(SqlConnection) action) =>
      action(connection);
  @override
  Future<void> close() async {}
}

final class _Connection implements SqlConnection {
  final commands = <String>[];
  @override
  bool? get transactionActive => null;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    commands.add(command.sql);
    return const SqlResult([]);
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => throw StateError(
    'Cursor SQL must be rejected before reaching the driver.',
  );
  @override
  Future<void> invalidate() async {}
}
