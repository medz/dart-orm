import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/named_sql/queries.queries.dart';

const source = 'test/support/named_sql/queries.dart';
const manifest = 'test/support/named_sql/queries.queries.json';
final posts = TableSchema(
  'posts',
  columns: [Column('author', Codecs.text), Column('points', Codecs.integer)],
);

GeneratedQueries fixed(
  SqlDialect dialect,
  String sql, {
  String type = 'integer',
  String column = 'n',
}) => GeneratedQueries('', {
  'queries': [
    {
      'name': 'fixed',
      'parameters': <Map<String, Object?>>[],
      'columns': [
        {'name': column, 'type': type, 'nullable': false},
      ],
      'sql': {dialect.name: sql},
    },
  ],
});

void main() {
  test('template binds repeated names once and preserves quotes/comments', () {
    for (final dialect in SqlDialect.values) {
      final template = SqlTemplate(
        "SELECT :input AS n, ':ignored;''text' AS s, \"quoted:field\" -- :line\n"
        '/* :comment */ FROM data WHERE n = :input; -- trailing',
        dialect: dialect,
      );
      final command = template.compile(
        Capabilities(dialect: dialect, maxParameters: 1),
        {'input': value(3, Codecs.integer)},
      );
      expect(template.parameters, {'input'});
      expect(command.parameters, [3]);
      expect(command.sql, contains("':ignored;''text'"));
      expect(command.sql, endsWith(' -- trailing'));
    }
    final pg = SqlTemplate(
      r'''SELECT :n::bigint, $tag$:ignored; '$tag$, E'\:ignored', payload ? 'key' /* nested /* :ignored */ end */''',
      dialect: SqlDialect.postgres,
    );
    expect(pg.parameters, {'n'});
    final sqlite = SqlTemplate(
      'SELECT :n, [name:ignored], `name:ignored`',
      dialect: SqlDialect.sqlite,
    );
    expect(sqlite.parameters, {'n'});
  });

  test(
    'templates reject ambiguous bindings and incomplete or multiple statements',
    () {
      for (final dialect in SqlDialect.values) {
        for (final sql in [
          "SELECT 'unfinished",
          'SELECT 1 /* incomplete',
          'SELECT 1; SELECT 2',
          'DELETE FROM data',
          r'SELECT $1',
          '-- only a comment',
        ]) {
          expect(
            () => SqlTemplate(sql, dialect: dialect),
            throwsA(isA<OrmException>()),
            reason: sql,
          );
        }
        final template = SqlTemplate('SELECT :n', dialect: dialect);
        final caps = Capabilities(dialect: dialect, maxParameters: 0);
        expect(() => template.compile(caps, {}), throwsA(isA<OrmException>()));
        expect(
          () => template.compile(caps, {'n': value(1, Codecs.integer)}),
          throwsA(isA<OrmException>()),
        );
        expect(
          () => template.compile(caps, {'n': value(1, Codecs.integer).plus(2)}),
          throwsA(isA<OrmException>()),
        );
      }
      for (final sql in ['SELECT ?1', 'SELECT @name']) {
        expect(
          () => SqlTemplate(sql, dialect: SqlDialect.sqlite),
          throwsA(isA<OrmException>()),
        );
      }
      expect(
        () => SqlTemplate(r"SELECT '\'", dialect: SqlDialect.postgres),
        throwsA(isA<OrmException>()),
      );
      expect(
        () => SqlTemplate(r'SELECT $$unfinished', dialect: SqlDialect.postgres),
        throwsA(isA<OrmException>()),
      );
    },
  );

  test('generated client and manifest are deterministic and fresh', () async {
    final generated = await generateQueries(source);
    expect(
      generated.dart,
      await File('test/support/named_sql/queries.queries.dart').readAsString(),
    );
    expect(generated.manifest, jsonDecode(await File(manifest).readAsString()));
    expect((await readGeneratedQueries(manifest)).dart, generated.dart);
  });

  for (final dialect in SqlDialect.values) {
    group(
      dialect.name,
      () {
        late Database<Backend> db;
        setUp(() async {
          if (dialect == SqlDialect.sqlite) {
            db = await sqlite(const SqliteOptions.memory());
          } else {
            db = postgres(
              PostgresOptions(
                url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
                tls: PostgresTls.disable,
                schema: 'orm_named_sql_tests',
              ),
            );
            await db.execute(
              SqlCommand('DROP SCHEMA IF EXISTS orm_named_sql_tests CASCADE'),
            );
            await db.execute(SqlCommand('CREATE SCHEMA orm_named_sql_tests'));
          }
          await db.execute(
            SqlCommand(
              'CREATE TABLE posts (author TEXT NOT NULL, points BIGINT NOT NULL)',
            ),
          );
          await db.execute(
            SqlCommand("INSERT INTO posts VALUES ('a', 1), ('a', 3), ('b', 7)"),
          );
        });
        tearDown(() => db.close());

        test(
          'typed parameters, projection and repeated nullable bindings compose',
          () async {
            final query = db
                .authorStats(minimum: 0)
                .orderBy((s) => [s.author.asc()]);
            expect(await query.get(), [
              (author: 'a', postCount: 2, points: 4),
              (author: 'b', postCount: 1, points: 7),
            ]);
            expect(await db.authorStats(minimum: 2, author: 'a').single(), (
              author: 'a',
              postCount: 1,
              points: 3,
            ));
            expect(
              await query
                  .where((s) => s.points.gt(4))
                  .select(
                    (s) => (
                      s.author,
                      s.points,
                    ).map((author, points) => (author, points)),
                  )
                  .get(),
              [('b', 7)],
            );
            expect(
              await db.authorStats(minimum: 0, author: "a' OR 1=1 --").get(),
              isEmpty,
            );
            expect(await db.constant().single(), (n: 42));
          },
        );

        test(
          'native numeric and temporal codecs survive binding and streaming',
          () async {
            final instant = DateTime.utc(2024, 1, 2, 3, 4, 5, 6, 7);
            final amount = Decimal.parse('12345678901234567890.00000000001');
            final day = LocalDate.parse('0001-01-01 BC');
            final query = db.echo(
              value: ':ignored; " --',
              at: instant,
              amount: amount,
              day: day,
            );
            expect(await query.single(), (
              value: ':ignored; " --',
              at: instant,
              amount: amount,
              day: day,
            ));
            expect(await query.select((q) => q.amount).stream().toList(), [
              amount,
            ]);
          },
        );

        test(
          'CTEs and unions retain distinct query arguments and field identity',
          () async {
            final a = db.authorStats(minimum: 0, author: 'a');
            final b = db.authorStats(minimum: 0, author: 'b');
            final cte = a.asCte('author_subset');
            expect(
              await cte.query.select((s) => s.ref((r) => r.points)).single(),
              4,
            );
            expect(
              await a
                  .select((s) => s.author)
                  .unionAll(b.select((s) => s.author))
                  .get(),
              ['a', 'b'],
            );
            expect(
              await db
                  .constant()
                  .select((c) => a.select((s) => s.points).take(1).scalar())
                  .single(),
              4,
            );
          },
        );

        test('transactions see pending writes and rollback normally', () async {
          await expectLater(
            db.transaction((tx) async {
              await tx.execute(
                SqlCommand("INSERT INTO posts VALUES ('a', 10)"),
              );
              expect(
                (await tx.authorStats(minimum: 0, author: 'a').single()).points,
                14,
              );
              throw StateError('rollback');
            }),
            throwsStateError,
          );
          expect(
            (await db.authorStats(minimum: 0, author: 'a').single()).points,
            4,
          );
        });

        test('named sources reject table mutations and require explicit watch reads', () async {
          await expectLater(
            db
                .authorStats(minimum: 0)
                .update((s) => [s.points.set(1)])
                .execute(),
            throwsA(isA<OrmException>()),
          );
          await expectLater(
            db.authorStats(minimum: 0).watch().first,
            throwsA(
              isA<OrmException>().having((e) => e.code, 'code', 'WATCH.READS'),
            ),
          );
          final snapshots = StreamIterator(
            db.authorStats(minimum: 0, author: 'a').watch(reads: [posts]),
          );
          try {
            expect(await snapshots.moveNext(), true);
            expect(snapshots.current.single.points, 4);
            final next = snapshots.moveNext();
            await db.execute(
              SqlCommand("INSERT INTO posts VALUES ('a', 2)"),
              changedTables: [posts],
            );
            expect(await next.timeout(const Duration(seconds: 3)), true);
            expect(snapshots.current.single.points, 6);
          } finally {
            await snapshots.cancel();
          }
        });

        test('native checks accept declared shape and preserve prepared-statement state', () async {
          final result = await checkSqlQueries(
            db,
            await generateQueries(source),
          );
          expect(result.length, dialect == SqlDialect.sqlite ? 3 : 4);
          expect(
            result.every(
              (r) =>
                  r['structureChecked'] == true &&
                  r['nullabilityChecked'] == false,
            ),
            true,
          );
          if (dialect == SqlDialect.postgres) {
            final left = await db.execute(
              SqlCommand(
                "SELECT COUNT(*) FROM pg_catalog.pg_prepared_statements WHERE name LIKE '_orm_check_%'",
              ),
            );
            expect(left.rows.single.single, 0);
            expect(await (db as Database<Postgres>).postgresOnly().single(), (
              n: 42,
            ));
          }
        });

        test('native checks reject syntax, missing tables and missing result aliases', () async {
          for (final sql in [
            'SELECT FROM',
            'SELECT n FROM missing_table',
            'SELECT 1 AS wrong',
          ]) {
            await expectLater(
              checkSqlQueries(db, fixed(dialect, sql)),
              throwsA(isA<GenerationException>()),
              reason: sql,
            );
          }
          if (dialect == SqlDialect.postgres) {
            await expectLater(
              checkSqlQueries(db, fixed(dialect, "SELECT 'text'::text AS n")),
              throwsA(isA<GenerationException>()),
            );
          }
          expect((await db.constant().single()).n, 42);
        });

        test('native checks do not evaluate application expressions', () async {
          final sql = dialect == SqlDialect.sqlite
              ? 'SELECT abs(-9223372036854775808) AS n'
              : 'SELECT 1 / 0 AS n';
          expect(await checkSqlQueries(db, fixed(dialect, sql)), hasLength(1));
          await expectLater(db.execute(SqlCommand(sql)), throwsA(anything));
          if (dialect == SqlDialect.postgres) {
            await db.execute(SqlCommand('CREATE SEQUENCE query_check_counter'));
            await checkSqlQueries(
              db,
              fixed(dialect, "SELECT nextval('query_check_counter') AS n"),
            );
            expect(
              (await db.execute(
                SqlCommand('SELECT is_called FROM query_check_counter'),
              )).rows.single.single,
              false,
            );
          }
        });
      },
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES for native PostgreSQL checks.'
          : false,
    );
  }
}
