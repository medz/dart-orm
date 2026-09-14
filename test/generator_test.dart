import 'dart:io';
import 'dart:convert';

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
      for (final source in [
        'example/schema.dart',
        'test/support/relations/schema.dart',
        'test/support/codecs/schema.dart',
        'test/support/integers/schema.dart',
        'test/support/decimals/schema.dart',
      ]) {
        final result = await generateSchema(source);
        final temporary = File('${fixtures.path}/deterministic.dart');
        await temporary.writeAsString(result.dart);
        final format = await Process.run(Platform.resolvedExecutable, [
          'format',
          temporary.path,
        ]);
        expect(format.exitCode, 0);
        final base = source.substring(0, source.length - 5);
        expect(
          await temporary.readAsString(),
          await File('$base.orm.dart').readAsString(),
        );
        expect(
          result.snapshot,
          jsonDecode(await File('$base.orm.json').readAsString()),
        );
      }
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

  test('custom types resolve defining libraries when output moves to another directory', () async {
    final output = '${fixtures.path}/nested/domain_client.dart';
    await writeGeneratedSchema(
      'test/support/codecs/schema.dart',
      output: output,
    );
    final result = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      output,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final source = await File(output).readAsString();
    expect(source, contains('Codec') /* static const codec references */);
    expect(source, contains('types0.Email'));
    expect(source, contains('types1.Email'));
  });

  test('nested generic and record types preserve nullable aliases without running codecs', () async {
    await generate('structured', '''
typedef Value = ({String label, List<int> numbers});
typedef Optional = Value?;
const valueCodec = Codec<Value>('json', decode, encode);
Value decode(Object? raw) => throw StateError('must not run');
String encode(Value value) => throw StateError('must not run');
const nestedCodec = Codec<List<({String name, int count})>>('json', decodeNested, encodeNested);
List<({String name, int count})> decodeNested(Object? raw) => throw StateError('must not run');
String encodeNested(List<({String name, int count})> value) => throw StateError('must not run');
typedef Row = ({@Id() int id, @UseCodec(valueCodec) Optional value, @UseCodec(nestedCodec) List<({String name, int count})> items});
final rows = entity<Row>();
''');
    final source = '${fixtures.path}/structured.dart';
    await writeGeneratedSchema(source);
    final analysis = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '${fixtures.path}/structured.orm.dart',
    ]);
    expect(
      analysis.exitCode,
      0,
      reason: '${analysis.stdout}\n${analysis.stderr}',
    );
    final result = await generateSchema(source);
    expect(result.dart, contains('models.Optional'));
    expect(result.dart, contains('models.valueCodec.nullable()'));
    final table = (result.snapshot['tables'] as List).single as Map;
    final columns = table['columns'] as List;
    expect((columns[1] as Map)['nullable'], true);
  });

  for (final (name, source, message) in <(String, String, String)>[
    (
      'wrong_codec',
      '''
const valueCodec = Codec<String>('text', decode, encode);
String decode(Object? value) => value as String;
String encode(String value) => value;
typedef Row = ({@UseCodec(valueCodec) int value});
final rows = entity<Row>();
''',
      'does not match',
    ),
    (
      'nullable_codec',
      '''
const valueCodec = Codec<int?>('integer', decode, encode);
int? decode(Object? value) => value as int?;
int? encode(int? value) => value;
typedef Row = ({@UseCodec(valueCodec) int value});
final rows = entity<Row>();
''',
      'does not match',
    ),
    (
      'erased_extension',
      '''
extension type const UserId(int value) {}
const valueCodec = Codec<int>('integer', decode, encode);
int decode(Object? value) => value as int;
int encode(int value) => value;
typedef Row = ({@UseCodec(valueCodec) UserId value});
final rows = entity<Row>();
''',
      'does not match',
    ),
    (
      'unknown_storage',
      '''
const valueCodec = Codec<int>('magic', decode, encode);
int decode(Object? value) => value as int;
int encode(int value) => value;
typedef Row = ({@UseCodec(valueCodec) int value});
final rows = entity<Row>();
''',
      'Unknown codec storage',
    ),
    (
      'private_codec',
      '''
const _valueCodec = Codec<int>('integer', decode, encode);
int decode(Object? value) => value as int;
int encode(int value) => value;
typedef Row = ({@UseCodec(_valueCodec) int value});
final rows = entity<Row>();
''',
      'public const codec',
    ),
    (
      'private_type',
      '''
class _Value { const _Value(); }
const valueCodec = Codec<_Value>('text', decode, encode);
_Value decode(Object? value) => const _Value();
String encode(_Value value) => '';
typedef Row = ({@UseCodec(valueCodec) _Value value});
final rows = entity<Row>();
''',
      'public symbols',
    ),
    (
      'inline_codec',
      '''
int decode(Object? value) => value as int;
int encode(int value) => value;
typedef Row = ({@UseCodec(Codec<int>('integer', decode, encode)) int value});
final rows = entity<Row>();
''',
      'public const codec',
    ),
    (
      'duplicate_codec',
      '''
const valueCodec = Codec<int>('integer', decode, encode);
int decode(Object? value) => value as int;
int encode(int value) => value;
typedef Row = ({@UseCodec(valueCodec) @UseCodec(valueCodec) int value});
final rows = entity<Row>();
''',
      'only appear once',
    ),
    (
      'missing_codec',
      '''
class Value {}
typedef Row = ({Value value});
final rows = entity<Row>();
''',
      'explicit @UseCodec',
    ),
    (
      'duplicate_labels',
      '''
enum Value { @EnumValue('same') a, @EnumValue('same') b }
typedef Row = ({Value value});
final rows = entity<Row>();
''',
      'Duplicate enum storage label',
    ),
    (
      'duplicate_enum_annotation',
      '''
enum Value { @EnumValue('one') @EnumValue('two') a }
typedef Row = ({Value value});
final rows = entity<Row>();
''',
      'EnumValue appears twice',
    ),
  ]) {
    test('invalid custom declaration: $name', () async {
      await expectLater(
        generate(name, source),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
    });
  }

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
