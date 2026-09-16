import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';
import 'package:web/web.dart' as web;

import 'schema.orm.dart';
import 'schema.dart' as models;
import 'teams.dart';
import 'precision.dart';

final checks = <Map<String, Object?>>[];
void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> rejects(Future<Object?> Function() action, {String? code}) async {
  try {
    await action();
  } catch (e) {
    if (code != null) {
      expect(e is OrmException && e.code == code, 'Expected $code, got $e');
    }
    return;
  }
  throw StateError('Expected rejection${code == null ? '' : ': $code'}');
}

Future<void> check(String name, Future<void> Function() body) async {
  final watch = Stopwatch()..start();
  await body();
  checks.add({'name': name, 'milliseconds': watch.elapsedMilliseconds});
}

Future<Database<Sqlite>> memory() => sqlite(const SqliteOptions.memory());
Future<void> initialize(Database<Sqlite> db) => Migrator(db)
    .apply([
      Migration.create('0001_browser', appSchema, dialect: SqlDialect.sqlite),
    ])
    .then((_) {});

Future<void> main() async {
  try {
    if (Uri.base.queryParameters['phase'] == 'recover') {
      checks.addAll(
        (jsonDecode(web.window.sessionStorage.getItem('orm_checks')!) as List)
            .cast<Map<String, Object?>>(),
      );
      final name = web.window.sessionStorage.getItem('orm_database')!;
      final recovered = await sqlite(SqliteOptions.persistent(name));
      try {
        await check('page reload recovers committed rows and rolls back interrupted transaction', () async {
          expect(
            (await recovered.users.single()).email == 'durable',
            'Committed rows changed or interrupted write survived',
          );
          expect(
            (await recovered.execute(SqlCommand('PRAGMA integrity_check')))
                    .rows
                    .single
                    .single ==
                'ok',
            'OPFS integrity failed',
          );
        });
        await check(
          'persistent schema upgrades after reload preserve existing data',
          () async {
            final first = Migration.create(
              '0001_browser',
              appSchema,
              dialect: SqlDialect.sqlite,
            );
            final target = SchemaSnapshot([
              ...appSchema,
              TableSchema(
                'upgraded',
                columns: [Column('version', Codecs.integer)],
              ),
            ]);
            final second = Migration.diff(
              '0002_browser',
              from: SchemaSnapshot(appSchema),
              to: target,
              previous: first.checksum,
              dialect: SqlDialect.sqlite,
            );
            await Migrator(recovered).apply([first, second]);
            expect(
              (await verifySchema(recovered, target)).matches,
              'Upgrade schema differs',
            );
            expect(
              (await recovered.users.single()).email == 'durable',
              'Upgrade removed existing data',
            );
          },
        );
      } finally {
        await recovered.close();
      }
      await report({'passed': true, 'checks': checks});
      return;
    }
    await check(
      'many-to-many plans, phase observations, payloads, pagination and transaction writes preserve query counts',
      () => checkTeams(),
    );
    await check(
      'temporal column precision preserves epoch ties, extended ranges, defaults and keys',
      () => checkTemporalPrecision(),
    );
    final db = await memory();
    try {
      await check('memory migrations and verified foreign keys', () async {
        await initialize(db);
        expect(
          (await verifySchema(db, SchemaSnapshot(appSchema))).matches,
          'Schema differs',
        );
        await rejects(() => db.posts.create(authorId: 999, title: 'invalid'));
      });
      await check('query ownership, optional guards and write validation survive JS and WASM', () async {
        final isolated = await memory();
        try {
          await initialize(isolated);
          await isolated.users.create(email: 'boundary');
          await isolated.transaction((tx) async {
            final ids = isolated.users.select((u) => u.id);
            await rejects(
              () => tx.users.where((u) => u.id.isInQuery(ids)).get(),
              code: 'QUERY.SESSION',
            );
            final cte = ids.asCte('root_ids').alias();
            await rejects(
              () => tx.users
                  .join(cte, on: (u, c) => u.id.equals(c.ref((u) => u.id)))
                  .get(),
              code: 'QUERY.SESSION',
            );
            expect(
              await tx.users.count() == 1,
              'Rejected queries damaged the transaction',
            );
          });
          final present = usersTable.alias(), absent = usersTable.alias();
          final query = isolated.users
              .leftJoin(present, on: (u, p) => u.id.equals(p.id))
              .leftJoin(absent, on: (u, a) => a.id.eq(-1));
          await rejects(
            () => query
                .select((_) => present.optional(absent.fields.email))
                .get(),
            code: 'QUERY.NULLABILITY',
          );
          final result = await query
              .select(
                (_) => present.optional(
                  (
                    present.fields.email,
                    absent.optional(absent.fields.email),
                  ).map((a, b) => (a, b)),
                ),
              )
              .get();
          expect(
            result.single == ('boundary', null),
            'Nested optional decoding differs',
          );
          await rejects(
            () => isolated.users
                .where((u) => u.id.count().gt(0))
                .delete()
                .execute(),
            code: 'QUERY.AGGREGATE',
          );
          await rejects(
            () => isolated.users
                .insert((u) => [u.email.set('invalid')])
                .returning((_) => fields({}))
                .get(),
            code: 'QUERY.EMPTY_SELECTION',
          );
          expect(
            await isolated.users.count() == 1,
            'Rejected writes changed data',
          );
        } finally {
          await isolated.close();
        }
      });
      await check('client factories distinguish omission, explicit null and prepared batch values', () async {
        final isolated = await memory();
        try {
          await initialize(isolated);
          final initialCalls = models.nicknameCalls;
          final row = await isolated.users.create(email: 'default');
          expect(
            row.nickname == 'guest',
            'Omitted value did not use Dart factory',
          );
          final explicit = await isolated.users.create(
            email: 'explicit',
            nickname: .set(null),
          );
          expect(explicit.nickname == null, 'Explicit null used Dart factory');
          final batch = isolated.users.insertMany([
            'batch-a',
            'batch-b',
          ], (u, email) => [u.email.set(email)]);
          expect(
            models.nicknameCalls == initialCalls + 3,
            'Factory invocation count differs',
          );
          batch.compile();
          batch.compile();
          await batch.execute();
          expect(
            models.nicknameCalls == initialCalls + 3,
            'Compiling or executing reran factories',
          );
          expect(
            await isolated.users.where((u) => u.nickname.eq('guest')).count() ==
                3,
            'Batch defaults were not stored',
          );
        } finally {
          await isolated.close();
        }
      });
      await check('computed stored and virtual fields recompute across CRUD and migrations', () async {
        final isolated = await memory();
        try {
          await initialize(isolated);
          final row = await isolated.users.create(email: 'computed');
          expect(
            row.emailSize == 8 && row.upperNickname == 'GUEST',
            'Computed creation differs',
          );
          await isolated.users
              .byId(row.id)
              .patch(email: .set('edited'), nickname: .set(null));
          final updated = await isolated.users.single();
          expect(
            updated.emailSize == 6 && updated.upperNickname == null,
            'Computed update differs',
          );
          final start = SchemaSnapshot(appSchema);
          final initial = Migration.create(
            '0001_browser',
            appSchema,
            dialect: SqlDialect.sqlite,
          );
          final target = SchemaSnapshot([
            for (final table in appSchema)
              if (table.name != 'users')
                table
              else
                TableSchema(
                  table.name,
                  columns: [
                    for (final c in table.columns)
                      if (c.name != 'email_size')
                        c
                      else
                        Column(
                          'email_size',
                          Codecs.integer,
                          computed: const ComputedColumn('length(email) + 1'),
                        ),
                  ],
                  primaryKey: table.primaryKey,
                  uniqueKeys: table.uniqueKeys,
                  foreignKeys: table.foreignKeys,
                  indexes: table.indexes,
                  checks: table.checks,
                ),
          ]);
          final migration = Migration.diff(
            '0002_computed',
            from: start,
            to: target,
            previous: initial.checksum,
            dialect: SqlDialect.sqlite,
          );
          await Migrator(isolated).apply([initial, migration]);
          expect(
            (await isolated.users.single()).emailSize == 7,
            'Migration did not recompute existing row',
          );
          expect(
            (await verifySchema(isolated, target)).matches,
            'Computed catalog differs',
          );
        } finally {
          await isolated.close();
        }
      });
      await check(
        'generated CHECK enforcement and atomic constraint migrations',
        () async {
          await rejects(() => db.users.create(email: ''));
          expect(
            (await inspectTable(db, 'users')).checks.length == 1,
            'Generated CHECK missing',
          );
          final isolated = await memory();
          try {
            TableSchema table(List<CheckSchema> constraints) => TableSchema(
              'scores',
              columns: [Column('value', Codecs.integer)],
              checks: constraints,
            );
            final start = SchemaSnapshot([table(const [])]);
            final first = Migration.create(
              '0001_initial',
              start.tables,
              dialect: SqlDialect.sqlite,
            );
            await Migrator(isolated).apply([first]);
            await isolated.execute(
              SqlCommand('INSERT INTO scores VALUES (-1)'),
            );
            final target = SchemaSnapshot([
              table(const [CheckSchema('positive', 'value >= 0')]),
            ]);
            final second = Migration.diff(
              '0002_check',
              from: start,
              to: target,
              previous: first.checksum,
              dialect: SqlDialect.sqlite,
            );
            await rejects(() => Migrator(isolated).apply([first, second]));
            expect(
              (await verifySchema(isolated, start)).matches,
              'Failed CHECK migration changed schema',
            );
            expect(
              (await Migrator(isolated).history()).length == 1,
              'Failed CHECK migration changed history',
            );
            await isolated.execute(SqlCommand('UPDATE scores SET value = 2'));
            await Migrator(isolated).apply([first, second]);
            expect(
              (await verifySchema(isolated, target)).matches,
              'CHECK migration differs',
            );
            await rejects(
              () =>
                  isolated.execute(SqlCommand('UPDATE scores SET value = -1')),
            );
          } finally {
            await isolated.close();
          }
        },
      );
      await check(
        'generated records, projections and typed relation batches',
        () async {
          final a = await db.users.create(email: 'a');
          final b = await db.users.create(email: 'b');
          for (final user in [a, b]) {
            for (var i = 0; i < 5; i++) {
              await db.posts.create(
                authorId: user.id,
                title: '${user.email}$i',
              );
            }
          }
          final rows = await db.users
              .orderBy((u) => [u.id.asc()])
              .select(
                (u) => (
                  u.email,
                  u.posts
                      .orderBy((p) => [p.id.desc()])
                      .take(2)
                      .select((p) => p.title)
                      .many(),
                ).map((email, posts) => (email: email, posts: posts)),
              )
              .get();
          expect(
            rows.length == 2 &&
                rows[0].posts.join(',') == 'a4,a3' &&
                rows[1].posts.join(',') == 'b4,b3',
            '$rows',
          );
          await db.users.byId(a.id).patch(nickname: .set('named'));
          await db.users.byId(a.id).patch(nickname: .set(null));
          expect(
            (await db.users.byId(a.id).single()).nickname == null,
            'Explicit NULL failed',
          );
        },
      );
      await check('rollback, savepoints and transaction lifetime', () async {
        Database<Sqlite>? escaped;
        await rejects(
          () => db.transaction((tx) async {
            escaped = tx;
            await tx.users.create(email: 'rolled-back');
            throw StateError('rollback');
          }),
        );
        expect(
          !await db.users.where((u) => u.email.eq('rolled-back')).exists(),
          'Rollback leaked data',
        );
        await rejects(() => escaped!.users.get(), code: 'SESSION.CLOSED');
        await db.transaction((tx) async {
          await rejects(
            () => tx.savepoint((sp) async {
              await sp.users.create(email: 'savepoint');
              throw StateError('rollback');
            }),
          );
          expect(
            !await tx.users.where((u) => u.email.eq('savepoint')).exists(),
            'Savepoint leaked data',
          );
        });
      });
      await check('stream cursor batches and early release', () async {
        final all = await db.posts
            .orderBy((p) => [p.id.asc()])
            .select((p) => p.title)
            .stream(batchSize: 3)
            .toList();
        expect(all.length == 10, 'Stream truncated');
        await db.posts.stream(batchSize: 2).take(1).drain<void>();
        expect(await db.posts.count() == 10, 'Cursor retained the lease');
      });
      await check('commit invalidation and watch snapshots', () async {
        final stream = StreamIterator(db.users.select((u) => u.email).watch());
        try {
          expect(await stream.moveNext(), 'Missing first snapshot');
          final next = stream.moveNext();
          await db.transaction((tx) async {
            await tx.users.create(email: 'watched');
          });
          expect(await next, 'Missing commit snapshot');
          expect(stream.current.contains('watched'), 'Watch missed commit');
        } finally {
          await stream.cancel();
        }
      });
      await check(
        'exact BigInt, Decimal, blobs and calendar transport',
        () async {
          final big = BigInt.parse('9223372036854775807');
          final amount = Decimal.parse('123456789012345678901.000000001');
          final row = await db.values.create(
            wide: big,
            bytes: Uint8List.fromList([0, 127, 255]),
            amount: amount,
            day: LocalDate.parse('0001-01-01 BC'),
            time: LocalTime.parse('23:59:59.123456'),
            stamp: LocalDateTime.parse('0001-01-01 12:00:00.123456 BC'),
            instant: DateTime.utc(2024),
          );
          expect(
            row.wide == big &&
                row.amount == amount &&
                row.bytes.join(',') == '0,127,255',
            'Scalar codec mismatch',
          );
          expect(
            row.day == LocalDate.parse('0001-01-01 BC') &&
                row.time.microseconds % 1000000 == 123456,
            'Calendar precision changed',
          );
          expect(
            row.stamp == LocalDateTime.parse('0001-01-01 12:00:00.123456 BC') &&
                row.instant == DateTime.utc(2024),
            'Timestamp changed',
          );
          final raw = await db.execute(
            SqlCommand('SELECT 9223372036854775807, -9223372036854775808'),
          );
          expect(
            raw.rows.single[0] == big &&
                raw.rows.single[1] == -big - BigInt.one,
            'Raw int64 was rounded',
          );
          final total = await db.values.select((v) => v.amount.sum()).single();
          expect(total == amount, 'Decimal aggregate changed');
        },
      );
      await check('explicit unsupported cancellation', () async {
        expect(
          !db.capabilities.cancellation,
          'Cancellation was falsely advertised',
        );
        await rejects(
          () => db.users.get(
            options: const ExecutionOptions(timeout: Duration(seconds: 1)),
          ),
          code: 'CAPABILITY.CANCEL',
        );
      });
      await check('large real values retain floating storage', () async {
        final result = await db.users
            .take(1)
            .select((u) => value(1e20, Codecs.real))
            .single();
        expect(result == 1e20, 'Large REAL changed');
        final raw = await db.execute(
          SqlCommand('SELECT typeof(?1), ?1', [const SqlReal(1e20)]),
        );
        expect(
          raw.rows.single[0] == 'real' && raw.rows.single[1] == 1e20,
          'Floating storage was lost',
        );
        await rejects(
          () => db.execute(
            SqlCommand('SELECT ?1', [int.parse('9007199254740993')]),
          ),
          code: 'CODEC.INTEGER',
        );
        await db.readings.create(id: 1, value: 1e20);
        await db.readings.create(id: 2, value: 1e20);
        await db.readings.create(id: 3, value: 2e20);
        final token = db.readings.cursorToken(
          (r) => [r.value.cursor(1e20), r.id.cursor(1)],
        );
        final next = await db.readings
            .seekToken(token, orderBy: (r) => [r.value.asc(), r.id.asc()])
            .get();
        expect(
          next.length == 2 && next[0].id == 2 && next[1].id == 3,
          'REAL cursor lost its value or stable tie breaker',
        );
        final peers = await db.readings
            .orderBy((r) => [r.id.asc()])
            .select(
              (r) => r.peers
                  .orderBy((p) => [p.id.asc()])
                  .select((p) => p.id)
                  .many(),
            )
            .get();
        expect(
          peers.toString() == '[[1, 2], [1, 2], [3]]',
          'Query-only REAL relation keys lost their storage intent or equality',
        );
        final same = await db.readings
            .orderBy((r) => [r.id.asc()])
            .select((r) => r.sameReading.select((p) => p.id).many())
            .get();
        expect(
          same.toString() == '[[1], [2], [3]]',
          'Composite REAL relation keys lost their storage intent',
        );
      });
      await check(
        'instant microseconds are exact or explicitly rejected',
        () async {
          for (final text in [
            '2024-01-01 00:00:00.000001+00',
            '0001-01-01 00:00:00.000001+00 BC',
            '275760-09-12 23:59:59.999999+00',
          ]) {
            final decoded = Codecs.dateTime.decode(text);
            expect(
              Codecs.dateTime.encode(decoded) == text,
              'Instant silently lost microseconds: $text',
            );
          }
        },
      );
      await check('worker does not block the browser event loop', () async {
        var ticks = 0;
        final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
          ticks++;
        });
        try {
          await db.execute(
            SqlCommand(
              'WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<1000000) SELECT SUM(x) FROM n',
            ),
          );
          expect(ticks > 0, 'Main event loop was blocked');
        } finally {
          timer.cancel();
        }
      });
    } finally {
      await db.close();
    }
    await check(
      'startup failures are bounded and release failed workers',
      () async {
        await rejects(
          () => sqlite(
            SqliteOptions.memory(
              web: SqliteWebOptions(wasm: Uri.parse('/missing.wasm')),
            ),
          ),
        );
        await rejects(
          () => sqlite(
            SqliteOptions.memory(
              web: SqliteWebOptions(
                worker: Uri.parse('/missing-worker.js'),
                openTimeout: const Duration(seconds: 2),
              ),
            ),
          ),
        );
        final healthy = await memory();
        await healthy.close();
      },
    );
    await check(
      'unified entry rejects native paths and mismatched browser assets',
      () async {
        await rejects(
          () => sqlite(const SqliteOptions.file('native.sqlite')),
          code: 'CAPABILITY.STORAGE',
        );
        await rejects(
          () => sqlite(
            SqliteOptions.memory(
              web: SqliteWebOptions(worker: Uri.parse('/mismatched-worker.js')),
            ),
          ),
          code: 'DRIVER.PROTOCOL',
        );
        await rejects(
          () => sqlite(
            SqliteOptions.memory(
              web: SqliteWebOptions(
                worker: Uri.parse('/mismatched-worker.js?protocol=old'),
              ),
            ),
          ),
          code: 'DRIVER.PROTOCOL',
        );
        await rejects(
          () => sqlite(
            const SqliteOptions.memory(
              web: SqliteWebOptions(
                wasmIntegrity:
                    'sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
              ),
            ),
          ),
          code: 'DRIVER.ASSET',
        );
        final healthy = await memory();
        await healthy.close();
      },
    );
    await check(
      'OPFS commit survives a closed worker and new connection',
      () async {
        final options = SqliteOptions.persistent(
          'browser-${DateTime.now().millisecondsSinceEpoch}',
        );
        var persistent = await sqlite(options);
        try {
          await initialize(persistent);
          await persistent.users.create(email: 'persisted');
          await rejects(() => sqlite(options));
          expect(
            (await persistent.users.single()).email == 'persisted',
            'Failed competing open disturbed the owner',
          );
        } finally {
          await persistent.close();
        }
        persistent = await sqlite(options);
        try {
          expect(
            (await persistent.users.single()).email == 'persisted',
            'OPFS lost committed data',
          );
        } finally {
          await persistent.close();
        }
      },
    );
    final name = 'reload-${DateTime.now().millisecondsSinceEpoch}';
    final persistent = await sqlite(SqliteOptions.persistent(name));
    await initialize(persistent);
    await persistent.users.create(email: 'durable');
    await persistent.transaction((tx) async {
      await tx.users.create(email: 'interrupted');
      web.window.sessionStorage.setItem('orm_checks', jsonEncode(checks));
      web.window.sessionStorage.setItem('orm_database', name);
      // Reload without closing this connection or committing its transaction.
      web.window.location.replace('/?phase=recover');
      await Completer<void>().future;
    });
  } catch (error, stack) {
    await report({
      'passed': false,
      'error': error.toString(),
      'stack': stack.toString(),
      'checks': checks,
    });
  }
}

Future<void> report(Map<String, Object?> result) async {
  result['browser'] = web.window.navigator.userAgent;
  final body = jsonEncode(result);
  web.document.body!.textContent = body;
  await web.window
      .fetch('/report'.toJS, web.RequestInit(method: 'POST', body: body.toJS))
      .toDart;
}
