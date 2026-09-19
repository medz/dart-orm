import 'dart:io';

import 'package:orm/generate.dart';
import 'package:test/test.dart';

void main() {
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory('.dart_tool/orm-nominal-tests')
        .create(recursive: true);
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  Future<GeneratedSchema> generate(String name, String source) async {
    final file = File('${fixtures.path}/$name.dart');
    await file.writeAsString("import 'package:orm/schema.dart';\n$source");
    return generateSchema(file.path);
  }

  Future<ProcessResult> analyze(String path) =>
      Process.run(Platform.resolvedExecutable, ['analyze', path]);

  test(
    'wide nominal rows and metadata match the committed generated fixture',
    () async {
      const source = 'test/support/nominal/schema.dart';
      final result = await generateSchema(source);
      expect(
        result.dart,
        await File('test/support/nominal/schema.orm.dart').readAsString(),
      );
      expect(
        result.snapshotDart,
        await File('test/support/nominal/schema.snapshot.dart').readAsString(),
      );
      expect(result.dart, contains('models.Account('));
      expect(result.dart, contains('models.emailCodec'));
      expect(result.dart, contains('models.defaultMarker'));
      expect(
        result.dart,
        contains('Relation<models.Note, NotesFields> get notes'),
      );
      expect(result.dart, isNot(contains("import 'package:orm/orm.dart'")));
      final analysis = await analyze('test/support/nominal/schema.orm.dart');
      expect(
        analysis.exitCode,
        0,
        reason: '${analysis.stdout}\n${analysis.stderr}',
      );
    },
  );

  test('named, positional, mixed and single-field constructors materialize directly', () async {
    await generate('constructors', '''
final class Named({@Id() required final int id, required final String models});
final class Positional(@Id() final int id, final String models);
final class Mixed(@Id() final int id, {required final String name});
final class Single(@Id() final int id);
final class const Constant(@Id() final int id);
final named = entity<Named>();
final positional = entity<Positional>();
final mixed = entity<Mixed>();
final single = entity<Single>();
final constants = entity<Constant>();
''');
    final source = '${fixtures.path}/constructors.dart';
    await writeGeneratedSchema(source);
    final result = await analyze('${fixtures.path}/constructors.orm.dart');
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final generated = await File('${fixtures.path}/constructors.orm.dart')
        .readAsString();
    expect(generated, contains('models.Named(id: v0, models: v1)'));
    expect(generated, contains('models.Positional(v0, v1)'));
    expect(generated, contains('models.Mixed(v0, name: v1)'));
    expect(generated, contains('models.Single(value)'));
    expect(generated, contains('models.Constant(value)'));
  });

  test('nominal rows and generated writes reject structural and field type mistakes', () async {
    await generate('types', '''
final class User(@Id.generated() final int id, final String email, final String? name);
final class Audit(@Id.generated() final int id, final String email, final String? name);
final users = entity<User>();
final audits = entity<Audit>();
''');
    await writeGeneratedSchema('${fixtures.path}/types.dart');
    final consumer = File('${fixtures.path}/consumer.dart');
    const prefix = '''
import 'package:orm/orm.dart';
import 'types.orm.dart';
Future<void> consume(Database<Backend> db) async {
''';
    await consumer.writeAsString('''
$prefix
  final User user = await db.users.create(email: 'a');
  await db.users.byId(user.id).patch(name: .set(null));
  final List<({int id, String email})> cards = await db.users
      .select((u) => (u.id, u.email).map((id, email) => (id: id, email: email)))
      .get();
  print(cards);
}
''');
    final valid = await analyze(consumer.path);
    expect(valid.exitCode, 0, reason: '${valid.stdout}\n${valid.stderr}');
    for (final statement in [
      "final User user = await db.audits.create(email: 'a'); print(user);",
      "final User user = (id: 1, email: 'a', name: null); print(user);",
      'await db.users.create(email: 42);',
      'await db.users.byId(1).patch(name: .set(42));',
      'await db.users.byId(1).patch(id: .set(42));',
      'await db.users.select((u) => u.missing).get();',
    ]) {
      await consumer.writeAsString('$prefix$statement\n}\n');
      final invalid = await analyze(consumer.path);
      expect(invalid.exitCode, isNot(0), reason: statement);
      expect('${invalid.stdout}', contains('error -'), reason: statement);
    }
    await consumer.delete();
  });

  test(
    'class and Record declarations produce the same frozen physical schema',
    () async {
      final record = await generate('record_snapshot', '''
typedef User = ({@Id.generated() int id, @Unique() String email, @ColumnName('display_name') String? name, @Default.sql('false') bool enabled});
final users = entity<User>();
''');
      final nominal = await generate('nominal_snapshot', '''
final class User({@Id.generated() required final int id, @Unique() required final String email, @ColumnName('display_name') required final String? name, @Default.sql('false') required final bool enabled});
final users = entity<User>();
''');
      expect(nominal.snapshotDart, record.snapshotDart);
      expect(nominal.snapshotDart, isNot(contains('models.')));
      final renamed = await generate('nominal_rename', '''
final class User({@Id.generated() required final int id, @Unique() @ColumnName('email') required final String contactEmail, @ColumnName('display_name') required final String? name, @Default.sql('false') required final bool enabled});
final users = entity<User>();
''');
      expect(renamed.snapshotDart, nominal.snapshotDart);
    },
  );

  test(
    'class models reject ambiguous construction and unsupported behavior',
    () async {
      final cases = [
        'class User(final int id);',
        'final class User(var int id);',
        'final class User(int id);',
        'final class User(final id);',
        'final class User({final int id = 0});',
        'final class User({final int? id});',
        'final class User(final int _id);',
        'final class User.named(final int id);',
        'final class User(final int id) { this { print(id); } }',
        'final class User(final int id) { int get computed => id + 1; }',
        'final class User { final int id; User(this.id); }',
      ];
      for (var i = 0; i < cases.length; i++) {
        await expectLater(
          generate('invalid_$i', '${cases[i]}\nfinal users = entity<User>();'),
          throwsA(isA<GenerationException>()),
          reason: cases[i],
        );
      }
      await expectLater(
        generate(
          'generic',
          'final class User<T>(final T id); final users = entity<User<int>>();',
        ),
        throwsA(isA<GenerationException>()),
      );
      await expectLater(
        generate(
          'private',
          'final class _User(final int id); final users = entity<_User>();',
        ),
        throwsA(isA<GenerationException>()),
      );
    },
  );

  test(
    'class metadata and relationship validation use the production validators',
    () async {
      for (final source in [
        'final class User(@Id() final int? id); final users = entity<User>();',
        'final class User(@ColumnName("id") final int a, @ColumnName("id") final int b); final users = entity<User>();',
        'final class User(final int id); final users = entity<User>(); final bad = users.primaryKey((u) => u.id + 1);',
        'final class User(final int id); final users = entity<User>(); final bad = users.unique((u) => (u.id, u.id));',
        'final class User(final int id); final class Post(final int owner); final users = entity<User>(); final posts = entity<Post>(); final owner = posts.key((p) => p.owner).references(users.key((u) => u.id));',
        'final class User(@Id() final int id); final class Post(final String owner); final users = entity<User>(); final posts = entity<Post>(); final owner = posts.key((p) => p.owner).references(users.key((u) => u.id));',
        'final class User(@Computed.sql("1") @Default.sql("0") final int id); final users = entity<User>();',
      ]) {
        await expectLater(
          generate('bad_metadata', source),
          throwsA(isA<GenerationException>()),
          reason: source,
        );
      }
    },
  );
}
