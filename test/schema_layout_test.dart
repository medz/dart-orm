@Tags(['core'])
library;

import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/src/generate/schema/layout.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _model(String name, String table, {String? namespace}) =>
    '''
@Model(table: '$table'${namespace == null ? '' : ", namespace: '$namespace'"})
class $name {
  @Id(generated: true) final int id;
  const $name({required this.id});
}
''';

void main() {
  test('recursive layout respects Windows and URL asset path contexts', () {
    for (final paths in [p.Context(style: p.Style.windows), p.url]) {
      final layout = SchemaLayout(
        'lib/fixture/./schema.dart',
        directory: true,
        paths: paths,
      );
      expect(layout.root, paths.join('lib', 'fixture', 'schema'));
      expect(layout.includes('lib/fixture/schema/auth/users.dart'), isTrue);
      expect(layout.includes('lib/fixture/schema.dart'), isTrue);
      expect(
        layout.includes('lib/fixture/schema/auth/deep/users.dart'),
        isTrue,
      );
      expect(layout.includes('lib/other/auth/users.dart'), isFalse);
      expect(
        layout.includes('lib/fixture/schema/deep/client.orm.dart'),
        isFalse,
      );
      expect(
        layout.includes('lib/fixture/schema/deep/client.snapshot.dart'),
        isFalse,
      );
    }
  });

  late Directory project;
  setUp(
    () async =>
        project = await Directory('.dart_tool').createTemp('schema-layout-'),
  );
  tearDown(() => project.delete(recursive: true));

  Future<void> source(String path, String body) async {
    final file = File('${project.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString("import 'package:orm/schema.dart';\n$body");
  }

  for (final dialect in SqlDialect.values) {
    test(
      '${dialect.name} rejects outputs discovered as model inputs',
      () async {
        const directory = 'schema/features/users';
        await source('$directory/user.dart', _model('User', 'users'));
        for (final output in [
          'schema.dart',
          '$directory/client.dart',
          'schema/client.dart',
        ]) {
          await expectLater(
            writeGeneratedSchema(
              '${project.path}/schema',
              output: '${project.path}/$output',
              dialect: dialect,
            ),
            throwsA(isA<GenerationException>()),
          );
          expect(File('${project.path}/$output').existsSync(), isFalse);
          expect(
            File(p.setExtension('${project.path}/$output', '.snapshot.dart'))
                .existsSync(),
            isFalse,
          );
        }
        final output = '${project.path}/$directory/client.orm.dart';
        await writeGeneratedSchema(
          '${project.path}/schema',
          output: output,
          dialect: dialect,
        );
        final before = await File(output).readAsString();
        await writeGeneratedSchema(
          '${project.path}/schema',
          output: output,
          dialect: dialect,
        );
        expect(await File(output).readAsString(), before);
      },
    );
  }

  test(
    'explicit PG namespaces retain DTO names and cross-schema references',
    () async {
      await source('schema/features/accounts.dart', '''
@Model(table: 'Users', namespace: 'auth')
class Account {
  @Id(generated: true) final int id;
  @Column(name: 'DisplayName') final String displayName;
  const Account({required this.id, required this.displayName});
}
''');
      await source('schema/users.dart', '''
import 'features/accounts.dart';
@Model(table: 'Users')
class User {
  @Id(generated: true) final int id;
  @Relation(target: Account, name: 'account') final int accountId;
  const User({required this.id, required this.accountId});
}
''');
      final result = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      expect(result.snapshot.tables.map((t) => t.identity), [
        'auth.Users',
        'public.Users',
      ]);
      expect(
        result.snapshot.tables.last.foreignKeys.single.targetNamespace,
        'auth',
      );
      expect(result.dart, contains('get account =>'));
      expect(result.dart, contains('get user =>'));
      expect(result.dart, isNot(contains('get auth =>')));
      expect(result.dart, isNot(contains('get public =>')));
      await writeGeneratedSchema('${project.path}/schema/', dialect: .postgres);
      final analysis = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        project.path,
      ]);
      expect(
        analysis.exitCode,
        0,
        reason: '${analysis.stdout}\n${analysis.stderr}',
      );
      final sql = Migration.create(
        '0001_initial',
        result.snapshot.tables,
        dialect: .postgres,
      ).steps.cast<ExecuteSql>().map((s) => s.sql).join('\n');
      expect(sql, contains('CREATE TABLE "auth"."Users"'));
      expect(sql, contains('REFERENCES "auth"."Users"'));
    },
  );

  test(
    'all entry spellings merge the sibling file and recursive directory once',
    () async {
      await source(
        'schema.dart',
        "export 'schema/features/users.dart';\n${_model('Post', 'posts')}",
      );
      await source('schema/features/users.dart', _model('User', 'users'));
      final checksums = <String>{};
      for (final suffix in ['schema', 'schema/', 'schema.dart']) {
        final result = await generateSchema(
          '${project.path}/$suffix',
          dialect: .postgres,
        );
        checksums.add(result.snapshot.checksum);
        expect(result.snapshot.tables.map((t) => t.identity), [
          'public.posts',
          'public.users',
        ]);
        expect(result.dart, contains('get user =>'));
        expect(result.dart, isNot(contains('get public =>')));
      }
      expect(checksums, hasLength(1));
    },
  );

  test('directory discovery supports engine-neutral snapshots', () async {
    await source('schema/features/users.dart', _model('User', 'users'));
    final result = await generateSchema('${project.path}/schema');
    expect(result.snapshot.tables.single.namespace, isNull);
  });

  test(
    'splitting a model file into recursive directories preserves the snapshot',
    () async {
      final posts = _model('Post', 'posts'), users = _model('User', 'users');
      await source('schema.dart', '$users\n$posts');
      final before = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      await source('schema.dart', users);
      await source('schema/features/deep/posts.dart', posts);
      final after = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      expect(after.snapshot.checksum, before.snapshot.checksum);
      expect(
        Migration.diff(
          '0002_split',
          dialect: .postgres,
          from: before.snapshot,
          to: after.snapshot,
        ).steps,
        isEmpty,
      );
    },
  );

  test(
    'qualifying an unqualified snapshot requires destructive opt-in',
    () async {
      await source('schema.dart', '''
${_model('User', 'users')}
@Model(table: 'posts')
class Post {
  @Id(generated: true) final int id;
  @Relation(target: User, name: 'author') final int authorId;
  const Post({required this.id, required this.authorId});
}
''');
      final neutral = await generateSchema('${project.path}/schema');
      final targeted = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      expect(
        () => Migration.diff(
          '0002_qualified',
          dialect: .postgres,
          from: neutral.snapshot,
          to: targeted.snapshot,
        ),
        throwsA(
          isA<OrmException>().having(
            (e) => e.code,
            'code',
            'MIGRATION.DESTRUCTIVE',
          ),
        ),
      );
      expect(
        () => Migration.diff(
          '0002_renamed',
          dialect: .postgres,
          from: neutral.snapshot,
          to: targeted.snapshot,
          renames: SchemaRenames(
            tables: {'users': 'public.users', 'posts': 'public.posts'},
          ),
        ),
        throwsA(
          isA<OrmException>().having((e) => e.code, 'code', 'MIGRATION.RENAME'),
        ),
      );
      final change = Migration.diff(
        '0002_qualified',
        dialect: .postgres,
        from: neutral.snapshot,
        to: targeted.snapshot,
        allowDestructive: true,
      );
      expect(change.steps.whereType<DropTable>().map((s) => s.table).toSet(), {
        'users',
        'posts',
      });
      expect(
        change.steps.whereType<ExecuteSql>().map((s) => s.sql).join('\n'),
        contains('CREATE TABLE "public"."users"'),
      );
      expect(
        change.snapshot!.tables.every((t) => t.namespace == 'public'),
        true,
      );
    },
  );

  for (final dialect in [
    SqlDialect.sqlite,
    SqlDialect.mysql,
    SqlDialect.mariadb,
  ]) {
    test(
      '${dialect.name} recursively collects files without namespaces',
      () async {
        await source('schema/users.dart', _model('User', 'users'));
        await source('schema/nested/posts.dart', _model('Post', 'posts'));
        final result = await generateSchema(
          '${project.path}/schema',
          dialect: dialect,
        );
        expect(result.snapshot.tables.map((t) => t.name), ['posts', 'users']);
        expect(result.snapshot.tables.every((t) => t.namespace == null), true);
      },
    );
  }

  test(
    'moving model sources across folders preserves physical identity',
    () async {
      await source(
        'schema/auth/users.dart',
        _model('User', 'users', namespace: 'identity'),
      );
      final before = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      await Directory('${project.path}/schema/features/deep')
          .create(recursive: true);
      await File('${project.path}/schema/auth/users.dart')
          .rename('${project.path}/schema/features/deep/accounts.dart');
      final after = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      expect(after.snapshot.checksum, before.snapshot.checksum);
      expect(after.snapshot.tables.single.namespace, 'identity');
    },
  );

  test(
    'dotted table names fail instead of being interpreted as qualification',
    () async {
      await source('schema.dart', _model('User', 'auth.users'));
      await expectLater(
        generateSchema('${project.path}/schema.dart', dialect: .postgres),
        throwsA(isA<GenerationException>()),
      );
    },
  );

  test(
    'conflicting physical declarations fail across source directories',
    () async {
      await source('schema.dart', _model('User', 'users'));
      await source('schema/nested/accounts.dart', _model('Account', 'users'));
      await expectLater(
        generateSchema('${project.path}/schema', dialect: .postgres),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.toString(),
            'diagnostic',
            contains('Duplicate physical table'),
          ),
        ),
      );
    },
  );
}
