import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/src/generate/schema/layout.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('layout respects native Windows and URL asset path contexts', () {
    for (final paths in [p.Context(style: p.Style.windows), p.url]) {
      final layout = SchemaLayout(
        'lib/fixture/./schema.dart',
        dialect: .postgres,
        directory: true,
        paths: paths,
      );
      expect(layout.root, paths.join('lib', 'fixture', 'schema'));
      expect(layout.includes('lib/fixture/schema/auth/users.dart'), isTrue);
      expect(layout.namespace('lib/fixture/schema/auth/users.dart'), 'auth');
      expect(layout.namespace('lib/fixture/schema.dart'), 'public');
      expect(
        layout.includes('lib/fixture/schema/auth/deep/users.dart'),
        isFalse,
      );
      expect(layout.includes('lib/other/auth/users.dart'), isFalse);
    }
  });

  late Directory project;
  setUp(() async {
    project = await Directory('.dart_tool').createTemp('schema-layout-');
  });
  tearDown(() => project.delete(recursive: true));

  Future<void> source(String path, String body) async {
    final file = File('${project.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString("import 'package:orm/schema.dart';\n$body");
  }

  for (final dialect in SqlDialect.values) {
    test(
      '${dialect.name} rejects outputs discovered as schema inputs',
      () async {
        final directory = dialect == SqlDialect.postgres
            ? 'schema/public'
            : 'schema';
        await source(
          '$directory/users.dart',
          "final user = model('users', (id: identity(),));",
        );
        for (final output in {
          'schema.dart',
          '$directory/client.dart',
          'schema/client.dart',
        }) {
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
    'PG directory namespaces, repeated names and cross-schema references',
    () async {
      await source(
        'schema/auth/users.dart',
        "final user = model('Users', (id: identity(), displayName: text(name: 'DisplayName')));",
      );
      await source(
        'schema/public/users.dart',
        "import '../auth/users.dart' as auth;\nfinal user = model('Users', (id: identity(), accountId: integer()), relations: (u) => (account: references(u.accountId, () => auth.user),));",
      );
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
      expect(result.dart, contains('final class AuthUser('));
      expect(result.dart, contains('final class PublicUser('));
      expect(result.dart, contains('get auth =>'));
      expect(result.dart, contains('get public =>'));
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
    'all entry spellings merge the default file and directory once',
    () async {
      await source(
        'schema.dart',
        "export 'schema/public/users.dart';\nfinal post = model('posts', (id: identity(),));",
      );
      await source(
        'schema/public/users.dart',
        "final user = model('users', (id: identity(),));",
      );
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

  test('directory generation requires an offline engine selection', () async {
    await source(
      'schema/users.dart',
      "final user = model('users', (id: identity(),));",
    );
    await expectLater(
      generateSchema('${project.path}/schema'),
      throwsA(isA<GenerationException>()),
    );
  });

  test(
    'splitting a targeted file into public preserves the snapshot',
    () async {
      const posts = "final post = model('posts', (id: identity(),));";
      const users = "final user = model('users', (id: identity(),));";
      await source('schema.dart', '$users\n$posts');
      final before = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      await source('schema.dart', users);
      await source('schema/public/posts.dart', posts);
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
    'replacing unqualified PostgreSQL snapshots requires destructive opt-in',
    () async {
      await source('schema.dart', '''
final user = model('users', (id: identity(),));
final post = model('posts', (id: identity(), authorId: integer()),
  relations: (p) => (author: references(p.authorId, () => user),));
''');
      final legacy = await generateSchema('${project.path}/schema');
      final current = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      expect(
        () => Migration.diff(
          '0002_qualified',
          dialect: .postgres,
          from: legacy.snapshot,
          to: current.snapshot,
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
          from: legacy.snapshot,
          to: current.snapshot,
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
        from: legacy.snapshot,
        to: current.snapshot,
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
      '${dialect.name} collects direct files without namespaces or recursion',
      () async {
        await source(
          'schema/users.dart',
          "final user = model('users', (id: identity(),));",
        );
        await source(
          'schema/nested/posts.dart',
          "final post = model('posts', (id: identity(),));",
        );
        final result = await generateSchema(
          '${project.path}/schema',
          dialect: dialect,
        );
        expect(result.snapshot.tables.map((t) => t.name), ['users']);
        expect(result.snapshot.tables.single.namespace, isNull);
      },
    );
  }

  test('references cannot pull models through deeper directories', () async {
    await source(
      'schema/auth/users.dart',
      "import 'nested/accounts.dart';\nfinal user = model('users', (id: identity(), accountId: integer()), relations: (u) => (account: references(u.accountId, () => account),));",
    );
    await source(
      'schema/auth/nested/accounts.dart',
      "final account = model('accounts', (id: identity(),));",
    );
    await expectLater(
      generateSchema('${project.path}/schema', dialect: .postgres),
      throwsA(
        isA<GenerationException>().having(
          (e) => e.toString(),
          'diagnostic',
          contains('outside the schema layout'),
        ),
      ),
    );
  });

  test(
    'moving declarations within a namespace preserves physical identity',
    () async {
      await source(
        'schema/auth/users.dart',
        "final user = model('users', (id: identity(),));",
      );
      final before = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      await File('${project.path}/schema/auth/users.dart')
          .rename('${project.path}/schema/auth/accounts.dart');
      final after = await generateSchema(
        '${project.path}/schema',
        dialect: .postgres,
      );
      expect(after.snapshot.checksum, before.snapshot.checksum);
    },
  );

  test(
    'dotted table names fail instead of being interpreted as qualification',
    () async {
      await source(
        'schema.dart',
        "final user = model('auth.users', (id: identity(),));",
      );
      await expectLater(
        generateSchema('${project.path}/schema.dart', dialect: .postgres),
        throwsA(
          isA<OrmException>().having(
            (e) => e.code,
            'code',
            'SCHEMA.IDENTIFIER',
          ),
        ),
      );
    },
  );

  test(
    'PG rejects direct directory files and conflicting physical declarations',
    () async {
      await source(
        'schema/users.dart',
        "final user = model('users', (id: identity(),));",
      );
      await expectLater(
        generateSchema('${project.path}/schema', dialect: .postgres),
        throwsA(isA<GenerationException>()),
      );
      await File('${project.path}/schema/users.dart').delete();
      await source(
        'schema.dart',
        "final user = model('users', (id: identity(),));",
      );
      await source(
        'schema/public/users.dart',
        "final user = model('users', (id: identity(),));",
      );
      await expectLater(
        generateSchema('${project.path}/schema', dialect: .postgres),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.toString(),
            'diagnostic',
            contains('also declared'),
          ),
        ),
      );
    },
  );
}
