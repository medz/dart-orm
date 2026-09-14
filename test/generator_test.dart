import 'dart:io';

import 'package:orm/generate.dart';
import 'package:test/test.dart';

void main() {
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory('.dart_tool/orm-generator-tests')
        .create(recursive: true);
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  Future<GeneratedSchema> generate(String name, String source) async {
    final file = File('${fixtures.path}/$name.dart');
    await file.writeAsString("import 'package:orm/schema.dart';\n$source");
    return generateSchema(file.path);
  }

  test('record annotations, physical names, relations and snapshots', () async {
    final result = await generateSchema('example/schema.dart');
    expect(result.dart, contains('Future<models.User> create('));
    expect(result.dart, contains('Change<int> score'));
    expect(
      result.dart,
      contains('Relation<models.Post, PostsFields> get posts'),
    );
    final tables = result.snapshot['tables'] as List<Object?>;
    expect(tables.length, 2);
    expect((tables[1] as Map<String, Object?>)['foreignKeys'], [
      {
        'columns': ['author_id'],
        'target': 'users',
        'targetColumns': ['id'],
        'onDelete': 'CASCADE',
      },
    ]);
  });

  test(
    'output is deterministic and matches the committed generated client',
    () async {
      final result = await generateSchema('example/schema.dart');
      final temporary = File('${fixtures.path}/deterministic.dart');
      await temporary.writeAsString(result.dart);
      final format = await Process.run(Platform.resolvedExecutable, [
        'format',
        temporary.path,
      ]);
      expect(format.exitCode, 0);
      expect(
        await temporary.readAsString(),
        await File('example/schema.orm.dart').readAsString(),
      );
    },
  );

  test(
    'composite keys and more than six fields generate analyzable code',
    () async {
      await generate('composite', '''
typedef Account = ({int tenant, int id, String email, int a, int b, int c, int d, int e});
typedef Event = ({int tenant, int owner, String title});
final accounts = entity<Account>();
final events = entity<Event>();
final accountKey = accounts.primaryKey((a) => (a.tenant, a.id));
final ownerAccount = events.key((e) => (e.tenant, e.owner)).references(accounts.key((a) => (a.tenant, a.id)), inverse: 'events');
''');
      final source = '${fixtures.path}/composite.dart';
      await writeGeneratedSchema(source);
      final analysis = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '${fixtures.path}/composite.orm.dart',
      ]);
      expect(
        analysis.exitCode,
        0,
        reason: '${analysis.stdout}\n${analysis.stderr}',
      );
    },
  );

  test('computed keys are rejected instead of executing a fake row', () async {
    await expectLater(
      generate('computed', '''
typedef User = ({int id});
final users = entity<User>();
final key = users.primaryKey((u) => u.id + 1);
'''),
      throwsA(isA<GenerationException>()),
    );
  });

  test('foreign keys require unique targets', () async {
    await expectLater(
      generate('not_unique', '''
typedef User = ({int id});
typedef Post = ({int authorId});
final users = entity<User>();
final posts = entity<Post>();
final author = posts.key((p) => p.authorId).references(users.key((u) => u.id));
'''),
      throwsA(isA<GenerationException>()),
    );
  });

  test('Dart type errors stop generation', () async {
    await expectLater(
      generate('type_error', '''
typedef User = ({@Id() int id});
typedef Post = ({String authorId});
final users = entity<User>();
final posts = entity<Post>();
final author = posts.key((p) => p.authorId).references(users.key((u) => u.id));
'''),
      throwsA(isA<GenerationException>()),
    );
  });

  test(
    'duplicate physical names and nullable primary keys are rejected',
    () async {
      await expectLater(
        generate('duplicate', '''
typedef User = ({@ColumnName('x') int id, @ColumnName('x') String name});
final users = entity<User>();
'''),
        throwsA(isA<GenerationException>()),
      );
      await expectLater(
        generate('nullable_id', '''
typedef User = ({@Id() int? id});
final users = entity<User>();
'''),
        throwsA(isA<GenerationException>()),
      );
    },
  );
}
