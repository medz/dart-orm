@Tags(['database'])
library;

import 'dart:io';

import 'package:orm/driver.dart';
import 'package:orm/migrate.dart';
import 'package:orm/orm.dart';
import 'package:orm/postgres.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/values.dart';
import 'package:test/test.dart' hide allOf;

import '../example/schema.orm.dart';

void main() {
  for (final dialect in [SqlDialect.sqlite, SqlDialect.postgres]) {
    group(
      dialect.name,
      () => _tests(dialect),
      tags: [dialect.name],
      skip:
          dialect == SqlDialect.postgres &&
              Platform.environment['ORM_TEST_POSTGRES'] == null
          ? 'Set ORM_TEST_POSTGRES to run real PostgreSQL.'
          : false,
    );
  }
}

void _tests(SqlDialect dialect) {
  late Database<Backend> db;
  final events = <QueryEvent>[];
  const email = "ada'@example.com";

  setUp(() async {
    if (dialect == SqlDialect.sqlite) {
      db = Database.fromSql(
        await sqlite(const SqliteOptions.memory(), onQuery: events.add),
      );
    } else {
      final url = Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!);
      final namespace =
          'orm_returning_${pid}_${DateTime.now().microsecondsSinceEpoch}';
      final admin = Database.fromSql(
        postgres(PostgresOptions(url: url, tls: .disable)),
      );
      addTearDown(admin.close);
      await admin.execute(SqlCommand('CREATE SCHEMA "$namespace"'));
      addTearDown(
        () => admin.execute(SqlCommand('DROP SCHEMA "$namespace" CASCADE')),
      );
      db = Database.fromSql(
        postgres(
          PostgresOptions(url: url, tls: .disable, schema: namespace),
          onQuery: events.add,
        ),
      );
    }
    addTearDown(db.close);
    await Migrator(
      db.sql,
    ).apply([Migration.create('0001_returning', appSchema, dialect: dialect)]);
    await db.user.insertMany([
      userInsert(id: 1, email: email),
      userInsert(id: 2, email: 'bob@example.com'),
      userInsert(id: 3, email: 'no-posts@example.com'),
    ]);
    await db.post.insertMany([
      postInsert(
        id: 10,
        authorId: 1,
        title: 'Published',
        createdAt: DateTime.utc(2026),
      ),
      postInsert(
        id: 11,
        authorId: 1,
        title: 'Draft',
        createdAt: DateTime.utc(2026),
      ),
      postInsert(
        id: 12,
        authorId: 2,
        title: 'Draft',
        createdAt: DateTime.utc(2026),
      ),
    ]);
    events.clear();
  });

  test('generated update returns typed relation counts and existence in one statement', () async {
    final List<({int id, String? nickname, int posts, bool published})> rows =
        await db.user.plan
            .update(userPatch(nickname: 'Reviewed'))
            .returning()
            .select(
              (u) =>
                  (
                    u.id,
                    u.nickname,
                    u.posts.where((p) => p.id.gt(u.id)).count(),
                    u.posts.where((p) => p.title.eq(.value('Published'))).any(),
                  ).map(
                    (id, nickname, posts, published) => (
                      id: id,
                      nickname: nickname,
                      posts: posts,
                      published: published,
                    ),
                  ),
            )
            .get();
    expect(
      {for (final row in rows) row.id: row},
      {
        1: (id: 1, nickname: 'Reviewed', posts: 2, published: true),
        2: (id: 2, nickname: 'Reviewed', posts: 1, published: false),
        3: (id: 3, nickname: 'Reviewed', posts: 0, published: false),
      },
    );
    expect(events, hasLength(1));
    expect(events.single.parameterCount, 2);
  });

  test(
    'correlated scalar subquery retains joined and nested field scopes',
    () async {
      final author = userTable.alias();
      final List<(int, String?)> rows = await db.user.plan
          .update(userPatch(nickname: null))
          .returning()
          .select(
            (u) => (
              u.id,
              db.post
                  .join(author, on: (p, a) => p.authorId.eq(a.id))
                  .where(
                    (p) => allOf([
                      p.authorId.eq(u.id),
                      p.author.where((a) => a.email.eq(u.email)).any(),
                      p.title.eq(.value('Published')),
                    ]),
                  )
                  .take(1)
                  .select((_) => author.fields.email)
                  .scalar(),
            ).row,
          )
          .get();
      expect(
        {for (final row in rows) row.$1: row.$2},
        {1: email, 2: null, 3: null},
      );
      expect(events, hasLength(1));
    },
  );

  test(
    'insert, batch and delete RETURNING retain independent joined subqueries',
    () async {
      final author = userTable.alias();
      final publishedAuthor = db.post
          .join(author, on: (p, a) => p.authorId.eq(a.id))
          .where((_) => author.fields.email.eq(.value(email)))
          .take(1)
          .select((_) => author.fields.email)
          .scalar();
      Selection<(int, String?)> selection(UserFields u) =>
          (u.id, publishedAuthor).row;

      expect(
        await db.user.plan
            .insert(userInsert(id: 20, email: 'inserted@example.com'))
            .returning()
            .select(selection)
            .single(),
        (20, email),
      );
      final batch = await db.user.plan
          .insertMany([
            userInsert(id: 21, email: 'batch1@example.com'),
            userInsert(id: 22, email: 'batch2@example.com'),
          ])
          .prepare()
          .returning(selection)
          .get();
      expect(batch.toSet(), {(21, email), (22, email)});
      expect(
        await db.user
            .byId(20)
            .plan
            .delete()
            .returning()
            .select(selection)
            .single(),
        (20, email),
      );
      expect(
        events,
        hasLength(5),
      ); // Insert, BEGIN, batch insert, COMMIT, delete.
      expect(events.every((event) => !event.sql.contains(email)), isTrue);
    },
  );

  test('RETURNING target names cannot be shadowed by generated subquery aliases', () async {
    // SQLite identifiers are case insensitive. T1 would shadow the first nested
    // t1 alias, and T2 would shadow its join alias if either is reused.
    for (final name in ['T1', 'T2', 'odd"name']) {
      final target = Table<int, _TargetFields>(
        TableSchema(name, columns: [_targetId], primaryKey: ['id']),
        _TargetFields.new,
        (t) => t.id,
      );
      final quoted = '"${name.replaceAll('"', '""')}"';
      await db.execute(
        SqlCommand('CREATE TABLE $quoted (id INTEGER PRIMARY KEY)'),
      );
      await db.table(target).insert((t) => [t.id.set(1)]).execute();
      final author = userTable.alias();
      final rows = await db
          .table(target)
          .update((t) => [t.id.setExpression(t.id)])
          .returning(
            (t) => (
              t.id,
              db.post
                  .join(author, on: (p, a) => p.authorId.eq(a.id))
                  .where((p) => p.authorId.eq(t.id))
                  .take(1)
                  .select((_) => author.fields.email)
                  .scalar(),
            ).row,
          )
          .single();
      expect(rows, (1, email), reason: name);
    }
  });
}

final _targetId = Column('id', Codecs.integer);

final class _TargetFields(super.table) extends Fields {
  late final id = column(_targetId);
}
