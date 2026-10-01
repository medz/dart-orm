import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

const _roles = """
@Model(table: 'people')
final class Person({@Id(generated:true) required final int id, required final String name});
@Model(table: 'articles')
final class Article({
 @Id(generated:true) required final int id, required final String title,
 @Relation(target:Person,name:'author',inverse:'authored') required final int authorId,
 @Relation(target:Person,name:'reviewer',inverse:'reviewed',onDelete:.setNull) required final int? reviewerId,
});
""";

void main() {
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory('.dart_tool/orm-relation-tests')
        .create(recursive: true);
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  test('two explicitly named relationships retain one FK each', () async {
    final file = File('${fixtures.path}/roles.dart');
    await file.writeAsString("import 'package:orm/schema.dart';\n$_roles");
    final generated = await generateSchema(file.path);
    expect(
      generated.snapshot.tables
          .singleWhere((t) => t.name == 'people')
          .foreignKeys,
      isEmpty,
    );
    expect(
      generated.snapshot.tables
          .singleWhere((t) => t.name == 'articles')
          .foreignKeys,
      hasLength(2),
    );
    for (final name in ['author', 'reviewer', 'authored', 'reviewed']) {
      expect(generated.dart, contains('get $name =>'));
    }
  });

  for (final backend in [
    'sqlite',
    if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) 'postgres',
  ]) {
    test(
      '$backend generated multi-role relations query the correct keys on real databases',
      () async {
        await File('${fixtures.path}/runtime.dart')
            .writeAsString("import 'package:orm/schema.dart';\n$_roles");
        await writeGeneratedSchema('${fixtures.path}/runtime.dart');
        final script = File('${fixtures.path}/consumer.dart');
        await script.writeAsString(_consumer);
        final fixture = await BuildFixture.create(
          ormPath: Directory.current.path,
        );
        addTearDown(fixture.dispose);
        await fixture.write('bin/relations.dart', '''
import '${script.absolute.uri}' as consumer;
Future<void> main(List<String> args) => consumer.main(args);
''');
        final result = await Process.run(Platform.resolvedExecutable, [
          'run',
          'orm_build_fixture:relations',
          backend,
        ], workingDirectory: fixture.directory.path);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final lines = (result.stdout as String)
            .split('\n')
            .where((line) => line.startsWith('{'));
        final engines = <String>[];
        for (final line in lines) {
          final data = jsonDecode(line) as Map;
          engines.add(data['engine'] as String);
          expect(data['authored'], ['written']);
          expect(data['reviewed'], ['reviewed']);
          expect(data['author'], 'Alice');
          expect(data['reviewer'], 'Bob');
          expect(data['clearedReviewer'], null);
          expect(data['manyQueries'], 2);
          expect(data['oneQueries'], 1);
        }
        expect(engines, [backend]);
      },
      tags: backend,
    );
  }
}

const _consumer = r'''
import 'dart:convert';
import 'dart:io';
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/postgres.dart';
import 'runtime.orm.dart';

Future<void> main(List<String> args) async {
  final events = <QueryEvent>[];
  if (args.single == 'sqlite') {
    await verify(await sqlite(const SqliteOptions.memory(), onQuery: events.add), events);
    return;
  }
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url == null) return;
  final admin = postgres(PostgresOptions(url: Uri.parse(url), tls: PostgresTls.disable));
  const schema = 'orm_named_relation_tests';
  try {
    await admin.execute(SqlCommand('CREATE SCHEMA "$schema"'));
    try {
      await verify(postgres(PostgresOptions(url: Uri.parse(url), schema: schema, tls: PostgresTls.disable), onQuery: events.add), events);
    } finally {
      await admin.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
    }
  } finally {
    await admin.close();
  }
}

Future<void> verify(Database<Backend> db, List<QueryEvent> events) async {
  try {
    await Migrator(db.sql).apply([Migration.create('0001_relations', appSchema, dialect: db.dialect)]);
    final alice = await db.person.create(name: 'Alice');
    final bob = await db.person.create(name: 'Bob');
    final written = await db.article.create(title: 'written', authorId: alice.id, reviewerId: bob.id);
    await db.article.create(title: 'reviewed', authorId: bob.id, reviewerId: alice.id);
    events.clear();
    final authored = await db.person.byId(alice.id).select((p) => p.authored.select((a) => a.title).many()).single();
    final manyQueries = events.length;
    final reviewed = await db.person.byId(alice.id).select((p) => p.reviewed.select((a) => a.title).many()).single();
    events.clear();
    final author = await db.article.byId(written.id).select((a) => a.author.select((p) => p.name).one()).single();
    final oneQueries = events.length;
    final reviewer = await db.article.byId(written.id).select((a) => a.reviewer.select((p) => p.name).one()).single();
    await db.article.byId(written.id).patch(reviewerId: .set(null));
    final clearedReviewer = await db.article.byId(written.id).select((a) => a.reviewer.select((p) => p.name).one()).single();
    print(jsonEncode({'engine': db.dialect.name, 'authored': authored, 'reviewed': reviewed, 'author': author, 'reviewer': reviewer, 'clearedReviewer': clearedReviewer, 'manyQueries': manyQueries, 'oneQueries': oneQueries}));
  } finally {
    await db.close();
  }
}
''';
