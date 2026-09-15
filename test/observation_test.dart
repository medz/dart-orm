import 'dart:async';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/teams/schema.orm.dart';

void main() {
  for (final dialect in SqlDialect.values) {
    group(
      'observation ${dialect.name}',
      () {
        late Database<Backend> db;
        final acquired = <AcquisitionEvent>[];
        final decoded = <DecodeEvent>[];
        final statements = <QueryEvent>[];
        setUp(() async {
          if (dialect == SqlDialect.sqlite) {
            db = await sqlite(
              const SqliteOptions.memory(),
              onQuery: statements.add,
              onAcquire: acquired.add,
              onDecode: decoded.add,
            );
          } else {
            db = postgres(
              PostgresOptions(
                url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                tls: .disable,
                schema: 'orm_observation_tests',
                maxConnections: 1,
              ),
              onQuery: statements.add,
              onAcquire: acquired.add,
              onDecode: decoded.add,
            );
            await db.execute(
              SqlCommand('DROP SCHEMA IF EXISTS orm_observation_tests CASCADE'),
            );
            await db.execute(SqlCommand('CREATE SCHEMA orm_observation_tests'));
          }
          await Migrator(db).apply([
            Migration.create('0001_teams', appSchema, dialect: db.dialect),
          ]);
          await db.users.create(id: 1, name: 'Ada');
          await db.teams.create(id: 10, name: 'Core');
          await db.memberships.create(
            teamId: 10,
            userId: 1,
            joinedAt: DateTime.utc(2026),
          );
          acquired.clear();
          decoded.clear();
          statements.clear();
        });
        tearDown(() => db.close());

        test(
          'actual lease queue and synchronous mapping have separate clocks',
          () async {
            final held = Completer<void>(), release = Completer<void>();
            final holder = db.session((session) async {
              held.complete();
              await release.future;
            });
            await held.future;
            acquired.clear();
            final pending = db.users.select((u) => u.name).map((name) {
              final clock = Stopwatch()..start();
              while (clock.elapsedMilliseconds <
                  20) {} // Deliberate synchronous mapper cost.
              return name;
            }).get();
            try {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              expect(acquired, isEmpty);
              expect(statements, isEmpty);
              expect(decoded, isEmpty);
            } finally {
              release.complete();
              await holder;
            }
            expect(await pending, ['Ada']);
            expect(acquired, hasLength(1));
            expect(
              acquired.single.elapsed.inMilliseconds,
              greaterThanOrEqualTo(25),
            );
            expect(acquired.single.reusedConnection, false);
            expect(decoded, hasLength(1));
            expect(
              decoded.single.elapsed.inMilliseconds,
              greaterThanOrEqualTo(20),
            );
            expect(decoded.single.inputRows, 1);
            expect(decoded.single.sql, statements.single.sql);
            expect(
              [
                acquired.single.error,
                decoded.single.error,
                statements.single.error,
              ],
              [null, null, null],
            );
          },
        );

        for (final cancel in [false, true]) {
          test(
            '${cancel ? 'cancelled' : 'expired'} acquisition emits one failure and no late SQL',
            () async {
              final held = Completer<void>(), release = Completer<void>();
              final holder = db.session((session) async {
                held.complete();
                await release.future;
              });
              await held.future;
              acquired.clear();
              final token = CancellationToken();
              final pending = db.users.get(
                options: ExecutionOptions(
                  cancellation: cancel ? token : null,
                  acquireTimeout: cancel
                      ? null
                      : const Duration(milliseconds: 25),
                ),
              );
              if (cancel) token.cancel();
              try {
                await expectLater(
                  pending,
                  throwsA(
                    isA<OrmException>().having(
                      (e) => e.code,
                      'code',
                      cancel ? 'OPERATION.CANCELLED' : 'CONNECTION.TIMEOUT',
                    ),
                  ),
                );
                expect(acquired, hasLength(1));
                expect(acquired.single.error, isA<OrmException>());
                expect(statements, isEmpty);
                expect(decoded, isEmpty);
              } finally {
                release.complete();
                await holder;
              }
              // Queue a later operation after the abandoned request has drained.
              await db.session((session) async {});
              expect(acquired.where((e) => e.error != null), hasLength(1));
              expect(statements, isEmpty);
              expect(decoded, isEmpty);
            },
          );
        }

        test('sessions transactions and savepoints inherit hooks and report reused leases', () async {
          await db.session((session) async {
            expect(await session.users.select((u) => u.name).single(), 'Ada');
            await session.transaction(
              (tx) => tx.savepoint((child) async {
                expect(await child.users.select((u) => u.id).single(), 1);
              }),
            );
          });
          expect(acquired.first.reusedConnection, false);
          expect(
            acquired
                .skip(1)
                .every((e) => e.reusedConnection && e.elapsed == Duration.zero),
            true,
          );
          expect(decoded.map((e) => e.inputRows), [1, 1]);
        });

        test('nested reads attribute decoding to each statement without repeating SQL', () async {
          final query = db.users.select(
            (u) => (
              u.name,
              u.memberships
                  .select((m) => m.team.select((t) => t.name).required())
                  .many(),
            ).map((name, teams) => (name, teams)),
          );
          final rows = await query.get();
          expect(rows.single.$2, ['Core']);
          expect(acquired, hasLength(1));
          expect(statements, hasLength(2));
          expect(decoded.map((e) => e.sql), [
            statements[1].sql,
            statements[0].sql,
          ]);
          expect(
            decoded.every((e) => e.inputRows == 1 && e.error == null),
            true,
          );
        });

        test('SQL and mapper failures belong to their own phases', () async {
          await expectLater(
            db.execute(SqlCommand('SELECT * FROM missing_table')),
            throwsA(isA<SqlFailure>()),
          );
          expect(acquired.single.error, isNull);
          expect(statements.single.error, isA<SqlFailure>());
          expect(decoded, isEmpty);
          final failure = StateError('mapper failed');
          await expectLater(
            db.users.map<Object?>((row) => throw failure).get(),
            throwsA(same(failure)),
          );
          expect(acquired.last.error, isNull);
          expect(statements.last.error, isNull);
          expect(decoded.single.error, same(failure));
          expect(decoded.single.inputRows, 1);
        });

        test(
          'cursor batches and returning writes produce decoding observations',
          () async {
            await db.users
                .insertMany([
                  2,
                  3,
                ], (u, id) => [u.id.set(id), u.name.set('member')])
                .returning((u) => u.id)
                .get();
            expect(decoded.single.sql, isNull);
            expect(decoded.single.inputRows, 2);
            decoded.clear();
            statements.clear();
            acquired.clear();
            expect(
              await db.users
                  .orderBy((u) => [u.id.asc()])
                  .select((u) => u.id)
                  .stream(batchSize: 2)
                  .toList(),
              [1, 2, 3],
            );
            expect(acquired, hasLength(1));
            expect(decoded.map((e) => e.inputRows), [2, 1]);
            expect(
              statements
                  .where((e) => e.operation == QueryOperation.cursorFetch)
                  .map((e) => e.rowCount),
              [2, 1],
            );
            decoded.clear();
            final row = await db.users.create(id: 4, name: 'new');
            expect(row.id, 4);
            expect(decoded.single.inputRows, 1);
            expect(decoded.single.sql, startsWith('INSERT'));
          },
        );

        test('observer exceptions preserve successful commits and original mapper errors', () async {
          final observed = Database(
            db.driver,
            onAcquire: (_) => throw StateError('observer'),
            onQuery: (_) => throw StateError('observer'),
            onDecode: (_) => throw StateError('observer'),
          );
          await observed.transaction(
            (tx) => tx.users.create(id: 2, name: 'committed'),
          );
          expect((await db.users.byId(2).single()).name, 'committed');
          final failure = StateError('actual mapper');
          await expectLater(
            observed.users.map<Object?>((row) => throw failure).get(),
            throwsA(same(failure)),
          );
        });
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES.'
          : false,
    );
  }

  test('synchronous driver acquisition failures are reported once', () async {
    final events = <AcquisitionEvent>[];
    final failure = StateError('driver unavailable');
    final db = Database(_FailedDriver(failure), onAcquire: events.add);
    await expectLater(
      db.execute(SqlCommand('SELECT 1')),
      throwsA(same(failure)),
    );
    expect(events, hasLength(1));
    expect(events.single.error, same(failure));
    await db.close();
  });
}

final class _FailedDriver(final Object failure) implements Driver<Backend> {
  @override
  Capabilities get capabilities =>
      const Capabilities(dialect: SqlDialect.sqlite, maxParameters: 10);
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) => throw failure;
  @override
  Future<void> close() async {}
}
