import 'dart:async';
import 'dart:io';

import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/tables.dart';

Matcher code(String code) =>
    isA<OrmException>().having((e) => e.code, 'code', code);
const retry = TransactionRetry(delay: Duration.zero);

void main() {
  runTests('sqlite', () => sqlite(const SqliteOptions.memory()));
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url != null) {
    runTests('postgres', () async {
      final db = postgres(
        PostgresOptions(
          url: Uri.parse(url),
          tls: .disable,
          schema: 'orm_retry_tests',
          maxConnections: 1,
        ),
      );
      await db.execute(
        SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_retry_tests'),
      );
      return db;
    });
  }
  test('SQLite WAL snapshot conflict replays reads after rollback', () async {
    final directory = await Directory.systemTemp.createTemp(
      'orm-retry-snapshot-',
    );
    final options = SqliteOptions.file('${directory.path}/db.sqlite');
    final base = await sqlite(options), other = await sqlite(options);
    final errors = <SqliteFailure>[];
    final db = Database(
      base.driver,
      onQuery: (event) {
        if (event.error case final SqliteFailure failure) errors.add(failure);
      },
    );
    try {
      await createTables(db);
      await db.table(users).createRow((u) => [u.email.set('initial')]);
      var calls = 0;
      final reads = <int>[];
      await db.transaction((tx) async {
        calls++;
        final row = await tx.table(users).single();
        reads.add(row.score);
        if (calls == 1) {
          await other.table(users).update((u) => [u.score.set(10)]).execute();
        }
        await tx
            .table(users)
            .update((u) => [u.score.set(row.score + 1)])
            .execute();
      }, retry: retry);
      expect(errors.map((e) => e.extendedCode), [517]);
      expect(reads, [0, 10]);
      expect(calls, 2);
      expect((await db.table(users).single()).score, 11);
    } finally {
      await other.close();
      await db.close();
      await directory.delete(recursive: true);
    }
  });
  for (final mode in [
    'success',
    'exhausted',
    'deadline',
    'cancel',
    'shared-budget',
  ]) {
    test('SQLite real busy COMMIT: $mode', () async {
      final directory = await Directory.systemTemp.createTemp(
        'orm-retry-commit-',
      );
      final options = SqliteOptions.file(
        '${directory.path}/db.sqlite',
        journal: .delete,
        busyTimeout: const Duration(milliseconds: 20),
      );
      final base = await sqlite(options), reader = await sqlite(options);
      final driver = _FaultDriver(base.driver);
      final release = Completer<void>(), entered = Completer<void>();
      final cancellation = CancellationToken();
      var callbacks = 0, busyCommits = 0;
      final writer = Database(
        driver,
        onQuery: (event) {
          if (event.sql == 'COMMIT' && event.error is SqliteFailure) {
            busyCommits++;
            if (mode == 'success' && !release.isCompleted) release.complete();
            if (mode == 'cancel') cancellation.cancel();
          }
        },
      );
      await createTables(writer);
      await writer.table(users).createRow((u) => [u.email.set('initial')]);
      final owner = reader.transaction((tx) async {
        await tx.table(users).count();
        entered.complete();
        await release.future;
      });
      try {
        await entered.future;
        driver.commands.clear();
        if (mode == 'shared-budget') {
          driver.after = (command) {
            if (command.sql.startsWith('UPDATE') && callbacks == 1) {
              throw const _Transient();
            }
          };
        }
        final future = writer.transaction(
          (tx) async {
            callbacks++;
            await tx
                .table(users)
                .update((u) => [u.score.increment(1)])
                .execute();
            return 'committed';
          },
          cancellation: cancellation,
          retry: TransactionRetry(
            maxAttempts: mode == 'deadline' ? 100 : 3,
            timeout: mode == 'deadline'
                ? const Duration(milliseconds: 80)
                : const Duration(seconds: 3),
            delay: const Duration(milliseconds: 20),
          ),
        );
        if (mode == 'success') {
          expect(await future, 'committed');
          expect(callbacks, 1);
          expect(busyCommits, 1);
          expect(driver.commands.where((s) => s == 'COMMIT').length, 2);
          expect(driver.commands, isNot(contains('ROLLBACK')));
        } else {
          await expectLater(
            future,
            throwsA(switch (mode) {
              'deadline' => code('TRANSACTION.TIMEOUT'),
              'cancel' => code('TRANSACTION.CANCELLED'),
              _ => isA<SqliteFailure>().having((e) => e.code, 'code', 5),
            }),
          ).timeout(const Duration(seconds: 2));
          expect(callbacks, mode == 'shared-budget' ? 2 : 1);
          if (mode == 'exhausted') expect(busyCommits, 3);
          if (mode == 'shared-budget') expect(busyCommits, 2);
        }
        expect(
          (await writer.table(users).single()).score,
          mode == 'success' ? 1 : 0,
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await owner;
        await reader.close();
        await writer.close();
        await directory.delete(recursive: true);
      }
    });
  }
}

void runTests(String name, Future<Database<Backend>> Function() open) {
  group('retry $name', () {
    late Database<Backend> db;
    late _FaultDriver driver;
    setUp(() async {
      final base = await open();
      driver = _FaultDriver(base.driver);
      db = Database(driver);
      await db.execute(SqlCommand('DROP TABLE IF EXISTS users'));
      await createTables(db);
      await db.table(users).createRow((u) => [u.email.set('initial')]);
      driver.commands.clear();
    });
    tearDown(() => db.close());
    Future<int> score() async =>
        (await db.table(users).where((u) => u.id.eq(1)).single()).score;
    Future<void> write(Database<Backend> tx) async => tx
        .table(users)
        .where((u) => u.id.eq(1))
        .update((u) => [u.score.increment(1)])
        .execute()
        .then((_) {});

    test(
      'opt-in retries roll back all writes and use new closed-over views',
      () async {
        var callbacks = 0;
        final views = <Database<Backend>>[];
        driver.after = (command) {
          if (command.sql.startsWith('UPDATE') && callbacks == 1) {
            throw const _Transient();
          }
        };
        final result = await db.transaction((tx) async {
          callbacks++;
          views.add(tx);
          await tx
              .table(users)
              .createRow((u) => [u.email.set('attempt$callbacks')]);
          await write(tx);
          return (
            attempt: callbacks,
            value:
                (await tx.table(users).where((u) => u.id.eq(1)).single()).score,
          );
        }, retry: retry);
        expect(result, (attempt: 2, value: 1));
        expect(views.toSet().length, 2);
        for (final view in views) {
          expect(
            () => view.execute(SqlCommand('SELECT 1')),
            throwsA(code('SESSION.CLOSED')),
          );
        }
        expect(
          await db.table(users).select((u) => u.email).get(),
          unorderedEquals(['initial', 'attempt2']),
        );
        expect(driver.commands.where((s) => s == 'ROLLBACK').length, 1);
        expect(driver.commands.where((s) => s == 'COMMIT').length, 1);
      },
    );

    test(
      'default is one attempt; an explicit attempt limit is exact',
      () async {
        var calls = 0;
        driver.after = (command) {
          if (command.sql.startsWith('UPDATE')) throw const _Transient();
        };
        Future<void> action(Database<Backend> tx) async {
          calls++;
          await write(tx);
        }

        await expectLater(db.transaction(action), throwsA(isA<_Transient>()));
        expect(calls, 1);
        calls = 0;
        driver.commands.clear();
        await expectLater(
          db.transaction(action, retry: retry),
          throwsA(isA<_Transient>()),
        );
        expect(calls, 3);
        expect(driver.commands.where((s) => s == 'ROLLBACK').length, 3);
        expect(await score(), 0);
      },
    );

    test('application and constraint errors and caught statement failures do not replay', () async {
      var calls = 0;
      await expectLater(
        db.transaction((tx) async {
          calls++;
          await tx.table(users).createRow((u) => [u.email.set('initial')]);
        }, retry: retry),
        throwsA(
          isA<SqlFailure>().having(
            (e) => e.retryTransaction,
            'retryTransaction',
            false,
          ),
        ),
      );
      expect(calls, 1);
      calls = 0;
      await expectLater(
        db.transaction((tx) async {
          calls++;
          throw StateError('application');
        }, retry: retry),
        throwsStateError,
      );
      expect(calls, 1);
      calls = 0;
      driver.after = (command) {
        if (command.sql.startsWith('UPDATE')) throw const _Transient();
      };
      await expectLater(
        db.transaction((tx) async {
          calls++;
          try {
            await write(tx);
          } on _Transient {
            /* Deliberately caught by the app. */
          }
        }, retry: retry),
        throwsA(code('TRANSACTION.FAILED')),
      );
      expect(calls, 1);
      expect(await score(), 0);
    });

    test('unknown commit and unconfirmed rollback prohibit replay', () async {
      var calls = 0;
      driver.after = (command) {
        if (command.sql == 'COMMIT') throw StateError('Lost acknowledgement');
      };
      await expectLater(
        db.transaction((tx) async {
          calls++;
          await write(tx);
        }, retry: retry),
        throwsA(code('TRANSACTION.COMMIT')),
      );
      expect(calls, 1);
      expect(await score(), 1);
      driver.after = (command) {
        if (command.sql.startsWith('UPDATE')) throw const _Transient();
      };
      driver.before = (command) {
        if (command.sql == 'ROLLBACK') {
          throw StateError('Rollback transport failed');
        }
      };
      calls = 0;
      await expectLater(
        db.transaction((tx) async {
          calls++;
          await write(tx);
        }, retry: retry),
        throwsA(code('TRANSACTION.ROLLBACK')),
      );
      expect(calls, 1);
      expect(driver.discards, 1);
    });

    test('retry time budget bounds active SQL and does not retry cancellation', () async {
      final slow = name == 'postgres'
          ? 'SELECT pg_sleep(10)'
          : 'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n';
      var calls = 0;
      await expectLater(
        db.transaction((tx) async {
          calls++;
          await write(tx);
          await tx.execute(SqlCommand(slow));
        }, retry: const TransactionRetry(timeout: Duration(milliseconds: 80))),
        throwsA(code('TRANSACTION.TIMEOUT')),
      ).timeout(const Duration(seconds: 3));
      expect(calls, 1);
      expect(await score(), 0);
    });

    test(
      'deadline and cancellation interrupt backoff without another callback',
      () async {
        var calls = 0;
        driver.after = (command) {
          if (command.sql.startsWith('UPDATE')) throw const _Transient();
        };
        await expectLater(
          db.transaction(
            (tx) async {
              calls++;
              await write(tx);
            },
            retry: const TransactionRetry(
              timeout: Duration(milliseconds: 80),
              delay: Duration(seconds: 5),
              maxDelay: Duration(seconds: 5),
            ),
          ),
          throwsA(code('TRANSACTION.TIMEOUT')),
        ).timeout(const Duration(seconds: 2));
        expect(calls, 1);
        expect(await score(), 0);
        calls = 0;
        final token = CancellationToken();
        Timer? cancelling;
        driver.after = (command) {
          if (command.sql.startsWith('UPDATE')) throw const _Transient();
          if (command.sql == 'ROLLBACK') {
            cancelling = Timer(const Duration(milliseconds: 20), token.cancel);
          }
        };
        try {
          await expectLater(
            db.transaction(
              (tx) async {
                calls++;
                await write(tx);
              },
              cancellation: token,
              retry: const TransactionRetry(
                delay: Duration(seconds: 5),
                maxDelay: Duration(seconds: 5),
              ),
            ),
            throwsA(code('TRANSACTION.CANCELLED')),
          ).timeout(const Duration(seconds: 2));
          expect(calls, 1);
          expect(await score(), 0);
        } finally {
          cancelling?.cancel();
        }
      },
    );

    test(
      'time budget includes acquisition and abandons late callbacks',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        final owner = db.session((s) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var calls = 0;
        try {
          await expectLater(
            db.transaction(
              (tx) async {
                calls++;
              },
              retry: const TransactionRetry(
                timeout: Duration(milliseconds: 40),
              ),
            ),
            throwsA(code('TRANSACTION.TIMEOUT')),
          ).timeout(const Duration(seconds: 2));
          await expectLater(
            db.transaction(
              (tx) async {
                calls++;
              },
              acquire: const AcquisitionOptions(
                timeout: Duration(milliseconds: 10),
              ),
              retry: const TransactionRetry(timeout: Duration(seconds: 1)),
            ),
            throwsA(code('CONNECTION.TIMEOUT')),
          );
        } finally {
          release.complete();
          await owner;
        }
        await db.execute(SqlCommand('SELECT 1'));
        expect(calls, 0);
        expect(driver.commands, isNot(contains('BEGIN')));
      },
    );

    test('transaction timeout is shared across attempts and sessions recover after expiry', () async {
      var calls = 0;
      driver.after = (command) {
        if (command.sql.startsWith('UPDATE')) throw const _Transient();
      };
      await expectLater(
        db.transaction(
          (tx) async {
            calls++;
            await Future<void>.delayed(const Duration(milliseconds: 40));
            await write(tx);
          },
          timeout: const Duration(milliseconds: 70),
          retry: const TransactionRetry(maxAttempts: 10, delay: Duration.zero),
        ),
        throwsA(code('TRANSACTION.TIMEOUT')),
      );
      expect(calls, lessThan(3));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await score(), 0);
      await db.session((session) async {
        await expectLater(
          Future.sync(
            () => session.transaction(
              (tx) async {},
              retry: const TransactionRetry(timeout: Duration(microseconds: 1)),
            ),
          ),
          throwsA(code('TRANSACTION.TIMEOUT')),
        );
        expect((await session.execute(SqlCommand('SELECT 1'))).rows, [
          [1],
        ]);
      });
    });

    test(
      'subscriptions publish only the final committed retry result',
      () async {
        var calls = 0;
        driver.after = (command) {
          if (command.sql.startsWith('UPDATE') && calls == 1) {
            throw const _Transient();
          }
        };
        final snapshots = <List<int>>[];
        final initial = Completer<void>(), committed = Completer<void>();
        final subscription = db
            .table(users)
            .select((u) => u.score)
            .watch()
            .listen((rows) {
              snapshots.add(rows);
              if (snapshots.length == 1) {
                initial.complete();
              } else {
                committed.complete();
              }
            });
        try {
          await initial.future;
          await db.transaction((tx) async {
            calls++;
            await write(tx);
          }, retry: retry);
          await committed.future.timeout(const Duration(seconds: 2));
          expect(snapshots, [
            [0],
            [1],
          ]);
        } finally {
          await subscription.cancel();
        }
      },
    );

    test('invalid policies reject before SQL', () {
      for (final policy in [
        const TransactionRetry(maxAttempts: 0),
        const TransactionRetry(timeout: Duration.zero),
        const TransactionRetry(delay: Duration(milliseconds: -1)),
        const TransactionRetry(delay: Duration(seconds: 2)),
      ]) {
        expect(
          () => db.transaction((tx) async {}, retry: policy),
          throwsArgumentError,
        );
      }
      expect(driver.commands, isEmpty);
    });

    if (name == 'postgres') {
      Future<Database<Postgres>> concurrent() async => postgres(
        PostgresOptions(
          url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
          tls: .disable,
          schema: 'orm_retry_tests',
          maxConnections: 1,
        ),
      );
      test('real unknown COMMIT response prohibits opted-in retry', () async {
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
        var calls = 0;
        await expectLater(
          db.transaction((tx) async {
            calls++;
            await write(tx);
          }, retry: retry),
          throwsA(code('TRANSACTION.COMMIT')),
        );
        expect(calls, 1);
        expect(await score(), 0);
      });
      test(
        'real serialization conflict repeats the reads and decisions',
        () async {
          final other = await concurrent();
          var calls = 0;
          final reads = <int>[];
          try {
            final result = await db.transaction(
              (tx) async {
                calls++;
                final user = await tx.table(users).single();
                reads.add(user.score);
                if (calls == 1) {
                  await other
                      .table(users)
                      .update((u) => [u.score.set(10)])
                      .execute();
                }
                await tx
                    .table(users)
                    .update((u) => [u.score.set(user.score + 1)])
                    .execute();
                return user.score + 1;
              },
              options: const PostgresTransaction(isolation: .repeatableRead),
              retry: retry,
            );
            expect(calls, 2);
            expect(reads, [0, 10]);
            expect(result, 11);
            expect(await score(), 11);
          } finally {
            await other.close();
          }
        },
      );
      test('real deadlock retries only the aborted callback', () async {
        final other = await concurrent();
        await db.table(users).createRow((u) => [u.email.set('second')]);
        final first = Completer<void>(), second = Completer<void>();
        Future<int> run(
          Database<Backend> source,
          int a,
          int b,
          Completer<void> ready,
          Completer<void> peer,
        ) async {
          var calls = 0;
          await source.transaction((tx) async {
            calls++;
            await tx
                .table(users)
                .where((u) => u.id.eq(a))
                .update((u) => [u.score.increment(1)])
                .execute();
            if (calls == 1) {
              ready.complete();
              await peer.future;
            }
            await tx
                .table(users)
                .where((u) => u.id.eq(b))
                .update((u) => [u.score.increment(1)])
                .execute();
          }, retry: retry);
          return calls;
        }

        try {
          final calls = await Future.wait([
            run(db, 1, 2, first, second),
            run(other, 2, 1, second, first),
          ]);
          expect(calls, unorderedEquals([1, 2]));
          expect(await db.table(users).select((u) => u.score).get(), [2, 2]);
        } finally {
          await other.close();
        }
      });
    }
  });
}

/// Controlled adapter failure after real SQL, to exercise cleanup/budget paths.
final class _Transient implements SqlFailure {
  const _Transient();
  @override
  bool get retryTransaction => true;
  @override
  bool get retryCommit => false;
  @override
  bool get commitRejected => true;
}

final class _FaultDriver(final Driver<Backend> source)
    implements Driver<Backend> {
  void Function(SqlCommand)? before, after;
  final commands = <String>[];
  int discards = 0;
  @override
  Capabilities get capabilities => source.capabilities;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      source.run((c) => action(_FaultConnection(c, this)));
  @override
  Future<void> close() => source.close();
}

final class _FaultConnection(
  final SqlConnection inner,
  final _FaultDriver driver,
) implements SqlConnection {
  @override
  bool? get transactionActive => inner.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    driver.commands.add(command.sql);
    driver.before?.call(command);
    final result = await inner.execute(command, options: options);
    driver.after?.call(command);
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
