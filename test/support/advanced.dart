import 'package:orm/orm.dart';
import 'package:test/test.dart';

import 'tables.dart';

void advancedScenarios(Database<Backend> Function() database) {
  test(
    'CTEs preserve SQL column identity through mapped projections',
    () async {
      final db = database();
      final counts = db
          .table(postsTable)
          .groupBy((p) => [p.authorId])
          .select(
            (p) => (
              p.authorId,
              p.id.count(),
            ).map((id, count) => (id: id, count: count)),
          )
          .asCte('post_counts');
      final rows = await counts.query
          .where((c) => c.ref((p) => p.id.count()).gt(3))
          .orderBy((c) => [c.ref((p) => p.authorId).asc()])
          .get();
      expect(rows, [(id: 1, count: 4), (id: 2, count: 4), (id: 3, count: 4)]);
      expect(
        () => counts.query.select((c) => c.ref((p) => p.title)),
        throwsA(isA<OrmException>()),
      );
      final alias = counts.alias();
      final joined = await db
          .table(users)
          .join(alias, on: (u, c) => u.id.equals(c.ref((p) => p.authorId)))
          .orderBy((u) => [u.id.asc()])
          .select(
            (u) => (
              u.email,
              alias.fields.ref((p) => p.id.count()),
            ).map((email, count) => (email: email, count: count)),
          )
          .get();
      expect(joined.first, (email: 'user0', count: 4));
      expect(joined.length, 3);
      final post = postsTable.alias();
      final optional = db
          .table(users)
          .leftJoin(post, on: (u, p) => u.id.equals(p.authorId).and(p.id.eq(1)))
          .select((u) => post.optional(post.fields.title))
          .asCte('optional_posts');
      expect(await optional.query.get(), ['post1', null, null, null]);
      expect(
        () => optional.query.select((c) => c.ref((u) => post.fields.title)),
        throwsA(isA<OrmException>()),
      );
      expect(
        await optional.query
            .select((c) => c.ref((u) => post.nullable(post.fields.title)))
            .get(),
        ['post1', null, null, null],
      );
    },
  );

  test('explicit aliases support multiple joins and self joins', () async {
    final db = database();
    final a = users.alias(), b = users.alias();
    final result = await db
        .table(users)
        .join(a, on: (u, a) => u.id.equals(a.id))
        .join(b, on: (u, b) => b.id.equals(a.fields.id))
        .orderBy((u) => [u.id.asc()])
        .select(
          (u) => (
            u.id,
            a.fields.email,
            b.fields.email,
          ).map((id, a, b) => (id: id, a: a, b: b)),
        )
        .get();
    expect(result.length, 4);
    expect(result.first, (id: 1, a: 'user0', b: 'user0'));
    expect(
      () => db
          .table(users)
          .join(a, on: (u, a) => a.id.equals(b.fields.id))
          .join(b, on: (u, b) => u.id.equals(b.id))
          .compile(),
      throwsA(isA<OrmException>()),
    );
  });

  test(
    'left join distinguishes a missing row from an all-null selection',
    () async {
      final db = database();
      final post = postsTable.alias();
      final rows = await db
          .table(users)
          .leftJoin(post, on: (u, p) => u.id.equals(p.authorId).and(p.id.eq(1)))
          .orderBy((u) => [u.id.asc()])
          .select(
            (u) => post.optional(post.fields.tag.map((tag) => (tag: tag))),
          )
          .get();
      expect(rows, [(tag: null), null, null, null]);
      final missing = await db
          .table(users)
          .leftJoin(post, on: (u, p) => u.id.equals(p.authorId))
          .where((u) => post.isPresent.not())
          .select((u) => u.id)
          .get();
      expect(missing, [4]);
      expect(
        () => db
            .table(users)
            .leftJoin(post, on: (u, p) => u.id.equals(p.authorId))
            .select((u) => post.fields.title)
            .compile(),
        throwsA(isA<OrmException>()),
      );
    },
  );

  test('correlated scalar, IN and EXISTS use nested SQL scopes', () async {
    final db = database();
    final counts = await db
        .table(users)
        .orderBy((u) => [u.id.asc()])
        .select(
          (u) => db
              .table(postsTable)
              .where((p) => p.authorId.equals(u.id))
              .select((p) => p.id.count())
              .scalar(),
        )
        .get();
    expect(counts, [4, 4, 4, 0]);
    final hasPosts = db.table(postsTable).select((p) => p.authorId);
    expect(
      await db.table(users).where((u) => u.id.isInQuery(hasPosts)).count(),
      3,
    );
    expect(
      await db
          .table(users)
          .where(
            (u) => db
                .table(postsTable)
                .where((p) => p.authorId.equals(u.id))
                .existsExpression(),
          )
          .count(),
      3,
    );
    final nullable = await db
        .table(users)
        .where((u) => u.id.eq(4))
        .select(
          (u) => db
              .table(postsTable)
              .where((p) => p.authorId.equals(u.id))
              .select((p) => p.title)
              .take(1)
              .scalar(),
        )
        .single();
    expect(nullable, null);
    expect(
      () => db.table(postsTable).select((p) => p.title).scalar(),
      throwsA(isA<OrmException>()),
    );
  });

  test(
    'grouping is checked and window functions preserve row cardinality',
    () async {
      final db = database();
      final counts = await db
          .table(postsTable)
          .groupBy((p) => [p.authorId])
          .having((p) => p.id.count().gt(3))
          .orderBy((p) => [p.authorId.asc()])
          .select(
            (p) => (
              p.authorId,
              p.id.count(),
            ).map((id, count) => (id: id, count: count)),
          )
          .get();
      expect(counts, [(id: 1, count: 4), (id: 2, count: 4), (id: 3, count: 4)]);
      final windowed = await db
          .table(postsTable)
          .where((p) => p.authorId.eq(1))
          .orderBy((p) => [p.id.asc()])
          .select(
            (p) => (
              rowNumber(partitionBy: [p.authorId], orderBy: [p.id.asc()]),
              p.id.sum().over(
                partitionBy: [p.authorId],
                orderBy: [p.id.asc()],
                frame: .rowsToCurrent,
              ),
            ).map((rank, sum) => (rank: rank, sum: sum)),
          )
          .get();
      expect(windowed, [
        (rank: 1, sum: 1),
        (rank: 2, sum: 3),
        (rank: 3, sum: 6),
        (rank: 4, sum: 10),
      ]);
      expect(
        () => db
            .table(postsTable)
            .select((p) => (p.title, p.id.count()).map((a, b) => (a, b)))
            .compile(),
        throwsA(isA<OrmException>()),
      );
      expect(
        () => db.table(postsTable).where((p) => p.id.count().gt(1)).compile(),
        throwsA(isA<OrmException>()),
      );
    },
  );
}
