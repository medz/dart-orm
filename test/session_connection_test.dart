import 'dart:async';
import 'dart:io';

import 'package:orm/drivers/postgres.dart';
import 'package:orm/drivers/sqlite.dart';
import 'package:orm/runtime.dart';
import 'package:test/test.dart';

Matcher _code(String code) =>
    isA<OrmException>().having((error) => error.code, 'code', code);

void main() {
  for (final engine in ['sqlite', 'postgres']) {
    final address = Platform.environment['ORM_TEST_POSTGRES'];
    group(
      '$engine owned session connections',
      () {
        late SqlDatabase<Backend> db;
        final schema = 'orm_session_connections_$pid';
        setUp(() async {
          db = SqlDatabase(
            engine == 'sqlite'
                ? await SqliteDriver.open(const SqliteOptions.memory())
                : PostgresDriver(
                    PostgresOptions(
                      url: Uri.parse(address!),
                      tls: .disable,
                      schema: schema,
                    ),
                  ),
          );
          if (engine == 'postgres') {
            await db.execute(
              SqlCommand('CREATE SCHEMA IF NOT EXISTS "$schema"'),
            );
          }
          await db.execute(
            SqlCommand('CREATE TABLE session_items (id BIGINT PRIMARY KEY)'),
          );
        });
        tearDown(() async {
          try {
            if (engine == 'postgres') {
              await db.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
            }
          } finally {
            await db.close();
          }
        });
        Future<List<Object?>> ids() async => (await db.execute(
          SqlCommand('SELECT id FROM session_items ORDER BY id'),
        )).rows.map((row) => row.single).toList();

        test(
          'borrowed session connections expire with their callback',
          () async {
            late SqlConnection saved;
            await db.session(
              (session) => session.run((connection) async {
                saved = connection;
              }),
            );
            await expectLater(
              saved.execute(SqlCommand('INSERT INTO session_items VALUES (1)')),
              throwsA(_code('SESSION.CLOSED')),
            );
            expect(await ids(), isEmpty);
          },
        );

        for (final rollback in [false, true]) {
          test(
            'savepoint connection expires after ${rollback ? 'rollback' : 'release'}',
            () async {
              late SqlConnection saved;
              await db.transaction((tx) async {
                try {
                  await tx.savepoint(
                    (child) => child.run((connection) async {
                      saved = connection;
                      if (rollback) {
                        await connection.execute(
                          SqlCommand('INSERT INTO session_items VALUES (1)'),
                        );
                        throw StateError('rollback child');
                      }
                    }),
                  );
                } on StateError catch (_) {}
                await expectLater(
                  saved.execute(
                    SqlCommand('INSERT INTO session_items VALUES (2)'),
                  ),
                  throwsA(_code('SESSION.CLOSED')),
                );
                await tx.execute(
                  SqlCommand('INSERT INTO session_items VALUES (3)'),
                );
              });
              expect(await ids(), [3]);
            },
          );
        }

        test(
          'expired executeOn rejects an otherwise active physical lease',
          () async {
            late SqlDatabase<Backend> expired;
            await db.session((session) async {
              await session.transaction((tx) async {
                expired = tx;
              });
              await session.run((connection) async {
                await expectLater(
                  Future.sync(
                    () => expired.executeOn(
                      connection,
                      SqlCommand('INSERT INTO session_items VALUES (1)'),
                    ),
                  ),
                  throwsA(_code('SESSION.CLOSED')),
                );
              });
            });
            expect(await ids(), isEmpty);
          },
        );

        test(
          'escaped parent connection cannot cross an active savepoint',
          () async {
            late SqlConnection parent;
            await db.transaction((tx) async {
              await tx.run((connection) async {
                parent = connection;
              });
              await tx.savepoint((child) async {
                await expectLater(
                  parent.execute(
                    SqlCommand('INSERT INTO session_items VALUES (1)'),
                  ),
                  throwsA(_code('SESSION.SAVEPOINT')),
                );
                await expectLater(
                  Future.sync(
                    () => tx.executeOn(
                      parent,
                      SqlCommand('INSERT INTO session_items VALUES (2)'),
                    ),
                  ),
                  throwsA(_code('SESSION.SAVEPOINT')),
                );
                await child.execute(
                  SqlCommand('INSERT INTO session_items VALUES (3)'),
                );
              });
            });
            expect(await ids(), [3]);
          },
        );

        test(
          'executeOn refuses a connection outside its transaction',
          () async {
            final foreign = _Connection();
            await db.transaction((tx) async {
              await expectLater(
                Future.sync(
                  () => tx.executeOn(
                    foreign,
                    SqlCommand('INSERT INTO session_items VALUES (1)'),
                  ),
                ),
                throwsA(_code('SESSION.CONNECTION')),
              );
              await tx.execute(
                SqlCommand('INSERT INTO session_items VALUES (2)'),
              );
            });
            expect(foreign.commands, isEmpty);
            expect(await ids(), [2]);
          },
        );

        test(
          'caught raw statement errors cannot turn rollback into success',
          () async {
            await expectLater(
              db.transaction((tx) async {
                await tx.execute(
                  SqlCommand('INSERT INTO session_items VALUES (1)'),
                );
                await tx.run((connection) async {
                  try {
                    await connection.execute(
                      SqlCommand('INSERT INTO session_items VALUES (1)'),
                    );
                  } catch (_) {}
                });
              }),
              throwsA(_code('TRANSACTION.FAILED')),
            );
            expect(await ids(), isEmpty);
          },
        );

        test(
          'unclosed raw cursor is drained and expires before rollback',
          () async {
            late SqlCursor cursor;
            await expectLater(
              db.transaction(
                (tx) => tx.run((connection) async {
                  cursor = await connection.openCursor(
                    SqlCommand('SELECT id FROM session_items'),
                  );
                }),
              ),
              throwsA(_code('TRANSACTION.UNAWAITED')),
            );
            await expectLater(
              cursor.fetch(1),
              throwsA(_code('SESSION.CLOSED')),
            );
            await cursor.close();
            expect(await ids(), isEmpty);
          },
        );
      },
      skip: engine == 'postgres' && address == null
          ? 'Set ORM_TEST_POSTGRES for PostgreSQL scope checks.'
          : false,
      tags: engine,
    );
  }

  for (final useExecuteOn in [false, true]) {
    test(
      'unawaited ${useExecuteOn ? 'executeOn' : 'run connection'} work drains before rollback',
      () async {
        final driver = _Driver();
        final db = SqlDatabase(driver);
        final pending = db.transaction((tx) async {
          if (useExecuteOn) {
            unawaited(
              tx.executeOn(driver.connection, SqlCommand('UPDATE blocked')),
            );
          } else {
            await tx.run((connection) async {
              unawaited(connection.execute(SqlCommand('UPDATE blocked')));
            });
          }
        });
        final failure = expectLater(
          pending,
          throwsA(_code('TRANSACTION.UNAWAITED')),
        );
        await driver.connection.started.future;
        await Future<void>.delayed(Duration.zero);
        expect(driver.connection.commands, ['BEGIN', 'UPDATE blocked']);
        driver.connection.finished.complete(
          const SqlResult([], affectedRows: 1),
        );
        await failure;
        expect(driver.connection.commands, [
          'BEGIN',
          'UPDATE blocked',
          'ROLLBACK',
        ]);
        await db.close();
      },
    );
  }
}

final class _Driver implements Driver<Postgres> {
  final connection = _Connection();
  @override
  Capabilities get capabilities =>
      const Capabilities(dialect: SqlDialect.postgres, maxParameters: 999);
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      action(connection);
  @override
  Future<void> close() async {}
}

final class _Connection implements SqlConnection {
  final commands = <String>[];
  final started = Completer<void>();
  final finished = Completer<SqlResult>();
  @override
  bool? get transactionActive => null;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    commands.add(command.sql);
    if (command.sql == 'UPDATE blocked') {
      started.complete();
      return finished.future;
    }
    return const SqlResult([]);
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => throw UnsupportedError('No test cursor.');
  @override
  Future<void> invalidate() async {}
}
