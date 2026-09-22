import 'dart:convert';
import 'dart:io';

import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';

import 'schema.orm.dart';

/// Runs the query cookbook on an empty, disposable database.
Future<Map<String, Object?>> queryCookbook(
  Database<Backend> db, {
  int? minimumScore,
}) async {
  final checks = <String>[];
  void check(bool condition, String name) {
    if (!condition) throw StateError(name);
    checks.add(name);
  }

  await Migrator(
    db.sql,
  ).apply([Migration.create('0001_example', appSchema, dialect: db.dialect)]);
  final (z, a) = await db.transaction((tx) async {
    final z = await tx.user.create(
      email: 'z@example.com',
      nickname: 'Z',
      score: .set(2),
    );
    final a = await tx.user.create(email: 'a@example.com');
    await tx.post.create(
      authorId: z.id,
      title: 'Z1',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await tx.post.create(
      authorId: z.id,
      title: 'Z2',
      createdAt: DateTime.utc(2026, 1, 2),
    );
    await tx.post.create(
      authorId: a.id,
      title: 'A1',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    return (z, a);
  });

  var query = db.user.where((u) => u.email.like('%@example.com'));
  if (minimumScore != null) {
    query = query.where((u) => u.score.gte(.value(minimumScore)));
  }
  final emails = await query
      .orderBy((u) => [u.id.asc()])
      .take(20)
      .select((u) => u.email)
      .get();
  final expectedEmails = [
    for (final user in [z, a])
      if (minimumScore == null || user.score >= minimumScore) user.email,
  ];
  check(
    jsonEncode(emails) == jsonEncode(expectedEmails),
    'Dynamic typed filter and scalar selection',
  );

  final author = userTable.alias();
  final joined = await db.post
      .join(author, on: (p, a) => p.authorId.eq(a.id))
      .orderBy((p) => [author.fields.email.asc(), p.id.asc()])
      .select((p) => (p.title, author.fields.email).row)
      .get();
  final expectedJoined = [('A1', a.email), ('Z1', z.email), ('Z2', z.email)];
  check(
    joined.length == expectedJoined.length &&
        joined.indexed.every((e) => e.$2 == expectedJoined[e.$1]),
    'Joined field orders root rows',
  );
  final relationOrder = await db.user
      .orderBy((u) => [u.posts.count().desc(), u.id.asc()])
      .select((u) => u.email)
      .get();
  check(
    jsonEncode(relationOrder) == jsonEncode([z.email, a.email]),
    'Correlated relation count orders root rows',
  );

  final totals = db.post
      .groupBy((p) => [p.authorId])
      .having((p) => p.id.count().gt(.value(1)))
      .select((p) => (p.authorId, p.id.count()).row)
      .asCte('author_totals');
  final active = await totals.query
      .orderBy((c) => [c.ref((p) => p.authorId).asc()])
      .get();
  check(
    active.length == 1 && active.single == (z.id, 2),
    'Grouping, HAVING and CTE exported columns',
  );
  final ranks = await db.post
      .orderBy((p) => [p.id.asc()])
      .select(
        (p) => (
          p.id,
          rowNumber(
            partitionBy: [p.authorId],
            orderBy: [p.createdAt.desc(), p.id.desc()],
          ),
        ).row,
      )
      .get();
  check(
    jsonEncode(ranks.map((r) => r.$2).toList()) == '[2,1,1]',
    'Window ordering is independent of result ordering',
  );
  final selectedAuthors = db.post.select((p) => p.authorId);
  check(
    await db.user.where((u) => u.id.isInQuery(selectedAuthors)).count() == 2,
    'Typed IN subquery',
  );
  final counts = await db.user
      .orderBy((u) => [u.id.asc()])
      .select(
        (u) => db.post
            .where((p) => p.authorId.eq(u.id))
            .select((p) => p.id.count())
            .scalar(),
      )
      .get();
  check(jsonEncode(counts) == '[2,1]', 'Correlated scalar aggregate');

  final first = await db.user
      .orderBy((u) => [u.nickname.asc(nulls: .last), u.id.asc()])
      .take(1)
      .get();
  final last = first.single;
  final token = db.user.cursorToken(
    (u) => [
      u.nickname.cursor(last.nickname, nulls: .last),
      u.id.cursor(last.id),
    ],
  );
  final next = await db.user
      .seekToken(
        token,
        orderBy: (u) => [u.nickname.asc(nulls: .last), u.id.asc()],
      )
      .take(1)
      .get();
  check(
    first.single.id == z.id && next.single.id == a.id,
    'Versioned cursor preserves NULL order and unique tie breaker',
  );
  check(
    (await verifySchema(db.sql, SchemaSnapshot(appSchema))).matches,
    'Generated schema matches the live database',
  );
  final empty = await db.user.create(
    email: 'empty@example.com',
    nickname: '100%_ready',
    score: .set(10),
  );
  const keyword = '%_';
  final filtered = db.user.where(
    (u) => allOf([
      if (minimumScore != null) u.score.gte(.value(minimumScore)),
      anyOf([u.nickname.contains(keyword), u.email.startsWith('a@')]),
      u.posts.none(),
    ]),
  );
  final filteredRows = await filtered.get();
  final expectEmpty = minimumScore == null || empty.score >= minimumScore;
  check(
    filteredRows.length == (expectEmpty ? 1 : 0) &&
        filteredRows.every((user) => user.id == empty.id),
    'Dynamic groups combine nullable literal text and relation filters',
  );
  check(
    jsonEncode(
          await db.user
              .where((u) => u.score.gt(u.id))
              .orderBy((u) => [u.id.asc()])
              .select((u) => u.id)
              .get(),
        ) ==
        jsonEncode([z.id, empty.id]),
    'One comparison API accepts another field',
  );
  check(
    await db.user.where((_) => allOf([])).count() == 3 &&
        !await db.user.where((_) => anyOf([])).exists(),
    'Empty AND is true and empty OR is false',
  );

  final samePost = db.user.where(
    (u) => u.posts
        .where(
          (p) => allOf([p.title.eq(.value('Z1')), p.title.eq(.value('Z2'))]),
        )
        .any(),
  );
  final independentPosts = db.user.where(
    (u) => allOf([
      u.posts.where((p) => p.title.eq(.value('Z1'))).any(),
      u.posts.where((p) => p.title.eq(.value('Z2'))).any(),
    ]),
  );
  check(
    !await samePost.exists() && (await independentPosts.single()).id == z.id,
    'A single child satisfying both predicates differs from independent matches',
  );

  final matchingParents = await db.user
      .where((u) => u.posts.where((p) => p.title.eq(.value('Z1'))).any())
      .select((u) => (u.id, u.posts.many()).map((id, posts) => (id, posts)))
      .get();
  final filteredChildren = await db.user
      .orderBy((u) => [u.id.asc()])
      .select((u) => u.posts.where((p) => p.title.eq(.value('Z1'))).many())
      .get();
  check(
    matchingParents.single.$1 == z.id &&
        matchingParents.single.$2.length == 2 &&
        jsonEncode(filteredChildren.map((rows) => rows.length).toList()) ==
            '[1,0,0]',
    'Parent filters and loaded-child filters have independent scopes',
  );

  check(
    await db.user
                .where((u) => u.posts.every((p) => p.title.startsWith('Z')))
                .count() ==
            2 &&
        (await db.user
                    .where(
                      (u) => allOf([
                        u.posts.any(),
                        u.posts.every((p) => p.title.startsWith('Z')),
                      ]),
                    )
                    .single())
                .id ==
            z.id,
    'Every accepts empty relationships unless existence is required',
  );

  // This predicate is unchanged by writing the title. Each operation still
  // evaluates WHERE anew; a query description is not a frozen list of keys.
  await db.transaction((tx) async {
    final matched = tx.post.where(
      (p) => p.author
          .where(
            (u) => allOf([u.email.eq(.value(z.email)), u.score.gt(.value(0))]),
          )
          .any(),
    );
    final before = await matched.get();
    final updated = await matched
        .update((p) => [p.title.set('Archived')])
        .execute();
    final after = await matched.get();
    final deleted = await matched.delete().execute();
    check(
      before.length == 2 &&
          updated == 2 &&
          after.length == 2 &&
          after.every((p) => p.title == 'Archived') &&
          deleted == 2 &&
          await tx.post.count() == 1,
      'The same relationship WHERE filters SELECT, UPDATE and DELETE',
    );
  });
  return {'backend': db.dialect.name, 'checks': checks, 'status': 'passed'};
}

Future<void> main() async {
  final url = Platform.environment['ORM_EXAMPLE_POSTGRES'];
  final schema = 'orm_example_${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final Database<Backend> db = url == null
      ? await sqlite(const SqliteOptions.memory())
      : postgres(
          PostgresOptions(url: Uri.parse(url), tls: .disable, schema: schema),
        );
  var created = false;
  try {
    if (url != null) {
      await db.execute(SqlCommand('CREATE SCHEMA "$schema"'));
      created = true;
    }
    print(jsonEncode(await queryCookbook(db, minimumScore: 1)));
  } finally {
    try {
      if (created) {
        await db.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
      }
    } finally {
      await db.close();
    }
  }
}
