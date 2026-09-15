import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:orm/migrate.dart';
import 'package:orm/sqlite_web.dart';
import 'package:web/web.dart' as web;

import 'schema.orm.dart';

final checks = <Map<String, Object?>>[];
final wasm = Uri.parse('/sqlite3.wasm');
final worker = Uri.parse('/worker.js');
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

Future<Database<Sqlite>> memory() =>
    sqliteWeb(SqliteWebOptions.memory(wasm: wasm, worker: worker));
Future<void> initialize(Database<Sqlite> db) =>
    Migrator(db)
        .apply([Migration.create('0001_browser', appSchema)])
        .then((_) {});

Future<void> main() async {
  try {
    if (Uri.base.queryParameters['phase'] == 'recover') {
      checks.addAll(
        (jsonDecode(web.window.sessionStorage.getItem('orm_checks')!) as List)
            .cast<Map<String, Object?>>(),
      );
      final name = web.window.sessionStorage.getItem('orm_database')!;
      final recovered = await sqliteWeb(
        SqliteWebOptions.opfs(name: name, wasm: wasm, worker: worker),
      );
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
            final first = Migration.create('0001_browser', appSchema);
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
          () => sqliteWeb(
            SqliteWebOptions.memory(
              wasm: Uri.parse('/missing.wasm'),
              worker: worker,
            ),
          ),
        );
        await rejects(
          () => sqliteWeb(
            SqliteWebOptions.memory(
              wasm: wasm,
              worker: Uri.parse('/missing-worker.js'),
              openTimeout: const Duration(seconds: 2),
            ),
          ),
        );
        final healthy = await memory();
        await healthy.close();
      },
    );
    await check(
      'OPFS commit survives a closed worker and new connection',
      () async {
        final options = SqliteWebOptions.opfs(
          name: 'browser-${DateTime.now().millisecondsSinceEpoch}',
          wasm: wasm,
          worker: worker,
        );
        var persistent = await sqliteWeb(options);
        try {
          await initialize(persistent);
          await persistent.users.create(email: 'persisted');
          await rejects(() => sqliteWeb(options));
          expect(
            (await persistent.users.single()).email == 'persisted',
            'Failed competing open disturbed the owner',
          );
        } finally {
          await persistent.close();
        }
        persistent = await sqliteWeb(options);
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
    final persistent = await sqliteWeb(
      SqliteWebOptions.opfs(name: name, wasm: wasm, worker: worker),
    );
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
