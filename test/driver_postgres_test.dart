import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/postgres.dart';
import 'package:test/test.dart';

void main() {
  final socket = Platform.environment['ORM_TEST_POSTGRES_SOCKET'];
  final host = Platform.environment['ORM_TEST_POSTGRES_HOST'];
  final port = int.parse(
    Platform.environment['ORM_TEST_POSTGRES_PORT'] ??
        (socket == null ? '5432' : '55439'),
  );
  final socketPath = socket == null || socket.contains('.s.PGSQL.')
      ? socket
      : '$socket/.s.PGSQL.$port';
  group(
    'real PostgreSQL',
    () {
      late Database database;
      late String table;
      setUp(() async {
        database = openDatabase(
          PostgresDriver(
            Endpoint(
              host: socketPath ?? host!,
              port: port,
              database:
                  Platform.environment['ORM_TEST_POSTGRES_DATABASE'] ??
                  'postgres',
              username:
                  Platform.environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
              password: Platform.environment['ORM_TEST_POSTGRES_PASSWORD'],
              isUnixSocket: socket != null,
            ),
            settings: const PoolSettings(
              sslMode: SslMode.disable,
              maxConnectionCount: 2,
            ),
          ),
        );
        table =
            'orm_driver_entries_${pid}_${DateTime.now().microsecondsSinceEpoch}';
        await database.session.run(
          'CREATE TABLE "$table" (id BIGINT PRIMARY KEY)',
        );
      });
      tearDown(() async {
        await database.session.run('DROP TABLE "$table"');
        await database.close();
      });

      test(
        'native positional parameters preserve supported Dart values',
        () async {
          final recorded = DateTime.parse('2026-10-09T04:05:06.123456+08:00');
          final result = await database.session.run(
            r'SELECT $1 AS number, $2 AS label, $3 AS enabled, $4 AS score, '
            r'$5 AS recorded, $6 AS payload, $7::text AS missing',
            parameters: [
              9007199254740993,
              "O'Reilly",
              true,
              1.25,
              recorded,
              Uint8List.fromList([0, 255]),
              null,
            ],
          );
          expect(result.columns, [
            'number',
            'label',
            'enabled',
            'score',
            'recorded',
            'payload',
            'missing',
          ]);
          expect(result.rows.single, [
            9007199254740993,
            "O'Reilly",
            true,
            1.25,
            recorded.toUtc(),
            Uint8List.fromList([0, 255]),
            null,
          ]);
          expect(
            (await database.session.run(
              'INSERT INTO "$table" VALUES (\$1) RETURNING id',
              parameters: [1],
            )).affectedRows,
            1,
          );
          expect(
            (await database.session.run(
              'UPDATE "$table" SET id = \$1',
              parameters: [2],
            )).affectedRows,
            1,
          );
          await expectLater(
            database.session.run(r'SELECT $1', parameters: [Object()]),
            throwsArgumentError,
          );
        },
      );

      test(
        'direct queued statements capture binary parameters at submission',
        () async {
          final driver = PostgresDriver(
            Endpoint(
              host: socketPath ?? host!,
              port: port,
              database:
                  Platform.environment['ORM_TEST_POSTGRES_DATABASE'] ??
                  'postgres',
              username:
                  Platform.environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
              password: Platform.environment['ORM_TEST_POSTGRES_PASSWORD'],
              isUnixSocket: socket != null,
            ),
            settings: const PoolSettings(
              sslMode: SslMode.disable,
              maxConnectionCount: 1,
            ),
          );
          addTearDown(driver.close);
          await driver.withConnection((connection) async {
            final bytes = Uint8List.fromList([0, 255]);
            final parameters = <Object?>[bytes.asUnmodifiableView()];
            final pending = connection.run(r'SELECT $1::bytea', parameters);
            bytes[0] = 42;
            parameters.clear();
            expect((await pending).rows.single.single, [0, 255]);
            expect(bytes, [42, 255]);
          });
        },
      );

      test(
        'commit and rollback stay on the acquired physical connection',
        () async {
          late Session escaped;
          final ids = <Object?>[];
          await database.transaction((session) async {
            escaped = session;
            ids.add(
              (await session.run('SELECT pg_backend_pid()')).rows.single.single,
            );
            await session.run(
              'INSERT INTO "$table" VALUES (\$1)',
              parameters: [1],
            );
            ids.add(
              (await session.run('SELECT pg_backend_pid()')).rows.single.single,
            );
          });
          expect(ids[0], ids[1]);
          await expectLater(escaped.run('SELECT 1'), throwsStateError);
          final failure = StateError('callback failure');
          await expectLater(
            database.transaction((session) async {
              await session.run(
                'INSERT INTO "$table" VALUES (\$1)',
                parameters: [2],
              );
              throw failure;
            }),
            throwsA(same(failure)),
          );
          expect((await database.session.run('SELECT id FROM "$table"')).rows, [
            [1],
          ]);
        },
      );

      test(
        'all isolation levels and read-only mode are enforced by the server',
        () async {
          for (final isolation in Isolation.values) {
            await database.transaction(
              (session) async {
                expect(
                  (await session.run('SHOW transaction_isolation'))
                      .rows
                      .single
                      .single,
                  switch (isolation) {
                    Isolation.readCommitted => 'read committed',
                    Isolation.repeatableRead => 'repeatable read',
                    Isolation.serializable => 'serializable',
                  },
                );
                expect((await session.run('SHOW transaction_read_only')).rows, [
                  ['on'],
                ]);
              },
              isolation: isolation,
              readOnly: true,
            );
          }
          await expectLater(
            database.transaction((session) async {
              await session.run('INSERT INTO "$table" VALUES (1)');
            }, readOnly: true),
            throwsA(isA<Exception>()),
          );
          await database.session.run('INSERT INTO "$table" VALUES (2)');
        },
      );

      test(
        'pool isolates concurrent root work from an active transaction',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          late Object? transactionBackend;
          final work = database.transaction((session) async {
            transactionBackend = (await session.run('SELECT pg_backend_pid()'))
                .rows
                .single
                .single;
            await session.run('INSERT INTO "$table" VALUES (1)');
            entered.complete();
            await release.future;
          });
          await entered.future;
          final root = await database.session.run(
            'SELECT pg_backend_pid(), COUNT(*) FROM "$table"',
          );
          expect(root.rows.single[0], isNot(transactionBackend));
          expect(root.rows.single[1], 0);
          release.complete();
          await work;
          expect(
            (await database.session.run('SELECT COUNT(*) FROM "$table"')).rows,
            [
              [1],
            ],
          );
        },
      );

      test(
        'raw SET and RESET cannot replace runtime transaction options',
        () async {
          await database.transaction((session) async {
            for (final sql in [
              'SET TRANSACTION READ WRITE',
              'SET /* option */ LOCAL transaction_read_only = off',
              'SET SESSION "transaction_isolation" TO \'read committed\'',
              'SET SESSION CHARACTERISTICS AS TRANSACTION READ WRITE',
              'SET default_transaction_read_only = off',
              'RESET transaction_read_only',
              'RESET default_transaction_isolation',
              'RESET ALL',
            ]) {
              await expectLater(
                session.run(sql),
                throwsArgumentError,
                reason: sql,
              );
            }
            await session.run('SET LOCAL statement_timeout = 5000');
            expect((await session.run('SHOW transaction_read_only')).rows, [
              ['on'],
            ]);
            expect((await session.run('SHOW transaction_isolation')).rows, [
              ['serializable'],
            ]);
          }, readOnly: true);
        },
      );

      test(
        'direct callback rolls back unfinished and chained transactions',
        () async {
          final driver = PostgresDriver(
            Endpoint(
              host: socketPath ?? host!,
              port: port,
              database:
                  Platform.environment['ORM_TEST_POSTGRES_DATABASE'] ??
                  'postgres',
              username:
                  Platform.environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
              password: Platform.environment['ORM_TEST_POSTGRES_PASSWORD'],
              isUnixSocket: socket != null,
            ),
            settings: const PoolSettings(
              sslMode: SslMode.disable,
              maxConnectionCount: 1,
            ),
          );
          addTearDown(driver.close);
          late Connection escaped;
          await driver.withConnection((connection) async {
            escaped = connection;
            await connection.run('/* outer /* nested */ */ BEGIN', const []);
            await connection.run('INSERT INTO "$table" VALUES (1)', const []);
            await expectLater(
              driver.withConnection((_) async {}),
              throwsStateError,
            );
            await expectLater(driver.close(), throwsStateError);
          });
          await expectLater(
            escaped.run('SELECT 1', const []),
            throwsStateError,
          );
          expect(
            (await database.session.run('SELECT * FROM "$table"')).rows,
            isEmpty,
          );
          await driver.withConnection((connection) async {
            await connection.run('START TRANSACTION', const []);
            await connection.run('INSERT INTO "$table" VALUES (2)', const []);
            await connection.run('COMMIT AND CHAIN', const []);
            await connection.run('INSERT INTO "$table" VALUES (3)', const []);
          });
          expect((await database.session.run('SELECT id FROM "$table"')).rows, [
            [2],
          ]);
          await driver.withConnection((connection) async {
            expect(
              (await connection.run(
                'SELECT txid_current_if_assigned()',
                const [],
              )).rows,
              [
                [null],
              ],
            );
          });
        },
      );

      test(
        'caught PostgreSQL statement errors still roll back earlier writes',
        () async {
          await expectLater(
            database.transaction((session) async {
              await session.run('INSERT INTO "$table" VALUES (1)');
              try {
                await session.run('INSERT INTO "$table" VALUES (1)');
              } catch (_) {}
            }),
            throwsA(isA<Exception>()),
          );
          expect(
            (await database.session.run('SELECT * FROM "$table"')).rows,
            isEmpty,
          );
        },
      );

      test(
        'read-write mode explicitly overrides a pooled session default',
        () async {
          final driver = PostgresDriver(
            Endpoint(
              host: socketPath ?? host!,
              port: port,
              database:
                  Platform.environment['ORM_TEST_POSTGRES_DATABASE'] ??
                  'postgres',
              username:
                  Platform.environment['ORM_TEST_POSTGRES_USER'] ?? 'orm_test',
              password: Platform.environment['ORM_TEST_POSTGRES_PASSWORD'],
              isUnixSocket: socket != null,
            ),
            settings: const PoolSettings(
              sslMode: SslMode.disable,
              maxConnectionCount: 1,
            ),
          );
          await driver.withConnection(
            (connection) => connection.run(
              'SET default_transaction_read_only = on',
              const [],
            ),
          );
          final writable = openDatabase(driver);
          addTearDown(writable.close);
          await writable.transaction((session) async {
            expect((await session.run('SHOW transaction_read_only')).rows, [
              ['off'],
            ]);
            await session.run('INSERT INTO "$table" VALUES (4)');
          });
          expect((await database.session.run('SELECT id FROM "$table"')).rows, [
            [4],
          ]);
        },
      );
    },
    skip: socket == null && host == null
        ? 'Set ORM_TEST_POSTGRES_SOCKET or ORM_TEST_POSTGRES_HOST to verify PostgreSQL against a real server.'
        : false,
  );
}
