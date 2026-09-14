import 'dart:async';
import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/tables.dart';

Matcher code(String code) =>
    isA<OrmException>().having((e) => e.code, 'code', code);

void main() {
  runTests(
    'sqlite',
    (observe) => sqlite(const SqliteOptions.memory(), onQuery: observe),
  );
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    runTests('postgres', (observe) async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          schema: 'orm_transaction_tests',
          maxConnections: 1,
        ),
        onQuery: observe,
      );
      await db.execute(
        SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_transaction_tests'),
      );
      return db;
    });
  }
  test(
    'SQLite COMMIT busy is a known rejection followed by verified rollback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orm-commit-busy-',
      );
      final options = SqliteOptions.file(
        '${directory.path}/db.sqlite',
        journal: .delete,
        busyTimeout: const Duration(milliseconds: 40),
      );
      final writer = await sqlite(options), reader = await sqlite(options);
      await createTables(writer);
      await writer.table(users).createRow((u) => [u.email.set('initial')]);
      final entered = Completer<void>(), release = Completer<void>();
      final owner = reader.transaction((tx) async {
        await tx.table(users).count();
        entered.complete();
        await release.future;
      });
      try {
        await entered.future;
        await expectLater(
          writer.transaction((tx) async {
            await tx.table(users).update((u) => [u.score.set(9)]).execute();
          }),
          throwsA(
            isA<SqliteFailure>()
                .having((e) => e.code, 'code', 5)
                .having((e) => e.commitRejected, 'commitRejected', true)
                .having((e) => e.retryTransaction, 'retryTransaction', true),
          ),
        );
        expect((await writer.table(users).single()).score, 0);
        // An actual deadline during the same known rejection remains a timeout,
        // rather than an unknown-commit report.
        await expectLater(
          writer.transaction((tx) async {
            await tx.table(users).update((u) => [u.score.set(9)]).execute();
          }, timeout: const Duration(milliseconds: 20)),
          throwsA(code('TRANSACTION.TIMEOUT')),
        );
        expect((await writer.table(users).single()).score, 0);
      } finally {
        release.complete();
        await owner;
        await reader.close();
        await writer.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'SQLite deadline while BEGIN waits for a writer preserves its connection',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orm-begin-deadline-',
      );
      final options = SqliteOptions.file(
        '${directory.path}/db.sqlite',
        busyTimeout: const Duration(milliseconds: 150),
      );
      final writer = await sqlite(options), blocked = await sqlite(options);
      final entered = Completer<void>(), release = Completer<void>();
      final owner = writer.transaction((tx) async {
        entered.complete();
        await release.future;
      }, options: const SqliteTransaction(mode: .immediate));
      var calls = 0;
      try {
        await entered.future;
        await expectLater(
          blocked.transaction(
            (tx) async {
              calls++;
            },
            options: const SqliteTransaction(mode: .immediate),
            timeout: const Duration(milliseconds: 40),
          ),
          throwsA(code('TRANSACTION.TIMEOUT')),
        ).timeout(const Duration(seconds: 2));
        expect(calls, 0);
        release.complete();
        await owner;
        expect(
          await blocked.transaction(
            (tx) async => (await tx.execute(SqlCommand('SELECT 1'))).rows,
          ),
          [
            [1],
          ],
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await owner;
        await blocked.close();
        await writer.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

void runTests(
  String name,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open,
) {
  group('transaction control $name', () {
    late Database<Backend> db;
    final events = <QueryEvent>[];
    final slow = name == 'postgres'
        ? 'SELECT pg_sleep(10)'
        : 'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n';
    setUp(() async {
      db = await open(events.add);
      await db.execute(SqlCommand('DROP TABLE IF EXISTS children'));
      await db.execute(SqlCommand('DROP TABLE IF EXISTS users'));
      await createTables(db);
      await db.table(users).createRow((u) => [u.email.set('original')]);
      events.clear();
    });
    tearDown(() => db.close());
    Future<int> score() async => (await db.table(users).single()).score;
    Future<void> write(Database<Backend> tx) async {
      await tx.table(users).update((u) => [u.score.set(8)]).execute();
    }

    test(
      'idle callback expires, rolls back and cannot issue late SQL',
      () async {
        final entered = Completer<void>(),
            resume = Completer<void>(),
            finished = Completer<void>();
        Database<Backend>? escaped;
        final future = db.transaction((tx) async {
          escaped = tx;
          await write(tx);
          entered.complete();
          await resume.future;
          try {
            await write(tx);
          } finally {
            finished.complete();
          }
        }, timeout: const Duration(milliseconds: 100));
        final failure = expectLater(
          future,
          throwsA(code('TRANSACTION.TIMEOUT')),
        );
        await entered.future;
        try {
          await failure.timeout(const Duration(seconds: 2));
          expect(await score(), 0);
          expect(
            () => escaped!.execute(SqlCommand('SELECT 1')),
            throwsA(code('SESSION.CLOSED')),
          );
        } finally {
          resume.complete();
          await finished.future;
        }
        expect(await score(), 0);
        expect(events.where((e) => e.sql == 'COMMIT'), isEmpty);
      },
    );

    test(
      'deadline interrupts active SQL before releasing and reusing the lease',
      () async {
        await expectLater(
          db.transaction((tx) async {
            await write(tx);
            await tx.execute(SqlCommand(slow));
          }, timeout: const Duration(milliseconds: 80)),
          throwsA(code('TRANSACTION.TIMEOUT')),
        ).timeout(const Duration(seconds: 3));
        expect(await score(), 0);
        expect(events.any((e) => e.sql == slow && e.error != null), true);
        expect(
          await db.transaction(
            (tx) async => (await tx.execute(SqlCommand('SELECT 2'))).rows,
          ),
          [
            [2],
          ],
        );
      },
    );

    test('interrupted write rolls back and leaves the connection usable', () async {
      final writing = name == 'postgres'
          ? 'UPDATE users SET score = (SELECT 9 FROM pg_sleep(10))'
          : 'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100000000) UPDATE users SET score=(SELECT sum(x) FROM n)';
      await expectLater(
        db.transaction((tx) async {
          await write(tx);
          await tx.execute(SqlCommand(writing));
        }, timeout: const Duration(milliseconds: 80)),
        throwsA(code('TRANSACTION.TIMEOUT')),
      ).timeout(const Duration(seconds: 3));
      expect(await score(), 0);
    });

    test(
      'explicit transaction cancellation stops an idle callback and active SQL',
      () async {
        final token = CancellationToken(),
            entered = Completer<void>(),
            resume = Completer<void>();
        final future = db.transaction((tx) async {
          await write(tx);
          entered.complete();
          await resume.future;
        }, cancellation: token);
        final failure = expectLater(
          future,
          throwsA(code('TRANSACTION.CANCELLED')),
        );
        await entered.future;
        token.cancel();
        try {
          await failure.timeout(const Duration(seconds: 2));
        } finally {
          resume.complete();
        }
        expect(await score(), 0);
        final running = CancellationToken();
        final timer = Timer(const Duration(milliseconds: 80), running.cancel);
        try {
          await expectLater(
            db.transaction((tx) async {
              await write(tx);
              await tx.execute(SqlCommand(slow));
            }, cancellation: running),
            throwsA(code('TRANSACTION.CANCELLED')),
          ).timeout(const Duration(seconds: 3));
        } finally {
          timer.cancel();
        }
        expect(await score(), 0);
      },
    );

    test('global transaction cancellation also abandons acquisition', () async {
      final entered = Completer<void>(), release = Completer<void>();
      final owner = db.session((s) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      var calls = 0;
      final token = CancellationToken();
      final request = db.transaction((tx) async {
        calls++;
      }, cancellation: token);
      final failure = expectLater(
        request,
        throwsA(code('OPERATION.CANCELLED')),
      );
      token.cancel();
      try {
        await failure.timeout(const Duration(seconds: 2));
      } finally {
        release.complete();
        await owner;
      }
      await db.execute(SqlCommand('SELECT 1'));
      expect(calls, 0);
    });

    test(
      'savepoint inherits deadline, drains and rolls back through raw cleanup',
      () async {
        final resume = Completer<void>();
        try {
          await expectLater(
            db.transaction((tx) async {
              await write(tx);
              await tx.savepoint((child) async {
                await child.execute(SqlCommand('SELECT 1'));
                await resume.future;
              });
            }, timeout: const Duration(milliseconds: 100)),
            throwsA(code('TRANSACTION.TIMEOUT')),
          ).timeout(const Duration(seconds: 2));
          expect(await score(), 0);
          expect(
            events.any((e) => e.sql.startsWith('ROLLBACK TO SAVEPOINT')),
            true,
          );
        } finally {
          resume.complete();
        }
      },
    );

    test(
      'deadline closes a paused transactional cursor before rollback',
      () async {
        StreamSubscription<User>? subscription;
        final resume = Completer<void>();
        try {
          await expectLater(
            db.transaction((tx) async {
              await write(tx);
              final first = Completer<void>();
              subscription = tx.table(users).stream(batchSize: 1).listen((row) {
                subscription!.pause();
                first.complete();
              });
              await first.future;
              await resume.future;
            }, timeout: const Duration(milliseconds: 100)),
            throwsA(code('TRANSACTION.TIMEOUT')),
          ).timeout(const Duration(seconds: 2));
          expect(await score(), 0);
        } finally {
          resume.complete();
          await subscription?.cancel();
        }
      },
    );

    test('deadline interrupts an active transactional cursor fetch', () async {
      final expression = sql<int>(
        [name == 'postgres' ? '(SELECT 1 FROM pg_sleep(10))' : '($slow)'],
        [],
        Codecs.integer,
      );
      await expectLater(
        db.transaction((tx) async {
          await write(tx);
          await tx
              .table(users)
              .select((u) => expression)
              .stream(batchSize: 1)
              .toList();
        }, timeout: const Duration(milliseconds: 80)),
        throwsA(code('TRANSACTION.TIMEOUT')),
      ).timeout(const Duration(seconds: 3));
      expect(await score(), 0);
    });

    test('transaction clock starts after acquisition and a borrowed session recovers', () async {
      final entered = Completer<void>(), release = Completer<void>();
      final owner = db.session((s) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final result = db.transaction(
        (tx) async => (await tx.execute(SqlCommand('SELECT 1'))).rows,
        timeout: const Duration(milliseconds: 100),
        acquire: const AcquisitionOptions(timeout: Duration(seconds: 2)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      release.complete();
      await owner;
      expect(await result, [
        [1],
      ]);
      await db.session((session) async {
        final resume = Completer<void>();
        try {
          await expectLater(
            session.transaction((tx) async {
              await write(tx);
              await resume.future;
            }, timeout: const Duration(milliseconds: 50)),
            throwsA(code('TRANSACTION.TIMEOUT')),
          );
          expect((await session.table(users).single()).score, 0);
        } finally {
          resume.complete();
        }
      });
    });

    test(
      'failed rollback is explicit and discards an uncertain connection',
      () async {
        final driver = _AfterCommitDriver(db.driver, () {})
          ..before = (command) {
            if (command.sql == 'ROLLBACK') {
              throw StateError('Rollback transport failed');
            }
          };
        final hooked = Database(driver);
        await expectLater(
          hooked.transaction((tx) async {
            await write(tx);
            throw StateError('Original callback failure');
          }),
          throwsA(code('TRANSACTION.ROLLBACK')),
        );
        expect(driver.discards, 1);
        if (name == 'postgres') {
          expect(await score(), 0);
        } else {
          await expectLater(
            db.table(users).count(),
            throwsA(code('DRIVER.CLOSED')),
          );
        }
      },
    );

    test(
      'transaction controls reject adapters without actual cancellation',
      () {
        final driver = _AfterCommitDriver(db.driver, () {})
          ..supportsCancellation = false;
        final hooked = Database(driver);
        expect(
          () => hooked.transaction(
            (tx) async {},
            timeout: const Duration(seconds: 1),
          ),
          throwsA(code('CAPABILITY.CANCEL')),
        );
        expect(events, isEmpty);
      },
    );

    test('shorter statement limit retains its error and rolls back the transaction', () async {
      await expectLater(
        db.transaction((tx) async {
          await write(tx);
          await tx.execute(
            SqlCommand(slow),
            options: const ExecutionOptions(
              timeout: Duration(milliseconds: 40),
            ),
          );
        }, timeout: const Duration(seconds: 2)),
        throwsA(code('OPERATION.TIMEOUT')),
      );
      expect(await score(), 0);
    });

    test(
      'monotonic deadline prevents commit after a CPU-bound callback',
      () async {
        await expectLater(
          db.transaction((tx) async {
            final busy = Stopwatch()..start();
            while (busy.elapsed < const Duration(milliseconds: 150)) {}
          }, timeout: const Duration(milliseconds: 100)),
          throwsA(code('TRANSACTION.TIMEOUT')),
        );
        expect(events.where((e) => e.sql == 'COMMIT'), isEmpty);
      },
    );

    test(
      'completed scopes remove their timers and cancellation listeners',
      () async {
        final token = CancellationToken();
        await db.transaction(
          (tx) async {
            await write(tx);
          },
          timeout: const Duration(milliseconds: 100),
          cancellation: token,
        );
        token.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(await score(), 8);
        await db.transaction((tx) async {
          await tx.table(users).update((u) => [u.score.increment(1)]).execute();
        });
        expect(await score(), 9);
      },
    );

    test('confirmed commit wins a cancellation race; lost acknowledgement stays unknown', () async {
      final token = CancellationToken();
      final driver = _AfterCommitDriver(db.driver, () => token.cancel());
      final hooked = Database(driver);
      await hooked.transaction((tx) async {
        await write(tx);
      }, cancellation: token);
      expect(await score(), 8);
      driver.after = () => throw StateError('Lost COMMIT acknowledgement');
      await expectLater(
        hooked.transaction((tx) async {
          await tx.table(users).update((u) => [u.score.set(12)]).execute();
        }),
        throwsA(code('TRANSACTION.COMMIT')),
      );
      expect(await score(), 12);
    });

    test(
      'deferred constraint rejection at COMMIT is a known failure',
      () async {
        await db.execute(
          SqlCommand(
            'CREATE TABLE children (id INTEGER PRIMARY KEY, user_id BIGINT REFERENCES users(id) DEFERRABLE INITIALLY DEFERRED)',
          ),
        );
        await expectLater(
          db.transaction((tx) async {
            await tx.execute(
              SqlCommand('INSERT INTO children(id, user_id) VALUES (1, 99)'),
            );
          }),
          throwsA(
            isA<SqlFailure>()
                .having((e) => e.commitRejected, 'commitRejected', true)
                .having((e) => e.retryTransaction, 'retryTransaction', false),
          ),
        );
        expect(
          (await db.execute(SqlCommand('SELECT count(*) FROM children'))).rows,
          [
            [0],
          ],
        );
      },
    );

    test('invalid deadlines and already cancelled tokens never begin a transaction', () {
      expect(
        () => db.transaction((tx) async {}, timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => db.transaction(
          (tx) async {},
          cancellation: CancellationToken()..cancel(),
        ),
        throwsA(code('TRANSACTION.CANCELLED')),
      );
      expect(events, isEmpty);
    });

    if (name == 'postgres') {
      Future<Database<Postgres>> concurrent() async => postgres(
        PostgresOptions(
          url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
          tls: .disable,
          schema: 'orm_transaction_tests',
          maxConnections: 1,
        ),
      );
      test(
        'SQLSTATE 40003 at COMMIT is never classified as a confirmed rejection',
        () async {
          await db.execute(
            SqlCommand(
              r"CREATE OR REPLACE FUNCTION uncertain_commit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'uncertain result' USING ERRCODE = '40003'; END $$",
            ),
          );
          await db.execute(
            SqlCommand(
              'CREATE CONSTRAINT TRIGGER uncertain AFTER UPDATE ON users DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION uncertain_commit()',
            ),
          );
          await expectLater(
            db.transaction(write),
            throwsA(code('TRANSACTION.COMMIT')),
          );
          expect(await score(), 0);
        },
      );

      test(
        'real PostgreSQL serialization failure is classified after rollback',
        () async {
          final other = await concurrent();
          try {
            await expectLater(
              db.transaction(
                (tx) async {
                  await tx.table(users).single();
                  await other
                      .table(users)
                      .update((u) => [u.score.set(9)])
                      .execute();
                  await tx
                      .table(users)
                      .update((u) => [u.score.set(1)])
                      .execute();
                },
                options: const PostgresTransaction(isolation: .repeatableRead),
              ),
              throwsA(
                isA<PostgresFailure>()
                    .having((e) => e.code, 'SQLSTATE', '40001')
                    .having(
                      (e) => e.retryTransaction,
                      'retryTransaction',
                      true,
                    ),
              ),
            );
            expect(await score(), 9);
          } finally {
            await other.close();
          }
        },
      );
      test(
        'real PostgreSQL deadlock rolls back exactly one transaction',
        () async {
          final other = await concurrent();
          await db.table(users).createRow((u) => [u.email.set('second')]);
          final firstReady = Completer<void>(), secondReady = Completer<void>();
          Future<Object> attempt(
            Database<Backend> source,
            int first,
            int second,
            Completer<void> own,
            Completer<void> peer,
          ) async {
            try {
              await source.transaction((tx) async {
                await tx
                    .table(users)
                    .where((u) => u.id.eq(first))
                    .update((u) => [u.score.increment(1)])
                    .execute();
                own.complete();
                await peer.future;
                await tx
                    .table(users)
                    .where((u) => u.id.eq(second))
                    .update((u) => [u.score.increment(1)])
                    .execute();
              });
              return 'committed';
            } catch (error) {
              return error;
            }
          }

          try {
            final outcomes = await Future.wait([
              attempt(db, 1, 2, firstReady, secondReady),
              attempt(other, 2, 1, secondReady, firstReady),
            ]).timeout(const Duration(seconds: 5));
            expect(outcomes.whereType<String>(), ['committed']);
            final error = outcomes.whereType<PostgresFailure>().single;
            expect(error.code, '40P01');
            expect(error.retryTransaction, true);
            expect(await db.table(users).select((u) => u.score).get(), [1, 1]);
          } finally {
            await other.close();
          }
        },
      );
    }

    if (name == 'sqlite') {
      for (final nested in [false, true]) {
        test(
          'automatic SQLite rollback prevents late autocommit writes, nested=$nested',
          () async {
            await expectLater(
              db.transaction((tx) async {
                await write(tx);
                Future<void> fail(Database<Backend> scope) => scope
                    .execute(
                      SqlCommand(
                        "INSERT OR ROLLBACK INTO users(email) VALUES ('original')",
                      ),
                    )
                    .then((_) {});
                try {
                  if (nested) {
                    await tx.savepoint(fail);
                  } else {
                    await fail(tx);
                  }
                } on SqliteFailure {
                  /* The application catches the statement error. */
                }
                expect(
                  () => tx.execute(
                    SqlCommand(
                      "INSERT INTO users(email) VALUES ('must-not-commit')",
                    ),
                  ),
                  throwsA(code('TRANSACTION.ENDED')),
                );
              }),
              throwsA(code('TRANSACTION.FAILED')),
            );
            expect(await score(), 0);
            expect(events.where((e) => e.sql == 'ROLLBACK'), isEmpty);
          },
        );
      }
    }
  });
}

final class _AfterCommitDriver(final Driver<Backend> source, this.after)
    implements Driver<Backend> {
  void Function() after;
  void Function(SqlCommand)? before;
  bool supportsCancellation = true;
  int discards = 0;
  @override
  Capabilities get capabilities => supportsCancellation
      ? source.capabilities
      : Capabilities(
          dialect: source.capabilities.dialect,
          maxParameters: source.capabilities.maxParameters,
        );
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      source.run((c) => action(_AfterCommitConnection(c, this)));
  @override
  Future<void> close() => source.close();
}

final class _AfterCommitConnection(
  final SqlConnection inner,
  final _AfterCommitDriver driver,
) implements SqlConnection {
  @override
  bool? get transactionActive => inner.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    driver.before?.call(command);
    final result = await inner.execute(command, options: options);
    if (command.sql == 'COMMIT') driver.after();
    return result;
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => inner.openCursor(command, options: options);
  @override
  Future<void> invalidate() {
    driver.discards++;
    return inner.invalidate();
  }
}
