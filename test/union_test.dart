@Tags(['database'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';
import 'package:test/test.dart';

import 'support/tables.dart';

Matcher code(String expected) =>
    isA<OrmException>().having((e) => e.code, 'code', expected);

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
          schema: 'orm_union_tests',
          maxConnections: 1,
        ),
        onQuery: observe,
      );
      await db.execute(
        SqlCommand('CREATE SCHEMA IF NOT EXISTS orm_union_tests'),
      );
      return db;
    });
  }
}

void runTests(
  String name,
  Future<Database<Backend>> Function(void Function(QueryEvent)) open,
) {
  group('union $name', () {
    late Database<Backend> db;
    final events = <QueryEvent>[];
    setUp(() async {
      db = await open(events.add);
      await db.execute(SqlCommand('DROP TABLE IF EXISTS posts'));
      await db.execute(SqlCommand('DROP TABLE IF EXISTS users'));
      for (final command in createSchema([
        usersSchema,
        postsSchema,
      ], db.dialect)) {
        await db.execute(command);
      }
      for (final email in ['one', 'two', 'three']) {
        await db.table(users).createRow((u) => [u.email.set(email)]);
      }
      await db
          .table(postsTable)
          .createRow((p) => [p.authorId.set(1), p.title.set('one')]);
      await db
          .table(postsTable)
          .createRow((p) => [p.authorId.set(1), p.title.set('post')]);
      events.clear();
    });
    tearDown(() => db.close());

    test('SQL duplicate and NULL semantics use one statement', () async {
      final emails = db.table(users).select((u) => u.email);
      final titles = db.table(postsTable).select((p) => p.title);
      expect(
        await emails.union(titles).get(),
        unorderedEquals(['one', 'two', 'three', 'post']),
      );
      expect(events.length, 1);
      expect(await emails.unionAll(titles).count(), 5);
      expect(
        await db
            .table(users)
            .select((u) => u.nickname)
            .union(db.table(postsTable).select((p) => p.tag))
            .get(),
        [null],
      );
    });

    test(
      'heterogeneous records map only after SQL union and final pagination',
      () async {
        final result = db
            .table(users)
            .select((u) => (u.id, u.email).row)
            .unionAll(db.table(postsTable).select((p) => (p.id, p.title).row))
            .orderBy(
              (u) => [u.ref((u) => u.id).asc(), u.ref((u) => u.email).asc()],
            );
        final List<(int, String)> rows = await result.get();
        expect(rows, [
          (1, 'one'),
          (1, 'one'),
          (2, 'post'),
          (2, 'two'),
          (3, 'three'),
        ]);
        var mapped = 0;
        final selected = result
            .skip(1)
            .take(2)
            .select(
              (u) =>
                  (u.ref((u) => u.id), u.ref((u) => u.email)).map((id, label) {
                    mapped++;
                    return (id: id, label: label.toUpperCase());
                  }),
            );
        selected.compile();
        expect(mapped, 0);
        expect(await selected.get(), [
          (id: 1, label: 'ONE'),
          (id: 2, label: 'POST'),
        ]);
        expect(mapped, 2);
        final mappedRows = result
            .take(1)
            .map((row) => (id: row.$1, label: row.$2));
        expect(await mappedRows.single(), (id: 1, label: 'one'));
        expect(
          () => mappedRows.union(mappedRows),
          throwsA(code('QUERY.UNION_SELECTION')),
        );
      },
    );

    test(
      'operand limits, order, parameters and final filter stay scoped',
      () async {
        const hostile = "x' OR 1=1 --";
        final left = db
            .table(users)
            .where((u) => u.email.ne(hostile))
            .orderBy((u) => [u.id.desc()])
            .take(1)
            .select((u) => u.email);
        final right = db
            .table(postsTable)
            .where((p) => p.title.ne('post'))
            .orderBy((p) => [p.id.asc()])
            .take(1)
            .select((p) => p.title);
        final query = left
            .unionAll(right)
            .where((u) => u.ref((u) => u.email).ne('one'));
        expect(query.compile().sql, isNot(contains(hostile)));
        expect(query.compile().parameters, contains(hostile));
        expect(await query.get(), ['three']);
        expect(await left.get(), ['three']);
        expect(await right.get(), ['one']);
      },
    );

    test('repeated SQL expressions preserve positional columns', () async {
      final left = db
          .table(users)
          .where((u) => u.id.eq(1))
          .select((u) => (u.id, u.id).row);
      final right = db
          .table(users)
          .where((u) => u.id.eq(2))
          .select((u) => (u.id, u.score).row);
      expect(
        await left.unionAll(right).get(),
        unorderedEquals([(1, 1), (2, 0)]),
      );
      expect(
        await left.asCte('repeated').query.unionAll(right).get(),
        unorderedEquals([(1, 1), (2, 0)]),
      );
    });

    test(
      'nested sets preserve association, CTE exports and streaming',
      () async {
        final a = db
            .table(users)
            .where((u) => u.id.eq(1))
            .select((u) => u.email);
        final b = db
            .table(postsTable)
            .where((p) => p.id.eq(1))
            .select((p) => p.title);
        final c = db
            .table(users)
            .where((u) => u.id.eq(2))
            .select((u) => u.email);
        expect(
          await a.unionAll(b).union(c).get(),
          unorderedEquals(['one', 'two']),
        );
        expect(
          await a.unionAll(b.union(c)).get(),
          unorderedEquals(['one', 'one', 'two']),
        );
        final cte = a.unionAll(b).asCte('names');
        final exported = cte.query.select(
          (c) => c.ref((u) => u.ref((u) => u.email)),
        );
        expect(await exported.stream(batchSize: 1).toList(), ['one', 'one']);
        expect(await cte.query.unionAll(c).count(), 3);
      },
    );

    test(
      'same CTE names in distinct operands stay in separate scopes',
      () async {
        final a = db
            .table(users)
            .select((u) => (u.id, u.email).row)
            .asCte('same');
        final b = db
            .table(postsTable)
            .select((p) => (p.id, p.title).row)
            .asCte('same');
        expect(await a.query.union(b.query).count(), 4);
        final joined = a.query.unionAll(b.query).asCte('combined').alias();
        final source = db
            .table(users)
            .join(
              joined,
              on: (u, c) =>
                  u.id.equals(c.ref((u) => u.ref((c) => c.ref((u) => u.id)))),
            );
        expect(await source.count(), 5);
      },
    );

    test(
      'SQL scalar, IN subqueries, aggregate and zero-row results compose',
      () async {
        final query = db
            .table(users)
            .where((u) => u.id.eq(1))
            .select((u) => u.id)
            .union(db.table(postsTable).select((p) => p.authorId));
        expect(
          await db.table(users).where((u) => u.id.isInQuery(query)).count(),
          1,
        );
        expect(
          await db
              .table(users)
              .take(1)
              .select((u) => query.take(1).scalar())
              .single(),
          1,
        );
        expect(await query.select((u) => u.ref((u) => u.id).sum()).single(), 1);
        expect(await query.take(0).exists(), false);
        expect(await query.take(0).get(), isEmpty);
      },
    );

    test('grouped branches and window branches remain SQL queries', () async {
      final grouped = db.table(users).select((u) => u.id.count());
      final window = db
          .table(postsTable)
          .orderBy((p) => [p.id.asc()])
          .take(1)
          .select((p) => rowNumber(orderBy: [p.id.asc()]));
      expect(await grouped.unionAll(window).get(), unorderedEquals([3, 1]));
      final groups = db
          .table(users)
          .groupBy((u) => [u.score])
          .having((u) => u.id.count().gt(1))
          .select((u) => (u.score, u.id.count()).row);
      final postGroups = db
          .table(postsTable)
          .groupBy((p) => [p.authorId])
          .select((p) => (p.authorId, p.id.count()).row);
      expect(
        await groups.unionAll(postGroups).get(),
        unorderedEquals([(0, 3), (1, 2)]),
      );
      expect(await db.table(users).select((u) => u.id.average()).single(), 2.0);
    });

    test('bound constant projections retain Dart types', () async {
      final one = db
          .table(users)
          .take(1)
          .select((u) => value(7, Codecs.integer));
      final two = db.table(postsTable).take(1).select((p) => p.id);
      expect(await one.unionAll(two).get(), unorderedEquals([7, 1]));
      expect(await one.unionAll(one).get(), [7, 7]);
      final nulls = db
          .table(users)
          .take(1)
          .select((u) => value(null, Codecs.text.nullable()));
      expect(
        await nulls.union(db.table(postsTable).select((p) => p.tag)).get(),
        [null],
      );
      final values = db
          .table(users)
          .take(1)
          .select(
            (u) => (
              value(1.5, Codecs.real),
              value(true, Codecs.boolean),
              value(BigInt.parse('1234567890123456789012345'), Codecs.bigint),
              value(DateTime.utc(2026), Codecs.dateTime),
              value(Uint8List.fromList([1, 2, 3]), Codecs.bytes),
              value(const SqlJson(null), Codecs.jsonDocument),
            ).row,
          );
      final row = (await values.union(values).single());
      expect(
        (row.$1, row.$2, row.$3, row.$4),
        (
          1.5,
          true,
          BigInt.parse('1234567890123456789012345'),
          DateTime.utc(2026),
        ),
      );
      expect(row.$5, [1, 2, 3]);
      expect(row.$6.value, null);
      expect(
        await db
            .table(users)
            .take(1)
            .select((u) => value(9, Codecs.integer))
            .single(),
        9,
      );
    });

    test('Dart maps and relation selections are rejected before execution', () {
      final a = db
          .table(users)
          .select((u) => u.email.map((e) => e.toUpperCase()));
      final b = db
          .table(postsTable)
          .select((p) => p.title.map((e) => e.toLowerCase()));
      expect(() => a.union(b), throwsA(code('QUERY.UNION_SELECTION')));
      expect(
        () => db.table(users).union(db.table(users)),
        throwsA(code('QUERY.UNION_SELECTION')),
      );
      final relation = db
          .table(users)
          .select((u) => u.posts.select((p) => p.title).many());
      expect(
        () => relation.union(relation),
        throwsA(code('QUERY.UNION_SELECTION')),
      );
      expect(
        () => a.asCte('mapped').query.union(b),
        throwsA(code('QUERY.UNION_SELECTION')),
      );
      expect(events, isEmpty);
    });

    test('codecs and nullability cannot silently change across operands', () {
      final a = db.table(users).select<Object?>((u) => u.email);
      final b = db.table(users).select<Object?>((u) => u.id);
      expect(() => a.union(b), throwsA(code('QUERY.UNION_CODEC')));
      expect(
        () => a.union(db.table(users).select<Object?>((u) => u.nickname)),
        throwsA(code('QUERY.UNION_CODEC')),
      );
      final custom = Codecs.text.map<String>((v) => v.toUpperCase(), (v) => v);
      final encoded = db
          .table(users)
          .select<Object?>((u) => sql(['', ''], [u.email], custom));
      expect(() => a.union(encoded), throwsA(code('QUERY.UNION_CODEC')));
      expect(events, isEmpty);
    });

    test('shared domain codecs work, and nullable wrappers retain decoding semantics', () async {
      final codec = Codecs.text.map<_Label>(_Label.new, (v) => v.text);
      final left = db
          .table(users)
          .select((u) => sql(['', ''], [u.email], codec));
      final right = db
          .table(postsTable)
          .select((p) => sql(['', ''], [p.title], codec));
      expect(
        (await left.union(right).get()).map((v) => v.text),
        unorderedEquals(['one', 'two', 'three', 'post']),
      );
      final a = db
          .table(users)
          .select((u) => sql(['', ''], [u.nickname], codec.nullable()));
      final b = db
          .table(postsTable)
          .select((p) => sql(['', ''], [p.tag], codec.nullable().nullable()));
      expect(await a.union(b).get(), [null]);
      final nullable = Codec<String?>(
        'text',
        (v) => v == null ? 'missing' : v as String,
        (v) => v,
      );
      final direct = db
          .table(users)
          .select((u) => sql(['', ''], [u.nickname], nullable));
      final wrapped = db
          .table(users)
          .select((u) => sql(['', ''], [u.nickname], nullable.nullable()));
      expect(() => direct.union(wrapped), throwsA(code('QUERY.UNION_CODEC')));
      expect(await direct.take(1).get(), ['missing']);
      expect(await wrapped.take(1).get(), [null]);
    });

    test('export references and outer join nullability are guarded', () async {
      final joined = users.alias();
      final left = db
          .table(postsTable)
          .leftJoin(joined, on: (p, u) => p.id.equals(u.id))
          .select((p) => joined.nullable(joined.fields.email));
      final right = db.table(users).select((u) => u.nickname);
      final result = left.unionAll(right);
      expect(await result.count(), 5);
      expect(
        () => result.select((u) => u.ref((_) => joined.fields.email)),
        throwsA(code('QUERY.NULLABILITY')),
      );
      expect(
        () => result.select((u) => u.ref((p) => p.title)),
        throwsA(code('QUERY.UNION_COLUMN')),
      );
      final unsafe = db
          .table(postsTable)
          .leftJoin(joined, on: (p, u) => p.id.equals(u.id))
          .select((p) => joined.fields.email);
      events.clear();
      expect(
        () => unsafe.union(db.table(users).select((u) => u.email)).compile(),
        throwsA(code('QUERY.NULLABILITY')),
      );
      expect(events, isEmpty);
    });

    test('compound mutations and mixed sessions fail before SQL', () async {
      final source = db.table(users).select((u) => u.email);
      final query = source.union(source);
      expect(() => query.delete().compile(), throwsA(code('MUTATION.QUERY')));
      expect(
        () => query.seekAfter((u) => [u.ref((u) => u.email).cursor('one')]),
        throwsA(code('QUERY.CURSOR')),
      );
      await db.transaction((tx) async {
        expect(
          () => source.union(tx.table(users).select((u) => u.email)),
          throwsA(code('QUERY.UNION_SESSION')),
        );
        final t = tx.table(users).select((u) => u.email);
        expect(await t.union(t).count(), 3);
      });
    });

    test('all record arities use typed SQL decoding', () async {
      final base = db.table(users).where((u) => u.id.eq(1));
      final a = base.select((u) => (u.id, u.email, u.nickname).row);
      final b = base.select((u) => (u.id, u.email, u.nickname, u.score).row);
      final c = base.select(
        (u) => (u.id, u.email, u.nickname, u.score, u.id).row,
      );
      final d = base.select(
        (u) => (u.id, u.email, u.nickname, u.score, u.id, u.email).row,
      );
      expect(await a.union(a).single(), (1, 'one', null));
      expect(await b.union(b).single(), (1, 'one', null, 0));
      expect(await c.union(c).single(), (1, 'one', null, 0, 1));
      expect(await d.union(d).single(), (1, 'one', null, 0, 1, 'one'));
    });

    test('subscription observes committed changes in both operands', () async {
      final query = db
          .table(users)
          .select((u) => u.email)
          .union(db.table(postsTable).select((p) => p.title));
      final iterator = StreamIterator(query.watch());
      try {
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        expect(iterator.current.length, 4);
        await db
            .table(postsTable)
            .where((p) => p.id.eq(2))
            .update((p) => [p.title.set('changed')])
            .execute();
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        expect(iterator.current, contains('changed'));
        await db.transaction((tx) async {
          await tx
              .table(users)
              .where((u) => u.id.eq(2))
              .update((u) => [u.email.set('committed')])
              .execute();
        });
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          true,
        );
        expect(iterator.current, contains('committed'));
      } finally {
        await iterator.cancel();
      }
    });
  }, tags: name);
}

final class _Label(final String text);
