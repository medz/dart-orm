import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
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

  test(
    'target capabilities are checked when choosing a migration engine',
    () async {
      final sqlite = await generate('sqlite_virtual_index', '''
typedef Item = ({int id, @Unique() @Computed.sql('id + 1', storage: ComputedStorage.virtual, postgres: '') int value});
final items = entity<Item>();
final positive = items.check('id > 0', postgres: '');
''');
      expect(sqlite.snapshot.forDialect(.sqlite).tables, hasLength(1));
      expect(
        () => sqlite.snapshot.forDialect(.postgres),
        throwsA(isA<OrmException>()),
      );
      final postgres = await generate('postgres_computed_pk', '''
typedef Item = ({int source, @Id() @Computed.sql('source + 1') int id});
final items = entity<Item>();
final lower = items.check('source > 0', name: 'valid');
final upper = items.check('source < 10', name: 'VALID');
''');
      expect(postgres.snapshot.forDialect(.postgres).tables, hasLength(1));
      expect(
        () => postgres.snapshot.forDialect(.sqlite),
        throwsA(isA<OrmException>()),
      );
    },
  );

  test('unusable extension getters and generated symbol collisions fail at generation', () async {
    for (final source in [
      'typedef Item = ({int id}); final close = entity<Item>();',
      'typedef Item = ({int id}); final _items = entity<Item>();',
      'typedef Item = ({int id}); final app = entity<Item>();',
      "typedef Item = ({int id}); final items = entity<Item>(); final Items = entity<Item>(table: 'others');",
      'typedef Item = ({int iD, int ID}); final items = entity<Item>();',
    ]) {
      await expectLater(
        generate('collision', source),
        throwsA(isA<GenerationException>()),
      );
    }
  });

  test('client and snapshot paths cannot overwrite the declaration', () async {
    const declaration =
        "import 'package:orm/schema.dart';\ntypedef Row = ({int id});\nfinal rows = entity<Row>();\n";
    for (final (name, outputName) in [
      ('same.dart', 'same.dart'),
      ('overlap.snapshot.dart', 'overlap.dart'),
    ]) {
      final source = File('${fixtures.path}/$name');
      final output = File('${fixtures.path}/$outputName');
      await source.writeAsString(declaration);
      await expectLater(
        writeGeneratedSchema(source.path, output: output.path),
        throwsA(isA<GenerationException>()),
      );
      expect(await source.readAsString(), declaration);
      if (name != outputName) expect(await output.exists(), false);
    }
  });

  test('record annotations, physical names, relations and snapshots', () async {
    final result = await generateSchema('example/schema.dart');
    expect(result.dart, contains('Future<models.User> create('));
    expect(result.dart, contains('Change<int> score'));
    expect(
      result.dart,
      contains('Relation<models.Post, PostsFields> get posts'),
    );
    final tables = result.snapshot.toJson()['tables'] as List<Object?>;
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
        'example/teams/schema.dart',
        'test/support/relations/schema.dart',
        'test/support/codecs/schema.dart',
        'test/support/integers/schema.dart',
        'test/support/decimals/schema.dart',
        'test/support/precision/schema.dart',
        'test/support/temporals/schema.dart',
        'test/support/instants/schema.dart',
        'test/support/unconstrained/schema.dart',
        'test/support/checks/schema.dart',
        'test/support/defaults/schema.dart',
        'test/support/computed/schema.dart',
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
          result.snapshotDart,
          await File('$base.snapshot.dart').readAsString(),
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

  test('computed declarations reject conflicting defaults, empty SQL and invalid row identities', () async {
    final cases = [
      "typedef Item = ({int id, @Computed.sql('') int value});",
      "typedef Item = ({int id, @Computed.sql('1') @Default.sql('0') int value});",
      "int factory() => 1; typedef Item = ({int id, @Computed.sql('1') @ClientDefault(factory) int value});",
      "typedef Item = ({@Id.generated() @Computed.sql('1') int id, int value});",
      "typedef Item = ({@Computed.sql('1') int value});",
      "typedef Item = ({int id, @Computed.sql('1') @Computed.sql('2') int value});",
      "typedef Item = ({int id, int readColumn});",
    ];
    for (var i = 0; i < cases.length; i++) {
      await expectLater(
        generate(
          'computed_invalid_$i',
          '${cases[i]}\nfinal items = entity<Item>();',
        ),
        throwsA(isA<GenerationException>()),
        reason: cases[i],
      );
    }
  });

  test('client defaults reject incompatible, asynchronous, private and ambiguous factories', () async {
    for (final (name, declaration) in [
      (
        'erased_domain',
        '''
extension type const UserId(int value) {}
const idCodec = Codec<UserId>('integer', decodeId, encodeId);
UserId decodeId(Object? raw) => UserId(raw as int);
Object? encodeId(UserId id) => id.value;
int factory() => 1;
typedef Item = ({@UseCodec(idCodec) @ClientDefault(factory) UserId id});
''',
      ),
      (
        'return_type',
        'int factory() => 1; typedef Item = ({@ClientDefault(factory) String value});',
      ),
      (
        'async',
        "Future<String> factory() async => 'x'; typedef Item = ({@ClientDefault(factory) String value});",
      ),
      (
        'nullable',
        'String? factory() => null; typedef Item = ({@ClientDefault(factory) String value});',
      ),
      (
        'dynamic',
        "dynamic factory() => 'x'; typedef Item = ({@ClientDefault(factory) String value});",
      ),
      (
        'arguments',
        'String factory(String value) => value; typedef Item = ({@ClientDefault(factory) String value});',
      ),
      (
        'private',
        "String _factory() => 'x'; typedef Item = ({@ClientDefault(_factory) String value});",
      ),
      (
        'private_owner',
        "class _Defaults { static String make() => 'x'; } typedef Item = ({@ClientDefault(_Defaults.make) String value});",
      ),
      (
        'duplicate',
        "String factory() => 'x'; typedef Item = ({@ClientDefault(factory) @ClientDefault(factory) String value});",
      ),
      (
        'variable',
        "String make() => 'x'; final factory = make; typedef Item = ({@ClientDefault(factory) String value});",
      ),
    ]) {
      await expectLater(
        generate(
          'client_default_$name',
          '$declaration\nfinal items = entity<Item>();',
        ),
        throwsA(isA<GenerationException>()),
      );
    }
  });

  test(
    'CHECK declarations reject dynamic SQL, empty SQL and duplicate names',
    () async {
      for (final (name, declaration) in [
        (
          'dynamic_check',
          "final sql = 'id > 0'; final valid = items.check(sql);",
        ),
        ('empty_check', "final valid = items.check(' ');"),
        (
          'duplicate_check',
          "final one = items.check('id > 0', name: 'valid'); final two = items.check('id < 10', name: 'valid');",
        ),
        ('empty_check_name', "final valid = items.check('id > 0', name: '');"),
      ]) {
        await expectLater(
          generate(name, '''
typedef Item = ({@Id() int id});
final items = entity<Item>();
$declaration
'''),
          throwsA(isA<GenerationException>()),
        );
      }
    },
  );

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
    final table = (result.snapshot.toJson()['tables'] as List).single as Map;
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

  test('query-only edges do not alter physical snapshots or require unique targets', () async {
    const source = '''
typedef User = ({@Id() int id, @ColumnName('lookup_name') String label});
typedef Event = ({@Id() int id, String label});
final users = entity<User>();
final events = entity<Event>();
''';
    final before = await generate('without_navigation', source);
    final after = await generate('with_navigation', '''
$source
final matchingUsers = events.key((e) => e.label).relatesTo(users.key((u) => u.label), inverse: 'events');
''');
    expect(after.snapshot.toJson(), before.snapshot.toJson());
    expect(after.dart, contains('get matchingUsers'));
    expect(after.dart, contains('get events'));
    expect(
      after.dart,
      contains('Read-only navigation; no database foreign key'),
    );
    expect(after.dart, isNot(contains('ForeignKey(')));
  });

  test(
    'constrained and unconstrained edges retain separate migration meaning',
    () async {
      final result = await generate('mixed_navigation', '''
typedef User = ({@Id() int id});
typedef Event = ({@Id() int id, int owner, int lookup});
final users = entity<User>();
final events = entity<Event>();
final ownerAccount = events.key((e) => e.owner).references(users.key((u) => u.id));
final lookupAccount = events.key((e) => e.lookup).relatesTo(users.key((u) => u.id));
''');
      final table = (result.snapshot.toJson()['tables'] as List).last as Map;
      expect(table['foreignKeys'], [
        {
          'columns': ['owner'],
          'target': 'users',
          'targetColumns': ['id'],
          'onDelete': 'RESTRICT',
        },
      ]);
      expect(result.dart, contains('get ownerAccount'));
      expect(result.dart, contains('get lookupAccount'));
    },
  );

  for (final (name, source, expected) in [
    (
      'lookup_computed',
      '''
typedef Row = ({@Id() int id});
final rows = entity<Row>();
final peers = rows.key((r) => r.id + 1).relatesTo(rows.key((r) => r.id));
''',
      'direct fields',
    ),
    (
      'lookup_codec',
      '''
int decode(Object? raw) => int.parse(raw as String);
String encode(int value) => value.toString();
const textInt = Codec<int>('text', decode, encode);
typedef Row = ({@Id() int id, @UseCodec(textInt) int label});
final rows = entity<Row>();
final peers = rows.key((r) => r.id).relatesTo(rows.key((r) => r.label));
''',
      'Relationship storage types differ',
    ),
    (
      'lookup_inverse',
      '''
typedef Row = ({@Id() int id});
final rows = entity<Row>();
final peers = rows.key((r) => r.id).relatesTo(rows.key((r) => r.id), inverse: 'id');
''',
      'relationship name',
    ),
    (
      'lookup_type',
      '''
typedef Row = ({@Id() int id, String label});
final rows = entity<Row>();
final peers = rows.key((r) => r.id).relatesTo(rows.key((r) => r.label));
''',
      "isn't returnable",
    ),
    (
      'lookup_delete',
      '''
typedef Row = ({@Id() int id});
final rows = entity<Row>();
final peers = rows.key((r) => r.id).relatesTo(rows.key((r) => r.id), onDelete: ReferentialAction.cascade);
''',
      'onDelete',
    ),
  ]) {
    test('invalid query-only relation: $name', () async {
      await expectLater(
        generate(name, source),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.message,
            'message',
            contains(expected),
          ),
        ),
      );
    });
  }

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
