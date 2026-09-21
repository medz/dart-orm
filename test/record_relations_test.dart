import 'dart:convert';
import 'dart:io';

import 'package:orm/generate.dart';
import 'package:test/test.dart';

const _roles = '''
final Model person = model('people', (id: identity(), name: text()),
 relations: (p) => (
   authored: referencedBy(() => article, on: (authorId: p.id)),
   reviewed: referencedBy(() => article, on: (reviewerId: p.id)),
 ));
final Model article = model('articles', (
 id: identity(), title: text(), authorId: integer(), reviewerId: integer().nullable(),
), relations: (a) => (
 author: references(a.authorId, () => person),
 reviewer: references(a.reviewerId, () => person, onDelete: .setNull),
));
''';

void main() {
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory('.dart_tool/orm-relation-tests')
        .create(recursive: true);
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  Future<GeneratedSchema> generate(String name, String source) async {
    final file = File('${fixtures.path}/$name.dart');
    await file.writeAsString("import 'package:orm/schema.dart';\n$source");
    return generateSchema(file.path);
  }

  test(
    'named forward and reverse members belong to their declaring model',
    () async {
      final result = await generate('roles', _roles);
      final person = result.snapshot.tables.first;
      expect(person.foreignKeys, isEmpty);
      expect(result.snapshot.tables.last.foreignKeys, hasLength(2));
      for (final name in ['authored', 'reviewed', 'author', 'reviewer']) {
        expect(result.dart, contains('get $name =>'));
      }
      final changed = await generate(
        'renamed_roles',
        _roles
            .replaceFirst('authored:', 'written:')
            .replaceFirst('author:', 'writer:'),
      );
      expect(changed.snapshotDart, result.snapshotDart);
      expect(changed.dart, contains('get written =>'));
      expect(changed.dart, contains('get writer =>'));
      expect(changed.dart, isNot(contains('get authored =>')));
    },
  );

  test('a forward reference does not inject an inverse member', () async {
    final result = await generate('no_implicit_inverse', '''
final Model person = model('people', (id: identity(),));
final Model article = model('articles', (id: identity(), authorId: integer()),
 relations: (a) => (author: references(a.authorId, () => person),));
''');
    expect(
      result.dart,
      isNot(contains('Relation<Article, ArticleFields> get')),
    );
  });

  test(
    'named composite mappings normalize order and inverses reuse the mapping',
    () async {
      const source = '''
final Model team = model('teams', (tenant: integer(name: 'tenant_key'), code: text(name: 'team_code')),
 primaryKey: (t) => (t.tenant, t.code),
 relations: (t) => (members: referencedBy(() => member, on: (teamCode: t.code, tenantId: t.tenant)),));
final Model member = model('members', (id: identity(), tenantId: integer(), teamCode: text()),
 relations: (m) => (team: references((code: m.teamCode, tenant: m.tenantId), () => team),));
''';
      final result = await generate('composite', source);
      final fk = result.snapshot.tables.last.foreignKeys.single;
      expect(fk.columns, ['tenant_id', 'team_code']);
      expect(fk.targetColumns, ['tenant_key', 'team_code']);
      expect(result.snapshot.tables.first.foreignKeys, isEmpty);
      expect(result.dart, contains('get members =>'));
      final reordered = await generate(
        'reordered',
        source
            .replaceFirst(
              '(code: m.teamCode, tenant: m.tenantId)',
              '(tenant: m.tenantId, code: m.teamCode)',
            )
            .replaceFirst(
              '(teamCode: t.code, tenantId: t.tenant)',
              '(tenantId: t.tenant, teamCode: t.code)',
            ),
      );
      expect(reordered.snapshotDart, result.snapshotDart);
    },
  );

  test('reverse navigation preserves read-only reference ownership', () async {
    final result = await generate('read_only', '''
final Model team = model('teams', (id: identity(), code: text()),
 relations: (t) => (members: referencedBy(() => member, on: null),));
final Model member = model('members', (id: identity(), code: text()),
 relations: (m) => (team: references((code: m.code), () => team, constraint: false),));
''');
    expect(result.snapshot.tables.expand((t) => t.foreignKeys), isEmpty);
    expect('Read-only navigation'.allMatches(result.dart), hasLength(2));
  });

  test('an empty relations Record is valid', () async {
    final result = await generate(
      'empty',
      "final Model item = model('items', (id: identity(),), relations: (i) => ());",
    );
    expect(result.snapshot.tables, hasLength(1));
  });

  test('ambiguity reports concrete mappings for each candidate', () async {
    await expectLater(
      generate('ambiguous', _roles.replaceFirst(', on: (authorId: p.id)', '')),
      throwsA(
        isA<GenerationException>()
            .having((e) => e.code, 'code', 'SCHEMA.REFERENCE')
            .having(
              (e) => e.message,
              'choices',
              allOf(
                contains('article.author: on: (authorId: p.id)'),
                contains('article.reviewer: on: (reviewerId: p.id)'),
              ),
            ),
      ),
    );
  });

  final invalid = <String, (String, String)>{
    'wrong_inverse_mapping': (
      _roles.replaceFirst('(authorId: p.id)', '(title: p.name)'),
      'REFERENCE',
    ),
    'unknown_remote_field': (
      _roles.replaceFirst('(authorId: p.id)', '(authroId: p.id)'),
      'REFERENCE',
    ),
    'empty_inverse_mapping': (
      _roles.replaceFirst('(authorId: p.id)', '()'),
      'REFERENCE',
    ),
    'positional_inverse_mapping': (
      _roles.replaceFirst('(authorId: p.id)', '(p.id,)'),
      'REFERENCE',
    ),
    'inverse_without_forward': (
      "final Model item = model('items', (id: identity(), parentId: integer()), relations: (i) => (children: referencedBy(() => item),));",
      'REFERENCE',
    ),
    'inverse_chain': (
      "final Model item = model('items', (id: identity(),), relations: (i) => (children: referencedBy(() => item), parents: referencedBy(() => item)));",
      'REFERENCE',
    ),
    'invalid_relation_value': (
      "final Model item = model('items', (id: identity(),), relations: (i) => (children: 1,));",
      'RELATION',
    ),
    'positional_relation': (
      "final Model item = model('items', (id: identity(), parentId: integer()), relations: (i) => (references(i.parentId, () => item),));",
      'RELATION',
    ),
    'relation_factory': (
      "ReferenceDefinition make() => throw StateError('must not execute'); final Model item = model('items', (id: identity(),), relations: (i) => (children: make(),));",
      'RELATION',
    ),
    'named_nonunique_target': (
      "final Model item = model('items', (id: identity(), code: text()), relations: (i) => (parent: references((code: i.code), () => item),));",
      'REFERENCE',
    ),
    'named_wrong_type': (
      "final Model item = model('items', (id: identity(), code: text()), relations: (i) => (parent: references((id: i.code), () => item),));",
      'REFERENCE',
    ),
    'mixed_mapping': (
      "final Model item = model('items', (id: identity(),), relations: (i) => (parent: references((i.id, id: i.id), () => item),));",
      'REFERENCE',
    ),
    'duplicate_local_mapping': (
      "final Model item = model('items', (a: integer(), b: integer()), primaryKey: (i) => (i.a, i.b), relations: (i) => (parent: references((a: i.a, b: i.a), () => item),));",
      'REFERENCE',
    ),
    'inverse_name_collision': (
      "final Model item = model('items', (id: identity(), parentId: integer()), relations: (i) => (parent: references(i.parentId, () => item), id: referencedBy(() => item)));",
      'NAME',
    ),
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} at its declaration', () async {
      await expectLater(
        generate(entry.key, entry.value.$1),
        throwsA(
          isA<GenerationException>()
              .having((e) => e.code, 'code', 'SCHEMA.${entry.value.$2}')
              .having(
                (e) => e.source?.path,
                'source',
                endsWith('${entry.key}.dart'),
              )
              .having((e) => e.line, 'line', greaterThan(0)),
        ),
      );
    });
  }

  test('native Dart still checks local relation field access', () async {
    await expectLater(
      generate(
        'unknown_local',
        _roles.replaceFirst('references(a.authorId', 'references(a.authroId'),
      ),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.message,
          'message',
          contains("getter 'authroId' isn't defined"),
        ),
      ),
    );
  });

  test(
    'generated multi-role relations query the correct keys on real databases',
    () async {
      await generate('runtime', _roles);
      await writeGeneratedSchema('${fixtures.path}/runtime.dart');
      final script = File('${fixtures.path}/consumer.dart');
      await script.writeAsString(_consumer);
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        script.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
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
      expect(engines, contains('sqlite'));
      if (Platform.environment.containsKey('ORM_TEST_POSTGRES')) {
        expect(engines, contains('postgres'));
      }
    },
  );
}

const _consumer = r'''
import 'dart:convert';
import 'dart:io';
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/postgres.dart';
import 'runtime.orm.dart';

Future<void> main() async {
  final events = <QueryEvent>[];
  await verify(await sqlite(const SqliteOptions.memory(), onQuery: events.add), events);
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
