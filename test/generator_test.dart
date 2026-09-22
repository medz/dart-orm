@Tags(['core'])
library;

import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:test/test.dart';

void main() {
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory('.dart_tool').createTemp('schema-generation-');
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
final item = model('items', (
  id: integer(),
  value: integer(unique: true).computed('id + 1', storage: .virtual, postgres: ''),
), checks: [check('id > 0', name: 'positive', postgres: '')]);
''');
      expect(sqlite.snapshot.forDialect(.sqlite).tables, hasLength(1));
      expect(
        () => sqlite.snapshot.forDialect(.postgres),
        throwsA(isA<OrmException>()),
      );
      final postgres = await generate('postgres_computed_pk', '''
final item = model('items', (source: integer(), id: integer().computed('source + 1')),
  primaryKey: (i) => i.id,
  checks: [check('source > 0', name: 'valid'), check('source < 10', name: 'VALID')]);
''');
      expect(postgres.snapshot.forDialect(.postgres).tables, hasLength(1));
      expect(
        () => postgres.snapshot.forDialect(.sqlite),
        throwsA(isA<OrmException>()),
      );
    },
  );

  test('client and snapshot paths cannot overwrite the declaration', () async {
    const declaration =
        "import 'package:orm/schema.dart';\nfinal row = model('rows', (id: integer(),));\n";
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

  test('output is deterministic for all executable schemas', () async {
    final sources = [
      'example/schema.dart',
      'example/teams/schema.dart',
      'example/company/schema.dart',
      for (final directory in Directory(
        'test/support',
      ).listSync().whereType<Directory>())
        if (File('${directory.path}/schema.dart').existsSync())
          '${directory.path}/schema.dart',
    ];
    for (final source in sources) {
      final result = await generateSchema(source);
      expect(
        result.dart,
        await File(source.replaceAll('.dart', '.orm.dart')).readAsString(),
        reason: source,
      );
      expect(
        result.snapshotDart,
        await File(source.replaceAll('.dart', '.snapshot.dart')).readAsString(),
        reason: source,
      );
      expect(result.dart, isNot(contains('export "schema.dart" show User')));
    }
  });

  test(
    'custom types resolve their defining libraries when output moves',
    () async {
      final output = '${fixtures.path}/moved.dart';
      await writeGeneratedSchema(
        'test/support/codecs/schema.dart',
        output: output,
      );
      final analyzed = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        output,
      ]);
      expect(
        analyzed.exitCode,
        0,
        reason: '${analyzed.stdout}\n${analyzed.stderr}',
      );
    },
  );

  test(
    'SQL and nullable client defaults preserve independent insert ownership',
    () async {
      final generated = await generate('defaults', '''
String? label() => null;
String state() => 'client';
final item = model('items', (
  id: identity(),
  label: text().nullable(clientDefault: label),
  state: text(defaultSql: "'server'", clientDefault: state),
));
''');
      expect(generated.dart, contains('clientDefault: models.label'));
      expect(generated.dart, contains('clientDefault: models.state'));
      expect(
        generated.snapshot.tables.single.columns.last.defaultSql,
        "'server'",
      );
      expect(generated.snapshotDart, isNot(contains('clientDefault')));
    },
  );

  final invalid = <String, String>{
    'reserved_root': "final close = model('items', (id: integer(),));",
    'private_root': "final _item = model('items', (id: integer(),));",
    'schema_symbol': "final app = model('items', (id: integer(),));",
    'row_collision': "final item = model('items', (id: integer(),)); final Item = model('others', (id: integer(),));",
    'column_symbol_collision':
        "final item = model('items', (iD: integer(), i_d: integer()));",
    'selector_expression': "final item = model('items', (id: integer(),), primaryKey: (i) => (i.id, 1));",
    'computed_identity':
        "final item = model('items', (id: identity().computed('1'),));",
    'computed_sql_default': "final item = model('items', (id: integer(defaultValue: 1).computed('1'),));",
    'computed_client_default': "int value() => 1; final item = model('items', (id: integer(clientDefault: value).computed('1'),));",
    'computed_empty':
        "final item = model('items', (id: integer().computed(''),));",
    'wrong_factory': "String value() => 'one'; final item = model('items', (id: integer(clientDefault: value),));",
    'async_factory': "Future<int> value() async => 1; final item = model('items', (id: integer(clientDefault: value),));",
    'private_factory': "int _value() => 1; final item = model('items', (id: integer(clientDefault: _value),));",
    'required_factory': "int value(int input) => input; final item = model('items', (id: integer(clientDefault: value),));",
    'factory_closure':
        "final item = model('items', (id: integer(clientDefault: () => 1),));",
    'duplicate_factory': "String value() => 'a'; final item = model('items', (name: text(clientDefault: value).nullable(clientDefault: value),));",
    'dynamic_check': "String sql() => 'id > 0'; final item = model('items', (id: integer(),), checks: [check(sql(), name: 'valid')]);",
    'empty_check': "final item = model('items', (id: integer(),), checks: [check('', name: 'valid')]);",
    'duplicate_check': "final item = model('items', (id: integer(),), checks: [check('id > 0', name: 'valid'), check('id < 10', name: 'valid')]);",
    'private_codec': "int decode(Object? v) => v as int; Object? encode(int v) => v; const _codec = Codec<int>.integer(decode, encode); final item = model('items', (id: custom(_codec),));",
    'unknown_codec': "int decode(Object? v) => v as int; Object? encode(int v) => v; const codec = Codec<int>('unknown', decode, encode); final item = model('items', (id: custom(codec),));",
    'dart_type_error':
        "final item = model('items', (id: integer(defaultValue: 'one'),));",
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}', () async {
      await expectLater(
        generate(entry.key, entry.value),
        throwsA(isA<GenerationException>()),
      );
    });
  }
}
