@Tags(['core'])
library;

import 'package:orm/values.dart';

import 'dart:io';

import 'package:orm/generate.dart';
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
@Model(table: 'items')
@Check('id > 0', name: 'positive', postgres: '')
final class Item({required final int id,
  @Unique() @Computed('id + 1', storage: .virtual, postgres: '') required final int value});
''');
      expect(sqlite.snapshot.forDialect(.sqlite).tables, hasLength(1));
      expect(
        () => sqlite.snapshot.forDialect(.postgres),
        throwsA(isA<OrmException>()),
      );
      final postgres = await generate('postgres_computed_pk', '''
@Model(table: 'items')
@Check('source > 0', name: 'valid') @Check('source < 10', name: 'VALID')
final class Item({required final int source,
  @Id() @Computed('source + 1') required final int id});
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
        "import 'package:orm/schema.dart';\n@Model(table: 'rows') final class Row({required final int id});\n";
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
      expect(result.dart, isNot(contains('final class User(')));
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
String? defaultLabel() => null;
String defaultState() => 'client';
@Model(table: 'items')
final class Item({
  @Id(generated: true) required final int id,
  @ClientDefault(defaultLabel) required final String? label,
  @ClientDefault(defaultState) @DatabaseDefault.sql("'server'") required final String state,
});
''');
      expect(generated.dart, contains('clientDefault: models.defaultLabel'));
      expect(generated.dart, contains('clientDefault: models.defaultState'));
      expect(
        generated.snapshot.tables.single.columns.last.defaultSql,
        "'server'",
      );
      expect(generated.snapshotDart, isNot(contains('clientDefault')));
    },
  );

  final invalid = <String, String>{
    for (final name in [
      'Raw',
      'Query',
      'StreamSql',
      'WatchSql',
      'Close',
      'Switch',
    ])
      'reserved_$name': "@Model() final class $name({required final int id});",
    'private': '@Model() final class _Item({required final int id});',
    'symbol': '@Model() final class App({required final int id});',
    'duplicate_column': '@Model() final class Item({required final int iD, required final int i_d});',
    'computed_identity': "@Model() final class Item({@Id(generated:true) @Computed('1') required final int id});",
    'computed_sql_default': "@Model() final class Item({@DatabaseDefault(1) @Computed('1') required final int id});",
    'computed_client_default': "int value()=>1; @Model() final class Item({@ClientDefault(value) @Computed('1') required final int id});",
    'computed_empty':
        "@Model() final class Item({@Computed('') required final int id});",
    'wrong_factory': "String value()=>'one'; @Model() final class Item({@ClientDefault(value) required final int id});",
    'async_factory': "Future<int> value() async=>1; @Model() final class Item({@ClientDefault(value) required final int id});",
    'private_factory': "int _value()=>1; @Model() final class Item({@ClientDefault(_value) required final int id});",
    'required_factory': "int value(int a)=>a; @Model() final class Item({@ClientDefault(value) required final int id});",
    'factory_closure': '@Model() final class Item({@ClientDefault(() => 1) required final int id});',
    'duplicate_factory': 'int value()=>1; @Model() final class Item({@ClientDefault(value) @ClientDefault(value) required final int id});',
    'dynamic_check': "String sql()=>'id>0'; @Model() @Check(sql()) final class Item({required final int id});",
    'empty_check':
        "@Model() @Check('') final class Item({required final int id});",
    'duplicate_check': "@Model() @Check('id>0', name:'valid') @Check('id<10', name:'valid') final class Item({required final int id});",
    'wrong_default': "@Model() final class Item({@DatabaseDefault('one') required final int id});",
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
