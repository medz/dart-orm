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
