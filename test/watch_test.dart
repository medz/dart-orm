import 'dart:async';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import '../example/schema.orm.dart';

Matcher code(String code) =>
    isA<OrmException>().having((e) => e.code, 'code', code);

void main() {
  test(
    'independent native SQLite workers require explicit notification',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'orm-watch-external-',
      );
      final db = await sqlite(
        SqliteOptions.file('${directory.path}/data.sqlite'),
      );
      final external = await sqlite(
        SqliteOptions.file('${directory.path}/data.sqlite'),
      );
      _Snapshots<String>? result;
      try {
        await Migrator(db.sql).apply([
          Migration.create('0001_initial', appSchema, dialect: db.dialect),
        ]);
        final user = await db.user.create(email: 'before');
        result = _Snapshots(db.user.select((u) => u.email).watch());
        expect(await result.next(), ['before']);
        await external.user.byId(user.id).patch(email: .set('external'));
        await db.execute(SqlCommand('SELECT 1'));
        await Future<void>.delayed(Duration.zero);
        expect(result.rows.length, 1);
        db.invalidate([userSchema]);
        expect(await result.next(), ['external']);
      } finally {
        await result?.close();
        await external.close();
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );
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
          schema: 'orm_watch_tests',
          maxConnections: 1,
        ),
        onQuery: observe,
      );
      await db.execute(
        SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_watch_tests'),
      );
      return db;
    });
  }
}

void runTests(
  String name,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open,
) {
  group('watch $name', () {
    late Database<Backend> db;
    final events = <QueryEvent>[];
    void Function(QueryEvent)? hook;
    final watches = <_Snapshots<Object?>>[];
    _Snapshots<R> watch<R>(Stream<List<R>> stream) {
      final snapshots = _Snapshots(stream);
      watches.add(snapshots);
      return snapshots;
    }

    setUp(() async {
      hook = null;
      db = await open((event) {
        events.add(event);
        hook?.call(event);
      });
      for (final table in ['posts', 'users', '_orm_migrations']) {
        await db.execute(SqlCommand('DROP TABLE IF EXISTS "$table"'));
      }
      await Migrator(db.sql).apply([
        Migration.create('0001_initial', appSchema, dialect: db.dialect),
      ]);
      events.clear();
    });
    tearDown(() async {
      for (final watch in watches) {
        await watch.close();
      }
      watches.clear();
      await db.close();
    });
    Future<void> barrier() async {
      await db.execute(SqlCommand('SELECT 1'));
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> post(int author, [String title = 'post']) => db.post.create(
      authorId: author,
      title: title,
      createdAt: DateTime.utc(2026),
    );

    test('lazy initial snapshot and relevant table invalidation', () async {
      final stream = db.user.select((u) => u.email).watch();
      await barrier();
      expect(events.where((e) => e.sql.contains('FROM "users"')), isEmpty);
      final result = watch(stream);
      expect(await result.next(), isEmpty);
      final user = await db.user.create(email: 'first');
      expect(await result.next(), ['first']);
      events.clear();
      await post(user.id);
      await barrier();
      expect(result.rows.length, 2);
      expect(
        events.where(
          (e) => e.sql.startsWith('SELECT') && e.sql.contains('FROM "users"'),
        ),
        isEmpty,
      );
      await db.user.byId(user.id).patch(email: .set('second'));
      expect(await result.next(), ['second']);
      await db.user.byId(user.id).delete().execute();
      expect(await result.next(), isEmpty);
    });

    test(
      'transactions publish one snapshot after commit and none on rollback',
      () async {
        final result = watch(
          db.user.orderBy((u) => [u.id.asc()]).select((u) => u.email).watch(),
        );
        expect(await result.next(), isEmpty);
        await db.transaction((tx) async {
          await tx.user.create(email: 'a');
          await tx.user.create(email: 'b');
          expect(result.rows.length, 1);
        });
        expect(await result.next(), ['a', 'b']);
        await expectLater(
          db.transaction((tx) async {
            await tx.user.create(email: 'rollback');
            throw StateError('rollback');
          }),
          throwsStateError,
        );
        await barrier();
        expect(result.rows.length, 2);
        expect(await db.user.count(), 2);
      },
    );

    test(
      'savepoint changes merge on release and disappear on rollback',
      () async {
        final user = await db.user.create(email: 'initial');
        final result = watch(db.user.select((u) => u.email).watch());
        expect(await result.next(), ['initial']);
        await db.transaction((tx) async {
          await expectLater(
            tx.savepoint((child) async {
              await child.user.byId(user.id).patch(email: .set('rolled-back'));
              throw StateError('recoverable');
            }),
            throwsStateError,
          );
          await tx.savepoint((child) => postIn(child, user.id));
        });
        await barrier();
        expect(result.rows.length, 1);
        await db.transaction((tx) async {
          await tx.savepoint((child) async {
            await child.savepoint(
              (nested) =>
                  nested.user.byId(user.id).patch(email: .set('committed')),
            );
          });
          expect(result.rows.length, 1);
        });
        expect(await result.next(), ['committed']);
      },
    );

    test(
      'failed statements, zero-row writes and conflict no-ops do not refresh',
      () async {
        final user = await db.user.create(email: 'unique');
        final result = watch(db.user.select((u) => u.email).watch());
        expect(await result.next(), ['unique']);
        await expectLater(db.user.create(email: 'unique'), throwsA(anything));
        await db.user.byId(999).patch(email: .set('absent'));
        await db.user
            .insert((u) => [u.email.set('unique')])
            .onConflictDoNothing()
            .execute();
        await expectLater(
          db.transaction((tx) async {
            await tx.user.byId(user.id).patch(email: .set('temporary'));
            try {
              await tx.execute(SqlCommand('SELECT broken_column FROM users'));
            } catch (_) {}
          }),
          throwsA(code('TRANSACTION.FAILED')),
        );
        await barrier();
        expect(result.rows.length, 1);
      },
    );

    test(
      'batch writes and upsert returning publish committed changes',
      () async {
        final result = watch(
          db.user.orderBy((u) => [u.id.asc()]).select((u) => u.email).watch(),
        );
        expect(await result.next(), isEmpty);
        final ids = await db.user
            .insertMany(['a', 'b', 'c'], (u, email) => [u.email.set(email)])
            .returning((u) => u.id)
            .get();
        expect(ids.length, 3);
        expect(await result.next(), ['a', 'b', 'c']);
        await db.user
            .insert((u) => [u.email.set('b'), u.score.set(7)])
            .onConflictUpdate(
              target: (u) => [u.email],
              set: (old, incoming) => [old.email.set('changed')],
            )
            .returning((u) => u.id)
            .single();
        expect(await result.next(), ['a', 'changed', 'c']);
      },
    );

    test('joined and nested batch relations track child writes', () async {
      final user = await db.user.create(email: 'author');
      final children = watch(
        db.user
            .select(
              (u) => u.posts
                  .orderBy((p) => [p.id.asc()])
                  .select(
                    (p) => (
                      p.title,
                      p.author.select((a) => a.email).required(),
                    ).map((title, author) => (title, author)),
                  )
                  .many(),
            )
            .watch(),
      );
      expect(await children.next(), [<(String, String)>[]]);
      await post(user.id);
      expect(await children.next(), [
        [('post', 'author')],
      ]);
      final authors = watch(
        db.post
            .select((p) => p.author.select((u) => u.email).required())
            .watch(),
      );
      expect(await authors.next(), ['author']);
      await db.user.byId(user.id).patch(email: .set('updated'));
      expect(await authors.next(), ['updated']);
      expect(await children.next(), [
        [('post', 'updated')],
      ]);
    });

    test(
      'relation predicates, SQL subqueries and CTE sources are dependencies',
      () async {
        final user = await db.user.create(email: 'a');
        final hasPosts = watch(
          db.user.where((u) => u.posts.any()).select((u) => u.email).watch(),
        );
        final total = db.post.select((p) => p.id.count()).scalar();
        final subquery = watch(db.user.select((u) => total).watch());
        final cte = db.post.select((p) => p.title).asCte('titles');
        final titles = watch(cte.query.watch());
        expect(await hasPosts.next(), isEmpty);
        expect(await subquery.next(), [0]);
        expect(await titles.next(), isEmpty);
        await post(user.id, 'dependency');
        expect(await hasPosts.next(), ['a']);
        expect(await subquery.next(), [1]);
        expect(await titles.next(), ['dependency']);
      },
    );

    test('declared cascade deletion invalidates a child-only query', () async {
      final user = await db.user.create(email: 'parent');
      await post(user.id);
      final result = watch(db.post.select((p) => p.title).watch());
      expect(await result.next(), ['post']);
      await db.user.byId(user.id).patch(email: .set('no cascade'));
      await barrier();
      expect(result.rows.length, 1);
      await db.user.byId(user.id).delete().execute();
      expect(await result.next(), isEmpty);
    });

    for (final action in ['CASCADE', 'SET NULL']) {
      test('$action tracks declared transitive deletion effects', () async {
        final id = Column('id', Codecs.integer);
        final root = TableSchema(
          'watch_root',
          columns: [id],
          primaryKey: ['id'],
        );
        final branch = TableSchema(
          'watch_branch',
          columns: [
            id,
            Column('parent', Codecs.integer.nullable(), nullable: true),
          ],
          primaryKey: ['id'],
          foreignKeys: [
            ForeignKey(['parent'], root.name, ['id'], onDelete: action),
          ],
        );
        final leaf = TableSchema(
          'watch_leaf',
          columns: [id, Column('parent', Codecs.integer)],
          primaryKey: ['id'],
          foreignKeys: [
            ForeignKey(['parent'], branch.name, ['id'], onDelete: 'CASCADE'),
          ],
        );
        final schemas = [root, branch, leaf];
        db.registerSchema(schemas);
        for (final command in createSchema(schemas, db.dialect)) {
          await db.execute(command);
        }
        try {
          await db.execute(SqlCommand('INSERT INTO watch_root VALUES (1)'));
          await db.execute(
            SqlCommand('INSERT INTO watch_branch VALUES (2, 1)'),
          );
          await db.execute(SqlCommand('INSERT INTO watch_leaf VALUES (3, 2)'));
          final branches = watch(db.table(_ids(branch)).watch());
          final leaves = watch(db.table(_ids(leaf)).watch());
          expect(await branches.next(), [2]);
          expect(await leaves.next(), [3]);
          await db.table(_ids(root)).delete().execute();
          expect(await branches.next(), action == 'CASCADE' ? isEmpty : [2]);
          if (action == 'CASCADE') {
            expect(await leaves.next(), isEmpty);
          } else {
            await barrier();
            expect(leaves.rows.length, 1);
            expect(
              (await db.execute(SqlCommand('SELECT parent FROM watch_branch')))
                  .rows,
              [
                [null],
              ],
            );
          }
          await branches.close();
          await leaves.close();
        } finally {
          for (final table in schemas.reversed) {
            await db.execute(SqlCommand('DROP TABLE "${table.name}"'));
          }
        }
      });
    }

    test(
      'explicit JOINs and joined CTE definitions track both physical sources',
      () async {
        final user = await db.user.create(email: 'a');
        await post(user.id);
        final alias = postTable.alias();
        final joined = watch(
          db.user
              .join(alias, on: (u, p) => u.id.equals(p.authorId))
              .select((_) => alias.fields.title)
              .watch(),
        );
        final cte = db.post
            .select(
              (p) => (p.authorId, p.title).map((id, title) => (id, title)),
            )
            .asCte('post_names');
        final cteAlias = cte.alias();
        final viaCte = watch(
          db.user
              .join(
                cteAlias,
                on: (u, c) => u.id.equals(c.ref((p) => p.authorId)),
              )
              .select((_) => cteAlias.fields.ref((p) => p.title))
              .watch(),
        );
        expect(await joined.next(), ['post']);
        expect(await viaCte.next(), ['post']);
        await db.post.byId(1).patch(title: .set('joined'));
        expect(await joined.next(), ['joined']);
        expect(await viaCte.next(), ['joined']);
      },
    );

    test('raw SQL declares changed and read tables; explicit invalidation follows transactions', () async {
      final user = await db.user.create(email: 'a');
      final count = sql<int>(
        ['(SELECT COUNT(*) FROM posts)'],
        [],
        Codecs.integer,
      );
      final result = watch(
        db.user.select((_) => count).watch(reads: [postSchema]),
      );
      expect(await result.next(), [0]);
      await post(user.id);
      expect(await result.next(), [1]);
      await db.execute(
        SqlCommand('DELETE FROM posts'),
        changedTables: [postSchema],
      );
      expect(await result.next(), [0]);
      await db.transaction((tx) async {
        tx.invalidate([postSchema]);
        expect(result.rows.length, 3);
      });
      expect(await result.next(), [0]);
      await expectLater(
        db.transaction((tx) async {
          tx.invalidate([postSchema]);
          throw StateError('rollback invalidation');
        }),
        throwsStateError,
      );
      await barrier();
      expect(result.rows.length, 4);
    });

    test(
      'paused listeners coalesce writes and stop fetching until resumed',
      () async {
        final result = watch(db.user.select((u) => u.email).watch());
        expect(await result.next(), isEmpty);
        result.subscription.pause();
        events.clear();
        for (var i = 0; i < 5; i++) {
          await db.user.create(email: '$i');
        }
        await barrier();
        expect(result.rows.length, 1);
        expect(
          events.where(
            (e) => e.sql.startsWith('SELECT') && e.sql.contains('FROM "users"'),
          ),
          isEmpty,
        );
        result.subscription.resume();
        expect((await result.next()).length, 5);
        expect(result.rows.length, 2);
      },
    );

    test(
      'invalidation during a read suppresses the stale snapshot and refetches',
      () async {
        await db.user.create(email: 'before');
        final reading = Completer<void>(), release = Completer<void>();
        final intercepted = Database(
          _AfterReadDriver(db.driver, reading, release),
        );
        final result = watch(intercepted.user.select((u) => u.email).watch());
        await reading.future;
        // The connection was released after producing the old rows, while the
        // read's Future is deliberately held. A second view shares this driver.
        final other = Database(intercepted.driver);
        await other.user.byId(1).patch(email: .set('after'));
        release.complete();
        expect(await result.next(), ['after']);
        expect(result.rows.length, 1);
      },
    );

    test(
      'decoding errors are reported and a later write can recover',
      () async {
        final user = await db.user.create(email: 'bad');
        final result = watch(
          db.user
              .select(
                (u) => u.email.map((value) {
                  if (value == 'bad') throw const FormatException('bad value');
                  return value;
                }),
              )
              .watch(),
        );
        await result.waitForError();
        expect(result.errors.single, isA<FormatException>());
        await db.user.byId(user.id).patch(email: .set('good'));
        expect(await result.next(), ['good']);
      },
    );

    test(
      'separate subscriptions and views of one driver receive changes',
      () async {
        final other = Database(db.driver);
        final stream = db.user.select((u) => u.email).watch();
        final one = watch(stream);
        final two = watch(other.user.select((u) => u.email).watch());
        expect(await one.next(), isEmpty);
        expect(await two.next(), isEmpty);
        await other.user.create(email: 'shared');
        expect(await one.next(), ['shared']);
        expect(await two.next(), ['shared']);
        await one.close();
        await db.user.byId(1).patch(email: .set('still open'));
        expect(await two.next(), ['still open']);
        expect(one.rows.length, 2);
      },
    );

    test('watching leased sessions is rejected and cancelled tokens close the stream', () async {
      await db.transaction((tx) async {
        final result = watch(tx.user.watch());
        await result.waitForError();
        expect(result.errors.single, code('WATCH.SESSION'));
        await result.done.future;
      });
      final cancellation = CancellationToken();
      final result = watch(
        db.user.watch(options: ExecutionOptions(cancellation: cancellation)),
      );
      expect(await result.next(), isEmpty);
      cancellation.cancel();
      await result.done.future;
      expect(result.errors.single, code('OPERATION.CANCELLED'));
    });

    test(
      'database close finishes watchers even when a listener is paused',
      () async {
        final result = watch(db.user.watch());
        expect(await result.next(), isEmpty);
        result.subscription.pause();
        await db.close().timeout(const Duration(seconds: 2));
        result.subscription.resume();
        await result.done.future;
        final late = watch(db.user.watch());
        await late.waitForError();
        expect(late.errors.single, code('SESSION.CLOSED'));
      },
    );

    test('cancelling an active watched query interrupts SQL and releases its lease', () async {
      if (!db.capabilities.cancellation) {
        markTestSkipped(
          'This SQLite build does not expose native statement interruption.',
        );
        return;
      }
      await db.user.create(email: 'a');
      final started = Completer<void>();
      final expression = db.dialect == .postgres
          ? sql<int>(['(SELECT 1 FROM pg_sleep(20))'], [], Codecs.integer)
          : sql<int>(
              [
                '(WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1000000000) SELECT sum(x) FROM n)',
              ],
              [],
              Codecs.integer,
            );
      // Query observation completes only after execution, so a short timer
      // requests cancellation while the database is doing deliberately long work.
      final result = watch(db.user.select((_) => expression).watch());
      Timer(const Duration(milliseconds: 40), () => started.complete());
      await started.future;
      await result.close().timeout(const Duration(seconds: 3));
      expect(result.rows, isEmpty);
      expect(result.errors, isEmpty);
      expect(await db.user.count(), 1);
      expect(events.any((e) => e.error != null), true);
    });

    test('unsupported watch deadlines fail before SQL and ordinary watches remain usable', () async {
      if (db.capabilities.statementTimeout) {
        markTestSkipped('This driver supports statement deadlines.');
        return;
      }
      final rejected = watch(
        db.user.watch(
          options: const ExecutionOptions(timeout: Duration(milliseconds: 40)),
        ),
      );
      await rejected.waitForError();
      expect(rejected.errors.single, code('CAPABILITY.CANCEL'));
      expect(rejected.rows, isEmpty);
      expect(events, isEmpty);
      await rejected.close();

      final ordinary = watch(db.user.select((u) => u.email).watch());
      expect(await ordinary.next(), isEmpty);
      await db.user.create(email: 'still-watching');
      expect(await ordinary.next(), ['still-watching']);
      expect(ordinary.errors, isEmpty);
    });

    if (name == 'postgres') {
      test(
        'lost commit acknowledgement triggers a conservative re-read',
        () async {
          final uncertain = Database(_CommitAckDriver(db.driver));
          final result = watch(uncertain.user.select((u) => u.email).watch());
          expect(await result.next(), isEmpty);
          await expectLater(
            uncertain.transaction((tx) => tx.user.create(email: 'committed')),
            throwsA(code('TRANSACTION.COMMIT')),
          );
          expect(await result.next(), ['committed']);
          expect((await db.user.single()).email, 'committed');
        },
      );

      test('independent connections require an explicit external-write notification', () async {
        final user = await db.user.create(email: 'before');
        final result = watch(db.user.select((u) => u.email).watch());
        expect(await result.next(), ['before']);
        final external = await open((_) {});
        try {
          await external.user.byId(user.id).patch(email: .set('external'));
          await barrier();
          expect(result.rows.length, 1);
          db.invalidate([userSchema]);
          expect(await result.next(), ['external']);
        } finally {
          await external.close();
        }
      });
    }
  });
}

Future<void> postIn(Database<Backend> db, int user) async {
  await db.post.create(
    authorId: user,
    title: 'unrelated',
    createdAt: DateTime.utc(2026),
  );
}

final class _Snapshots<R> {
  final List<List<R>> rows = [];
  final List<Object> errors = [];
  final done = Completer<void>();
  late final StreamSubscription<List<R>> subscription;
  Completer<void>? _changed;
  int _next = 0;
  _Snapshots(Stream<List<R>> stream) {
    subscription = stream.listen(
      (value) {
        rows.add(value);
        _changed?.complete();
        _changed = null;
      },
      onError: (Object error) {
        errors.add(error);
        _changed?.complete();
        _changed = null;
      },
      onDone: () {
        done.complete();
        _changed?.complete();
        _changed = null;
      },
    );
  }
  Future<List<R>> next() async {
    while (rows.length <= _next) {
      if (done.isCompleted) throw StateError('Watch ended: $errors');
      await (_changed ??= Completer<void>()).future.timeout(
        const Duration(seconds: 5),
      );
    }
    return rows[_next++];
  }

  Future<void> waitForError() async {
    while (errors.isEmpty) {
      await (_changed ??= Completer<void>()).future.timeout(
        const Duration(seconds: 5),
      );
    }
  }

  Future<void> close() => subscription.cancel();
}

/// Hold exactly one completed read after the underlying connection is released.
final class _AfterReadDriver(
  final Driver<Backend> inner,
  final Completer<void> reading,
  final Completer<void> release,
) implements Driver<Backend> {
  bool held = false;
  @override
  Capabilities get capabilities => inner.capabilities;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) async {
    final value = await inner.run(action);
    if (!held) {
      held = true;
      reading.complete();
      await release.future;
    }
    return value;
  }

  @override
  Future<void> close() => inner.close();
}

Table<int, _Ids> _ids(TableSchema schema) =>
    Table(schema, _Ids.new, (f) => f.id);

final class _Ids extends Fields {
  _Ids(super.table);
  late final id = column(Column('id', Codecs.integer));
}

final class _CommitAckDriver(final Driver<Backend> inner)
    implements Driver<Backend> {
  bool armed = true;
  @override
  Capabilities get capabilities => inner.capabilities;
  @override
  Future<R> run<R>(Future<R> Function(SqlConnection) action) =>
      inner.run((connection) => action(_CommitAckConnection(connection, this)));
  @override
  Future<void> close() => inner.close();
}

final class _CommitAckConnection(
  final SqlConnection inner,
  final _CommitAckDriver driver,
) implements SqlConnection {
  @override
  bool? get transactionActive => inner.transactionActive;
  @override
  Future<SqlResult> execute(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final result = await inner.execute(command, options: options);
    if (command.sql == 'COMMIT' && driver.armed) {
      driver.armed = false;
      throw StateError('Commit executed; acknowledgement lost');
    }
    return result;
  }

  @override
  Future<SqlCursor> openCursor(
    SqlCommand command, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => inner.openCursor(command, options: options);
  @override
  Future<void> invalidate() => inner.invalidate();
}
