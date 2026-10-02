@Tags(['sqlite'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  test(
    'annotated example matches freshly generated client and snapshot',
    () async {
      final generated = await generateSchema(
        'example/annotated/models.dart',
        dialect: .sqlite,
      );
      expect(
        generated.dart,
        await File('example/annotated/models.orm.dart').readAsString(),
      );
      expect(
        generated.snapshotDart,
        await File('example/annotated/models.snapshot.dart').readAsString(),
      );
    },
  );

  test('generated NULL database defaults beat constructor values', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    try {
      await fixture.file('lib/schema.dart').delete();
      await fixture.write('lib/models.dart', '''
import 'package:orm/schema.dart';
@Model() final class User({
  @Id(generated: true) required final int id,
  @DatabaseDefault(null) final int? score = 7,
  @DatabaseDefault.sql('NULL') final String? note = 'constructor',
});
''');
      await fixture.write('orm.config.dart', '''
import 'package:orm/config.dart';
void main() => defineConfig(database: .sqlite, models: 'lib/models.dart',
  output: 'lib/models.orm.dart', migrations: 'migrations');
''');
      await fixture.write('bin/null_defaults.dart', _nullDefaultConsumer);
      await fixture.run(['run', 'orm', 'generate']);
      expect(
        await fixture.file('lib/models.orm.dart').readAsString(),
        isNot(contains('clientDefault:')),
      );
      final result = await fixture.run([
        'run',
        'orm_build_fixture:null_defaults',
      ]);
      expect(result.output, contains('explicit-null-default-ok'));
    } finally {
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('fresh annotated client compiles and executes original DTOs on SQLite', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    try {
      await fixture.file('lib/schema.dart').delete();
      final originalSource = await File('example/annotated/models.dart')
          .readAsString();
      final factoryProbe = fixture.file('factory-executed.txt');
      final instrumentedSource = originalSource
          .replaceFirst(
            'required final String title,',
            'required final String title, final bool published = false,',
          )
          .replaceFirst(
            "String nextMarker() => 'marker-\${++markerCalls}';",
            'String nextMarker() { '
                'File(${jsonEncode(factoryProbe.path)}).writeAsStringSync("called"); '
                "return 'marker-\${++markerCalls}'; }",
          );
      final source = "import 'dart:io';\n$instrumentedSource";
      await fixture.write('lib/models.dart', source);
      await fixture.write('orm.config.dart', '''
import 'package:orm/config.dart';

void main() {
  defineConfig(
    database: .sqlite,
    models: 'lib/models.dart',
    output: 'lib/models.orm.dart',
    migrations: 'migrations',
  );
}
''');
      await fixture.write('bin/annotated.dart', _consumer);
      final client = fixture.file('lib/models.orm.dart');
      final snapshot = fixture.file('lib/models.snapshot.dart');
      expect(await client.exists(), false);
      expect(await snapshot.exists(), false);

      await fixture.run(['run', 'orm', 'generate']);
      final generated = await client.readAsString();
      final frozen = await snapshot.readAsString();
      expect(
        await factoryProbe.exists(),
        false,
        reason:
            'The real CLI must not invoke default factories during generation.',
      );
      expect(await fixture.file('lib/models.dart').readAsString(), source);
      expect(generated, isNot(contains('final class User(')));
      expect(generated, isNot(contains('final class Post(')));
      expect(generated, contains('Table<models.User, UserFields>'));
      expect(generated, contains('Table<models.Post, PostFields>'));
      expect(
        generated,
        contains('import "package:orm_build_fixture/models.dart" as models;'),
      );
      expect(
        generated,
        contains(
          'export "package:orm_build_fixture/models.dart" show User, Post;',
        ),
      );
      expect(generated, isNot(contains('localLabel')));
      expect(frozen, isNot(contains('models.dart')));
      expect(frozen, isNot(contains('clientDefault:')));
      expect(frozen, isNot(contains('nextMarker')));
      expect(frozen, isNot(contains('nextInstant')));

      await fixture.run(['run', 'orm', 'generate']);
      expect(await client.readAsString(), generated);
      expect(await snapshot.readAsString(), frozen);
      final direct = await generateSchema(
        fixture.file('lib/models.dart').path,
        outputPath: client.path,
        dialect: .sqlite,
      );
      expect(direct.dart, generated);
      expect(direct.snapshotDart, frozen);
      expect(
        await factoryProbe.exists(),
        false,
        reason: 'Repeated CLI and direct parsing must leave application factories untouched.',
      );
      final user = direct.snapshot.tables.singleWhere(
        (table) => table.name == 'User',
      );
      expect(user.primaryKey, ['id']);
      expect(user.uniqueKeys, [
        ['email'],
      ]);
      expect(user.columns.map((column) => column.name), [
        'id',
        'email',
        'display_name',
        'nickname',
        'active',
        'marker',
        'score',
      ]);
      expect(
        user.columns
            .singleWhere((column) => column.name == 'nickname')
            .defaultSql,
        isNull,
      );
      final post = direct.snapshot.tables.singleWhere(
        (table) => table.name == 'posts',
      );
      expect(post.indexes.single.name, 'posts_author_created');
      expect(post.indexes.single.columns, ['author_id', 'created_at']);
      expect(post.foreignKeys.single.target, 'User');
      expect(post.foreignKeys.single.onDelete, 'CASCADE');
      expect(
        post.columns
            .singleWhere((column) => column.name == 'published')
            .defaultSql,
        isNull,
        reason: 'A constructor false default is client-only, not SQL DEFAULT.',
      );

      await fixture.run(['analyze']);
      final result = await fixture.run(['run', 'orm_build_fixture:annotated']);
      expect(result.output, contains('annotated-sqlite-ok'));
      expect(
        await factoryProbe.exists(),
        true,
        reason: 'The same factory must run for actual omitted insert values.',
      );
      // A generated client reached through a file URI must retain the same
      // canonical DTO identity as the package's public model import.
      await fixture.write(
        'bin/annotated.dart',
        _consumer.replaceFirst(
          "import 'package:orm_build_fixture/models.orm.dart';",
          "import '../lib/models.orm.dart';",
        ),
      );
      final relativeClient = await fixture.run([
        'run',
        'orm_build_fixture:annotated',
      ]);
      expect(relativeClient.output, contains('annotated-sqlite-ok'));
    } finally {
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

const _nullDefaultConsumer = r'''import 'package:orm/orm.dart';
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';
import 'package:orm_build_fixture/models.orm.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
Future<void> main() async {
  final db = Database.fromSql(await sqlite(const SqliteOptions.memory()));
  try {
    final migration = Migration.create('0001_initial', appSchema, dialect: .sqlite);
    await Migrator(db.sql).apply([migration]);
    check((await verifySchema(db.sql, migration.snapshot!)).matches, 'apply->verify drift');
    final omitted = await db.user.create();
    check(omitted.score == null && omitted.note == null, 'Omission used constructor defaults');
    final explicit = await db.user.create(score: null, note: null);
    check(explicit.score == null && explicit.note == null, 'Explicit null was replaced');
    final supplied = await db.user.create(score: 9, note: 'supplied');
    check(supplied.score == 9 && supplied.note == 'supplied', 'Explicit values were lost');
    await db.user.byId(omitted.id).update(userPatch.values(note: .set('updated')));
    final patched = await db.user.byId(omitted.id).single();
    check(patched.score == null && patched.note == 'updated', 'Omitted patch used fallback');
    final read = await db.user.byId(explicit.id).single();
    check(read.score == null && read.note == null, 'Read used constructor defaults');
    check((await verifySchema(db.sql, migration.snapshot!)).matches, 'DML changed schema verification');
    print('explicit-null-default-ok');
  } finally { await db.close(); }
}
''';

const _consumer = r'''import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/values.dart';
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'package:orm_build_fixture/models.dart' as original;
import 'package:orm_build_fixture/models.orm.dart';
import 'package:orm_build_fixture/models.snapshot.dart' as physical;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  check(original.markerCalls == 0, 'Importing a DTO executed its client factory.');
  check(original.instantCalls == 0, 'Importing a DTO executed its clock factory.');
  final events = <QueryEvent>[];
  final db = Database.fromSql(await sqlite(const SqliteOptions.memory(), onQuery: events.add));
  try {
    await Migrator(db.sql).apply([
      Migration.create('0001_initial', appSchema, dialect: db.dialect),
    ]);
    check(original.markerCalls == 0, 'Migration executed a client factory.');
    check((await verifySchema(db.sql, physical.schema)).matches,
        'Generated schema does not match the SQLite catalog.');

    events.clear();
    final User first = await db.user.create(email: 'first@example.com');
    final original.User originalFirst = first;
    check(originalFirst.greeting() == 'Hello, Anonymous',
        'Read rows must retain the original DTO and business methods.');
    check(first.id > 0 && first.nickname == 'guest' && first.score == 7,
        'Omitted generated and constructor defaults were not applied.');
    check(first.active, 'An explicit database default must beat a constructor fallback.');
    check(first.marker == 'marker-1' && original.markerCalls == 1,
        'An explicit client factory must beat a constructor fallback.');
    check(first.localLabel == 'local-only', 'Ignored constructor value was lost.');
    final insertSql = events.firstWhere((e) => e.sql.startsWith('INSERT')).sql;
    final insertedColumns = insertSql.substring(0, insertSql.indexOf(' VALUES'));
    check(!insertedColumns.contains('"active"'),
        'An omitted database default must stay absent from the INSERT.');
    check(insertedColumns.contains('"nickname"'),
        'Constructor defaults must be explicitly bound as client values.');

    final User second = await db.user.create(
      id: 40,
      email: 'second@example.com',
      name: 'Explicit',
      nickname: null,
      active: false,
      marker: 'manual',
      score: 0,
    );
    check(second.id == 40 && second.greeting() == 'Hello, Explicit',
        'Explicit generated keys and constructor values were lost.');
    check(second.nickname == null && !second.active && second.score == 0,
        'Explicit null, false and zero must not be treated as omission.');
    check(second.marker == 'manual' && original.markerCalls == 1,
        'Explicit values must bypass client factories.');

    await db.user.byId(first.id).update(userPatch.values(
      name: .set('Changed'),
      nickname: .keep(),
    ));
    final original.User patched = await db.user.byId(first.id).single();
    check(patched.greeting() == 'Hello, Changed' && patched.nickname == 'guest',
        'Patch keep must preserve the stored value.');
    check(patched.active && patched.score == 7 && patched.marker == 'marker-1',
        'A partial patch must not reset omitted defaults.');
    check(original.markerCalls == 1, 'Patch must not run insert factories.');
    await db.user.byId(first.id).update(userPatch.values(nickname: .set(null)));
    check((await db.user.byId(first.id).single()).nickname == null,
        'Patch must distinguish explicit null from keep.');
    try {
      await db.user.byId(first.id).update(userPatch.values());
      throw StateError('An empty patch must retain its explicit error.');
    } on OrmException catch (error) {
      check(error.code == 'MUTATION.EMPTY', 'Unexpected empty patch error.');
    }

    final User again = await db.user.create(email: 'third@example.com');
    check(again.marker == 'marker-2' && original.markerCalls == 2,
        'Each omitted insert must evaluate its factory exactly once.');
    await db.user.byId(again.id).delete();

    final before = DateTime.now().toUtc();
    final Post post = await db.post.create(
      authorId: first.id,
      title: 'Generated from DTOs',
    );
    check(!post.published, 'Omitting a constructor bool default must bind false.');
    final original.Post originalPost = post;
    check(originalPost.summary() == 'Generated from DTOs (draft)',
        'Database defaults must populate the original Post DTO.');
    check(!post.createdAt.isBefore(before) && original.instantCalls == 1,
        'Client timestamp default did not run once.');
    final explicitTime = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final Post secondPost = await db.post.create(
      authorId: first.id,
      title: 'Explicit timestamp',
      published: true,
      createdAt: explicitTime,
      status: 'published',
    );
    check(original.instantCalls == 1, 'Explicit timestamp ran its factory.');
    await db.post.byId(secondPost.id).update(postPatch.values(title: .set('Explicit timestamp')));
    check((await db.post.byId(secondPost.id).single()).published,
        'A patch/read must retain true rather than reapplying constructor false.');

    events.clear();
    final User author = await db.post
        .byId(post.id)
        .select((p) => p.author.required())
        .single();
    check(author.greeting() == 'Hello, Changed', 'Forward relation lost the DTO type.');
    check(events.length == 1, 'To-one navigation must use one query.');
    events.clear();
    final List<Post> posts = await db.user
        .byId(first.id)
        .select((u) => u.posts.orderBy((p) => [p.id.asc()]).many())
        .single();
    check(posts.length == 2 && posts.last.createdAt == explicitTime,
        'Inverse relation did not load typed complete rows.');
    check(posts.last.summary() == 'Explicit timestamp (published)',
        'Explicit database default override was lost.');
    check(events.length == 2, 'To-many navigation must use two batched queries.');

    try {
      await db.user.create(email: 'first@example.com', marker: 'duplicate');
      throw StateError('The database must enforce @Unique.');
    } on SqliteFailure catch (error) {
      check(error.code == 19, 'Unexpected unique constraint failure.');
    }
    try {
      await db.post.create(authorId: -1, title: 'Orphan');
      throw StateError('The database must enforce explicit foreign keys.');
    } on SqliteFailure catch (error) {
      check(error.code == 19, 'Unexpected foreign-key constraint failure.');
    }
    await db.user.byId(first.id).delete();
    check(await db.post.count() == 0, 'ON DELETE CASCADE did not remove posts.');
    check(await db.user.count() == 1, 'Cascade removed an unrelated user.');
    check((await db.user.byId(second.id).single()).marker == 'manual',
        'Unrelated row changed during cascade.');
    print('annotated-sqlite-ok');
  } finally {
    await db.close();
  }
}
''';
