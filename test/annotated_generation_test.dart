@Tags(['core'])
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';

import 'package:orm/generate.dart';
import 'package:orm/driver.dart' show SqlDialect;
import 'package:test/test.dart';

void main() {
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory('.dart_tool')
        .createTemp('annotated-generation-');
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  Future<File> source(String name, String contents) async {
    final file = File('${fixtures.path}/$name.dart');
    await file.parent.create(recursive: true);
    await file.writeAsString("import 'package:orm/schema.dart';\n$contents");
    return file;
  }

  Future<GeneratedSchema> generate(String name, String contents) async =>
      generateSchema((await source(name, contents)).path);

  test(
    'parameter and field annotations preserve constructor key order',
    () async {
      final result = await generate('composite', '''
@Model(table: 'teams')
@Unique(['slug'])
class Team {
  @Id()
  final String code;
  @Id()
  final int tenant;
  final String slug;
  const Team({required this.tenant, required this.code, required this.slug});
}
@Model(table: 'members')
@Relation(target: Team, name: 'team', fields: ['tenant', 'teamCode'],
  keys: ['tenant', 'code'], inverse: 'members', onDelete: .cascade)
@Index(['teamCode', 'tenant'], name: 'members_team')
class Member {
  final int id;
  final int tenant;
  @Column(name: 'team_code')
  final String teamCode;
  @Relation(target: Team, name: 'bySlug', key: 'slug')
  final String slug;
  const Member({@Id() required this.id, required this.tenant,
    required this.teamCode, required this.slug});
}
''');
      final team = result.snapshot.tables.singleWhere((t) => t.name == 'teams');
      final member = result.snapshot.tables.singleWhere(
        (t) => t.name == 'members',
      );
      expect(team.primaryKey, ['tenant', 'code']);
      expect(member.foreignKeys.first.columns, ['tenant', 'team_code']);
      expect(member.foreignKeys.first.targetColumns, ['tenant', 'code']);
      expect(member.foreignKeys.first.onDelete, 'CASCADE');
      expect(member.foreignKeys.last.targetColumns, ['slug']);
      expect(member.indexes.single.columns, ['team_code', 'tenant']);
      expect(result.dart, contains('get team =>'));
      expect(result.dart, contains('get members =>'));
      expect(result.dart, contains('get bySlug =>'));
      expect(result.dart, isNot(contains('final class Team(')));
    },
  );

  test(
    'exports and relations discover original DTOs without unrelated imports',
    () async {
      await source('split/team', '''
@Model()
class Team {
  @Id()
  final int id;
  const Team({required this.id});
}
''');
      await source('split/person', '''
import 'team.dart';
import 'unrelated.dart';
@Model()
class Person {
  @Id()
  final int id;
  @Relation(target: Team, name: 'team', inverse: 'people')
  final int teamId;
  const Person({required this.id, required this.teamId});
}
''');
      await source('split/unrelated', '''
@Model()
class Unrelated {
  final Object unsupported;
  const Unrelated({required this.unsupported});
}
''');
      final root = await source(
        'split/root',
        "export 'person.dart' show Person;",
      );
      final generated = await generateSchema(root.path);
      expect(generated.snapshot.tables.map((t) => t.name), ['Person', 'Team']);
      expect(generated.dart, contains('show Person'));
      expect(generated.dart, contains('show Team'));
      expect(generated.dart, isNot(contains('Unrelated')));
      await writeGeneratedSchema(root.path);
      final analysis = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '${fixtures.path}/split/root.orm.dart',
      ]);
      expect(
        analysis.exitCode,
        0,
        reason: '${analysis.stdout}\n${analysis.stderr}',
      );
    },
  );

  test(
    'explicit namespace wins without changing generated DTO names',
    () async {
      final file = await source('namespace', '''
@Model(table: 'members', namespace: 'accounts')
class User {
  @Id()
  final int id;
  const User({required this.id});
}
@Model(table: 'posts')
class Post {
  @Id()
  final int id;
  @Relation(target: User, name: 'author')
  final int authorId;
  const Post({required this.id, required this.authorId});
}
''');
      final result = await generateSchema(
        file.path,
        dialect: .postgres,
        defaultNamespace: 'content',
      );
      expect(result.snapshot.tables.map((t) => t.identity), [
        'accounts.members',
        'content.posts',
      ]);
      final posts = result.snapshot.tables.last;
      expect(posts.foreignKeys.single.targetNamespace, 'accounts');
      expect(result.dart, contains('get user =>'));
      expect(result.dart, contains('get post =>'));
      expect(result.dart, isNot(contains('get accounts =>')));
      expect(result.dart, isNot(contains('AccountsUser')));
      final defaults = await generateSchema(file.path, dialect: .postgres);
      expect(defaults.snapshot.tables.map((t) => t.identity), [
        'accounts.members',
        'public.posts',
      ]);
    },
  );

  test(
    'recursive model discovery ignores directories as namespace metadata',
    () async {
      await source('models/features/accounts/user', '''
@Model()
class User {
  @Id()
  final int id;
  const User({required this.id});
}
''');
      await source('models/direct', '''
@Model(namespace: 'audit')
class Audit {
  @Id()
  final int id;
  const Audit({required this.id});
}
''');
      final result = await generateSchema(
        '${fixtures.path}/models',
        dialect: .postgres,
        defaultNamespace: 'app',
      );
      expect(result.snapshot.tables.map((t) => t.identity), [
        'app.User',
        'audit.Audit',
      ]);
      expect(result.dart, contains('get user =>'));
      expect(result.dart, contains('get audit =>'));
      await writeGeneratedSchema(
        '${fixtures.path}/models',
        dialect: .postgres,
        defaultNamespace: 'app',
      );
      final again = await generateSchema(
        '${fixtures.path}/models',
        dialect: .postgres,
        defaultNamespace: 'app',
      );
      expect(again.dart, result.dart);
      expect(again.snapshotDart, result.snapshotDart);
    },
  );

  test(
    'physical snapshot is independent of DTO name and declaration order',
    () async {
      String body(String first, String second, {bool reverse = false}) {
        final declarations = [
          '''@Model(table: 'people')
class $first {
  @Id() final int id;
  @Column(name: 'display_name') final String name;
  const $first({required this.id, required this.name});
}''',
          '''@Model(table: 'logs')
class $second {
  @Id() final int id;
  const $second({required this.id});
}''',
        ];
        return (reverse ? declarations.reversed : declarations).join('\n');
      }

      final before = await generate('before', body('User', 'Log'));
      final after = await generate(
        'after',
        body('Member', 'Audit', reverse: true),
      );
      expect(after.snapshotDart, before.snapshotDart);
      expect(after.snapshot.checksum, before.snapshot.checksum);
      expect(after.snapshotDart, isNot(contains('after.dart')));
    },
  );

  test(
    'client defaults are referenced without executing application code',
    () async {
      final generated = await generate('client_defaults', '''
String forbidden() => throw StateError('application code was executed');
@Model()
class User {
  @Id(generated: true) final int id;
  @ClientDefault(forbidden) final String token;
  @DatabaseDefault(true) final bool active;
  final String label;
  final String? alias;
  @Ignore() final String local;
  const User({required this.id, required this.token, this.active = false,
      this.label = 'guest', this.alias, this.local = 'local'});
}
''');
      final table = generated.snapshot.tables.single;
      expect(table.columns.map((c) => c.name), [
        'id',
        'token',
        'active',
        'label',
        'alias',
      ]);
      expect(
        table.columns.singleWhere((c) => c.name == 'active').defaultSql,
        'true',
      );
      expect(
        table.columns.singleWhere((c) => c.name == 'label').defaultSql,
        isNull,
      );
      expect(generated.dart, contains('clientDefault: models.forbidden'));
      expect(generated.dart, contains('clientDefault: () => "guest"'));
      expect(generated.snapshotDart, isNot(contains('forbidden')));
    },
  );

  test(
    'generated DTO APIs reject wrong input types and identity patches',
    () async {
      final models = await source('typing/models', """
@Model()
final class User({
  @Id(generated: true) required final int id,
  required final String name,
  final String? nickname,
  @Ignore() final String local = 'local',
}) {}
""");
      await writeGeneratedSchema(models.path);
      const invalid = [
        "users.create(name: 7);",
        "users.create(name: null);",
        "users.create(name: 'ok', nickname: 7);",
        "users.patch(id: 1);",
        "users.patch(local: 'hidden');",
      ];
      final consumer = File('${fixtures.path}/typing/consumer.dart').absolute;
      await consumer.writeAsString("""
import 'models.dart' as original;
import 'models.orm.dart';
Future<original.User> valid(UserTableSet users) => users.create(name: 'ok', nickname: null);
void invalid(UserTableSet users) {
${invalid.join('\n')}
}
""");
      final contexts = AnalysisContextCollection(
        includedPaths: [consumer.path],
      );
      try {
        final result =
            await contexts
                    .contextFor(consumer.path)
                    .currentSession
                    .getResolvedUnit(consumer.path)
                as ResolvedUnitResult;
        final errors = result.diagnostics
            .where((e) => e.severity.name.toLowerCase() == 'error')
            .toList();
        expect(errors, hasLength(invalid.length), reason: errors.join('\n'));
        for (var i = 0; i < invalid.length; i++) {
          expect(
            errors.any(
              (e) => result.lineInfo.getLocation(e.offset).lineNumber == i + 5,
            ),
            true,
            reason: invalid[i],
          );
        }
      } finally {
        await contexts.dispose();
      }
    },
  );

  for (final (name, declaration, message) in _invalid) {
    test('rejects $name before emitting any output', () async {
      final file = await source('invalid_$name', declaration);
      await expectLater(
        writeGeneratedSchema(file.path),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
      final stem = file.path.substring(0, file.path.length - 5);
      expect(File('$stem.orm.dart').existsSync(), false);
      expect(File('$stem.snapshot.dart').existsSync(), false);
    });
  }

  test('rejects PostgreSQL-only namespaces for other engines', () async {
    final file = await source('sqlite_namespace', '''
@Model(namespace: 'accounts')
class User {
  @Id() final int id;
  const User({required this.id});
}
''');
    for (final dialect in [
      SqlDialect.sqlite,
      SqlDialect.mysql,
      SqlDialect.mariadb,
    ]) {
      await expectLater(
        generateSchema(file.path, dialect: dialect),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.message,
            'message',
            contains('PostgreSQL'),
          ),
        ),
      );
    }
  });
}

const _target = '''
@Model()
class Team {
  @Id() final int tenant;
  @Id() final int code;
  final int other;
  const Team({required this.tenant, required this.code, required this.other});
}
''';

const _invalid = <(String, String, String)>[
  (
    'transformed_constructor',
    '''
@Model()
class User {
  final int id;
  User({required int id}) : id = id + 1;
}
''',
    'The mapped constructor must directly',
  ),

  (
    'unknown_unique',
    '''
@Model() @Unique(['typo'])
class User { final int id; const User({required this.id}); }
''',
    'Unknown field',
  ),
  (
    'unknown_index',
    '''
@Model() @Index(['typo'], name: 'invalid')
class User { final int id; const User({required this.id}); }
''',
    'Unknown field',
  ),
  (
    'duplicate_key_field',
    '''
@Model() @Unique(['id', 'id'])
class User { final int id; const User({required this.id}); }
''',
    'distinct fields',
  ),
  (
    'duplicate_annotation',
    '''
@Model()
class User { @Id() @Id() final int id; const User({required this.id}); }
''',
    'more than once',
  ),
  (
    'duplicate_column',
    '''
@Model()
class User { @Column(name: 'same') final int id; @Column(name: 'same') final int code;
const User({required this.id, required this.code}); }
''',
    'Duplicate physical column',
  ),
  (
    'duplicate_table',
    '''
@Model(table: 'same')
class User { final int id; const User({required this.id}); }
@Model(table: 'same')
class Person { final int id; const Person({required this.id}); }
''',
    'Duplicate physical table',
  ),
  (
    'nullable_primary_key',
    '''
@Model()
class User { @Id() final int? id; const User({this.id}); }
''',
    'Primary keys cannot be nullable',
  ),
  (
    'generated_composite_key',
    '''
@Model()
class User { @Id(generated: true) final int id; @Id() final int code;
const User({required this.id, required this.code}); }
''',
    'one integer-storage primary key',
  ),
  (
    'required_ignored_parameter',
    '''
@Model()
class User { final int id; @Ignore() final String local;
const User({required this.id, required this.local}); }
''',
    'ignored constructor parameter must be optional',
  ),
  (
    'default_null',
    '''
@Model()
class User { @DatabaseDefault(null) final int id; const User({required this.id}); }
''',
    'nullability',
  ),
  (
    'invalid_codec_type',
    '''
String decodeString(Object? value) => value as String;
String encodeString(String value) => value;
const wrongCodec = Codec<String>.text(decodeString, encodeString);
@Model()
class User { @Column(codec: wrongCodec) final int id; const User({required this.id}); }
''',
    'Codec value type',
  ),
  (
    'unsupported_type',
    '''
@Model()
class User { final Object id; const User({required this.id}); }
''',
    'Unsupported persistent type',
  ),
  (
    'missing_target',
    '''
class Team { const Team(); }
@Model()
class User { @Relation(target: Team, name: 'team') final int id;
const User({required this.id}); }
''',
    'reachable @Model',
  ),
  (
    'unknown_reference',
    '''
$_target
@Model()
class User { @Relation(target: Team, name: 'team', key: 'typo') final int id;
const User({required this.id}); }
''',
    'Reference fields must exist',
  ),
  (
    'composite_order',
    '''
$_target
@Model()
@Relation(target: Team, name: 'team', fields: ['tenant', 'code'], keys: ['code', 'tenant'])
class User { final int tenant; final int code;
const User({required this.tenant, required this.code}); }
''',
    'ordered primary or unique key',
  ),
  (
    'reference_type',
    '''
@Model()
class Team { @Id() final int id; const Team({required this.id}); }
@Model()
class User { @Relation(target: Team, name: 'team') final String id;
const User({required this.id}); }
''',
    'matching value types',
  ),
  (
    'reference_codec',
    '''
int readInt(Object? value) => value as int;
int writeInt(int value) => value;
const alternate = Codec<int>.integer(readInt, writeInt);
@Model()
class Team { @Id() final int id; const Team({required this.id}); }
@Model()
class User { @Column(codec: alternate) @Relation(target: Team, name: 'team') final int id;
const User({required this.id}); }
''',
    'matching value types',
  ),
  (
    'set_null_nonnullable',
    '''
@Model()
class Team { @Id() final int id; const Team({required this.id}); }
@Model()
class User { @Relation(target: Team, name: 'team', onDelete: .setNull) final int id;
const User({required this.id}); }
''',
    'SET NULL requires nullable',
  ),
  (
    'duplicate_relation',
    '''
@Model()
class Team { @Id() final int id; const Team({required this.id}); }
@Model()
class User { @Relation(target: Team, name: 'team') final int first;
@Relation(target: Team, name: 'team') final int second;
const User({required this.first, required this.second}); }
''',
    'duplicate relation',
  ),
];
