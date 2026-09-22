@Tags(['mysql-suite'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:orm/drivers/mysql.dart';
import 'package:orm/drivers/mariadb.dart' as maria;
import 'package:test/test.dart';

Matcher _code(String code) =>
    isA<OrmException>().having((error) => error.code, 'code', code);

void main() {
  test('connection options fail before opening a socket', () async {
    for (final url in [
      'postgres://user:pass@localhost/db',
      'mysql://localhost/db',
      'mysql://user:pass@localhost/',
      'mysql://user:pass@localhost/db?tls=false',
      'mysql://user:pass@localhost/db#fragment',
    ]) {
      await expectLater(
        MysqlDriver.open(MysqlOptions(url: Uri.parse(url))),
        throwsArgumentError,
      );
    }
    await expectLater(
      MysqlDriver.open(
        MysqlOptions(
          url: Uri.parse('mysql://user:pass@localhost/db'),
          queryTimeout: Duration.zero,
        ),
      ),
      throwsArgumentError,
    );
  });

  for (final engine in ['mysql', 'mariadb']) {
    final variable = 'ORM_TEST_${engine.toUpperCase()}';
    final address = Platform.environment[variable];
    final tls = MysqlTls.values.byName(
      Platform.environment['${variable}_TLS'] ?? 'verifyFull',
    );
    Future<Driver<Backend>> open() async {
      final url = Uri.parse(address!);
      return engine == 'mysql'
          ? await MysqlDriver.open(MysqlOptions(url: url, tls: tls))
          : await maria.MariadbDriver.open(
              maria.MariadbOptions(url: url, tls: tls),
            );
    }

    group(
      engine,
      () {
        late Driver<Backend> driver;
        setUp(() async => driver = await open());
        tearDown(() => driver.close());

        test(
          'trailing delimiters preserve result rows and literal semicolons',
          () async {
            await driver.run((connection) async {
              for (final tail in [
                ';',
                '; -- done\n',
                '; # done\n',
                '; /* done ; */',
                '; /* first */ -- second\n',
              ]) {
                final plain = await connection.execute(
                  SqlCommand(
                    "/* harmless */ SELECT '; COMMIT', 'it''s safe'$tail",
                  ),
                );
                expect(plain.rows, [
                  ['; COMMIT', "it's safe"],
                ]);
                final prepared = await connection.execute(
                  SqlCommand('SELECT ? AS `value;name`$tail', [
                    'literal; -- text',
                  ]),
                );
                expect(prepared.rows, [
                  ['literal; -- text'],
                ]);
                expect(prepared.columns, ['value;name']);
              }
            });
          },
        );

        test('declares actual engine and unsupported operations', () async {
          expect(driver.capabilities.dialect.name, engine);
          expect(driver.capabilities.returning, isFalse);
          expect(driver.capabilities.streaming, isFalse);
          expect(driver.capabilities.cancellation, isFalse);
          expect(driver.capabilities.statementTimeout, isTrue);
          expect(driver.capabilities.exactDecimal, isTrue);
          expect(driver.capabilities.temporal, isTrue);
          await driver.run((connection) async {
            expect(connection.transactionActive, isNull);
            await expectLater(
              connection.openCursor(SqlCommand('SELECT 1')),
              throwsA(_code('CAPABILITY.STREAMING')),
            );
            await expectLater(
              connection.execute(
                SqlCommand('SELECT 1'),
                options: ExecutionOptions(cancellation: CancellationToken()),
              ),
              throwsA(_code('CAPABILITY.CANCELLATION')),
            );
            final result = await connection.execute(
              SqlCommand('SELECT @@session.sql_mode, @@session.time_zone'),
            );
            expect(result.rows.single[1], '+00:00');
            final modes = (result.rows.single[0] as String).split(',');
            expect(
              modes,
              containsAll([
                'ANSI_QUOTES',
                'STRICT_ALL_TABLES',
                'NO_BACKSLASH_ESCAPES',
              ]),
            );
          });
        });

        test(
          'binary-collated text stays UTF-8 in both wire protocols',
          () async {
            await driver.run((connection) async {
              await connection.execute(
                SqlCommand(
                  'CREATE TEMPORARY TABLE binary_text (name VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin, bytes BLOB)',
                ),
              );
              final bytes = Uint8List.fromList([0, 128, 255]);
              await connection.execute(
                SqlCommand('INSERT INTO binary_text VALUES (?, ?)', [
                  '雪',
                  bytes,
                ]),
              );
              for (final command in [
                SqlCommand('SELECT name, bytes FROM binary_text'),
                SqlCommand(
                  'SELECT name, bytes FROM binary_text WHERE name = ?',
                  ['雪'],
                ),
              ]) {
                final row = (await connection.execute(command)).rows.single;
                expect(row[0], '雪');
                expect(row[1], bytes);
              }
            });
          },
        );

        test(
          'prepared values preserve text, signed integers and binary bytes',
          () async {
            await driver.run((connection) async {
              await connection.execute(
                SqlCommand(
                  'CREATE TEMPORARY TABLE driver_values ('
                  'id BIGINT PRIMARY KEY AUTO_INCREMENT, '
                  'body TEXT NOT NULL, enabled BOOLEAN NOT NULL, '
                  'large BIGINT NOT NULL, small TINYINT NOT NULL, '
                  'bytes BLOB NOT NULL, optional TEXT)',
                ),
              );
              const text =
                  "quote' ? :named \\ newline\n雪; DROP TABLE driver_values";
              final bytes = Uint8List.fromList([0, 1, 127, 128, 255, 0]);
              final inserted = await connection.execute(
                SqlCommand(
                  'INSERT INTO driver_values (body, enabled, large, small, bytes, optional) '
                  'VALUES (?, ?, ?, ?, ?, ?)',
                  [text, true, 9223372036854775807, -128, bytes, null],
                ),
              );
              expect(inserted.affectedRows, 1);
              expect(inserted.lastInsertId, 1);
              final selected = await connection.execute(
                SqlCommand(
                  'SELECT body, enabled, large, small, bytes, optional '
                  'FROM driver_values WHERE id = ?',
                  [inserted.lastInsertId],
                ),
              );
              expect(selected.columns, [
                'body',
                'enabled',
                'large',
                'small',
                'bytes',
                'optional',
              ]);
              expect(selected.rows.single, [
                text,
                1,
                9223372036854775807,
                -128,
                bytes,
                null,
              ]);
              expect(Codecs.boolean.decode(selected.rows.single[1]), isTrue);
              final updated = await connection.execute(
                SqlCommand(
                  'UPDATE driver_values SET enabled = ? WHERE id = ?',
                  [false, 1],
                ),
              );
              expect(updated.affectedRows, 1);
            });
          },
        );

        test(
          'decimals and temporal microseconds round trip without doubles',
          () async {
            await driver.run((connection) async {
              await connection.execute(
                SqlCommand(
                  'CREATE TEMPORARY TABLE driver_precision ('
                  'amount DECIMAL(65,30), day DATE, clock TIME(6), '
                  'local_time DATETIME(6), instant DATETIME(6))',
                ),
              );
              final amount = Decimal.parse(
                '123456789012345678901234567890.123456789012345678901234567891',
              );
              final day = LocalDate(2026, 9, 19);
              final time = LocalTime(12, 34, 56, 1);
              final local = LocalDateTime(day, time);
              final instant = DateTime.utc(2026, 9, 19, 12, 34, 56, 0, 1);
              await connection.execute(
                SqlCommand(
                  'INSERT INTO driver_precision VALUES (?, ?, ?, ?, ?)',
                  [amount, day, time, local, instant],
                ),
              );
              final result = await connection.execute(
                SqlCommand('SELECT * FROM driver_precision WHERE amount = ?', [
                  amount,
                ]),
              );
              final row = result.rows.single;
              expect(Codecs.decimal.decode(row[0]), amount);
              expect(Codecs.date.decode(row[1]), day);
              expect(Codecs.time.decode(row[2]), time);
              expect(Codecs.localDateTime.decode(row[3]), local);
              expect(Codecs.dateTime.decode(row[4]), instant);
              expect(row[2], '12:34:56.000001');
            });
          },
        );

        test(
          'JSON text projections distinguish SQL null and all JSON values',
          () async {
            await driver.run((connection) async {
              await connection.execute(
                SqlCommand(
                  'CREATE TEMPORARY TABLE driver_json (id INTEGER PRIMARY KEY, document JSON)',
                ),
              );
              final values = [
                const SqlJson({
                  'number': 1,
                  'nested': [true, null],
                }),
                const SqlJson('a JSON string'),
                const SqlJson(null),
              ];
              for (var i = 0; i < values.length; i++) {
                await connection.execute(
                  SqlCommand('INSERT INTO driver_json VALUES (?, ?)', [
                    i,
                    values[i],
                  ]),
                );
              }
              await connection.execute(
                SqlCommand('INSERT INTO driver_json VALUES (?, ?)', [3, null]),
              );
              final result = await connection.execute(
                SqlCommand(
                  'SELECT CAST(document AS CHAR CHARACTER SET utf8mb4) '
                  'FROM driver_json ORDER BY id',
                ),
              );
              for (var i = 0; i < values.length; i++) {
                expect(
                  Codecs.jsonDocument.decode(result.rows[i][0]).value,
                  values[i].value,
                );
              }
              expect(result.rows[3][0], isNull);
            });
          },
        );

        test('commits persist, rollbacks and abandoned transactions do not', () async {
          await driver.run((connection) async {
            await connection.execute(
              SqlCommand(
                'CREATE TEMPORARY TABLE driver_transactions (id INTEGER PRIMARY KEY) ENGINE=InnoDB',
              ),
            );
            await connection.execute(SqlCommand('START TRANSACTION'));
            await connection.execute(
              SqlCommand('INSERT INTO driver_transactions VALUES (1)'),
            );
            await connection.execute(SqlCommand('COMMIT'));
            await connection.execute(SqlCommand('START TRANSACTION'));
            await connection.execute(
              SqlCommand('INSERT INTO driver_transactions VALUES (2)'),
            );
            await connection.execute(SqlCommand('ROLLBACK'));
            await connection.execute(SqlCommand('START TRANSACTION'));
            await connection.execute(
              SqlCommand('INSERT INTO driver_transactions VALUES (3)'),
            );
            // A raw caller forgot its rollback. Lease release must perform it.
          });
          final result = await driver.run(
            (connection) => connection.execute(
              SqlCommand('SELECT id FROM driver_transactions ORDER BY id'),
            ),
          );
          expect(result.rows, [
            [1],
          ]);
        });

        test('savepoints roll back only their own writes', () async {
          await driver.run((connection) async {
            await connection.execute(
              SqlCommand(
                'CREATE TEMPORARY TABLE driver_savepoint (id INTEGER) ENGINE=InnoDB',
              ),
            );
            await connection.execute(SqlCommand('START TRANSACTION'));
            await connection.execute(
              SqlCommand('INSERT INTO driver_savepoint VALUES (1)'),
            );
            await connection.execute(SqlCommand('SAVEPOINT nested'));
            await connection.execute(
              SqlCommand('INSERT INTO driver_savepoint VALUES (2)'),
            );
            await connection.execute(
              SqlCommand('ROLLBACK TO SAVEPOINT nested'),
            );
            await connection.execute(SqlCommand('RELEASE SAVEPOINT nested'));
            await connection.execute(SqlCommand('COMMIT'));
            expect(
              (await connection.execute(
                SqlCommand('SELECT id FROM driver_savepoint'),
              )).rows,
              [
                [1],
              ],
            );
          });
        });

        test('a server rejection preserves its numeric code and recovers', () async {
          await driver.run((connection) async {
            await connection.execute(
              SqlCommand(
                'CREATE TEMPORARY TABLE driver_unique (id INTEGER PRIMARY KEY)',
              ),
            );
            await connection.execute(
              SqlCommand('INSERT INTO driver_unique VALUES (?)', [1]),
            );
            await expectLater(
              connection.execute(
                SqlCommand('INSERT INTO driver_unique VALUES (?)', [1]),
              ),
              throwsA(
                isA<MysqlFailure>().having((error) => error.code, 'code', 1062),
              ),
            );
            expect(
              (await connection.execute(
                SqlCommand('SELECT COUNT(*) FROM driver_unique'),
              )).rows,
              [
                [1],
              ],
            );
          });
        });

        test(
          'whole leases serialize, all close callers wait for accepted work',
          () async {
            final entered = Completer<void>(), release = Completer<void>();
            final events = <String>[];
            final first = driver.run((connection) async {
              events.add('first');
              entered.complete();
              await release.future;
              await connection.execute(SqlCommand('SELECT 1'));
              events.add('first done');
            });
            await entered.future;
            final second = driver.run((connection) async {
              events.add('second');
              await connection.execute(SqlCommand('SELECT 2'));
            });
            final close = driver.close();
            expect(identical(close, driver.close()), isTrue);
            var closed = false;
            close.then((_) => closed = true);
            await Future<void>.delayed(Duration.zero);
            expect(events, ['first']);
            expect(closed, isFalse);
            await expectLater(
              driver.run((_) async {}),
              throwsA(_code('DRIVER.CLOSED')),
            );
            release.complete();
            await Future.wait([first, second, close]);
            expect(events, ['first', 'first done', 'second']);
          },
        );

        test(
          'escaped leases cannot execute or discard a later lease',
          () async {
            late SqlConnection escaped;
            await driver.run((connection) async => escaped = connection);
            await expectLater(
              escaped.execute(SqlCommand('SELECT 1')),
              throwsA(_code('SESSION.CLOSED')),
            );
            await escaped.invalidate();
            expect(
              (await driver.run(
                (connection) => connection.execute(SqlCommand('SELECT 2')),
              )).rows,
              [
                [2],
              ],
            );
          },
        );

        test('connection invalidation prevents reuse', () async {
          await driver.run((connection) => connection.invalidate());
          await expectLater(
            driver.run((_) async {}),
            throwsA(_code('DRIVER.CLOSED')),
          );
        });

        test(
          'timed-out statements discard the connection instead of reusing it',
          () async {
            await expectLater(
              driver.run(
                (connection) => connection.execute(
                  SqlCommand('SELECT SLEEP(0.25)'),
                  options: const ExecutionOptions(
                    timeout: Duration(milliseconds: 20),
                  ),
                ),
              ),
              throwsA(_code('OPERATION.TIMEOUT')),
            );
            await expectLater(
              driver.run((_) async {}),
              throwsA(_code('DRIVER.CLOSED')),
            );
            final fresh = await open();
            try {
              expect(
                (await fresh.run(
                  (connection) => connection.execute(SqlCommand('SELECT 1')),
                )).rows,
                [
                  [1],
                ],
              );
            } finally {
              await fresh.close();
            }
          },
        );

        test('the wrong engine is rejected before use', () async {
          final url = Uri.parse(address!);
          await expectLater(
            engine == 'mysql'
                ? maria.MariadbDriver.open(
                    maria.MariadbOptions(url: url, tls: tls),
                  )
                : MysqlDriver.open(
                    MysqlOptions(
                      url: url.replace(scheme: 'mysql'),
                      tls: tls,
                    ),
                  ),
            throwsA(_code('DRIVER.ENGINE')),
          );
        });
      },
      skip: address == null
          ? 'Set $variable to run against a real $engine server.'
          : false,
      tags: engine,
    );
  }
}
