@Tags(['core'])
library;

import 'dart:io';

import 'package:orm/generate.dart';
import 'package:test/test.dart';

void main() {
  late Directory fixtures;
  setUpAll(() async {
    fixtures = await Directory('.dart_tool').createTemp('mixin-generation-');
  });
  tearDownAll(() => fixtures.delete(recursive: true));

  Future<File> source(String name, String contents) async {
    final file = File('${fixtures.path}/$name.dart');
    await file.parent.create(recursive: true);
    await file.writeAsString("import 'package:orm/schema.dart';\n$contents");
    return file;
  }

  test(
    'imported mixin storage and metadata are reused by independent DTOs',
    () async {
      await source('shared', '''
String nextLabel() => 'client';
mixin Shared {
  @Id(generated: true) int id = 0;
  @Column(name: 'shared_label') @ClientDefault(nextLabel) String label = '';
  @Ignore() final String local = 'local';
  String describe() => '\$id: \$label';
}
''');
      final file = await source('models', '''
import 'shared.dart';
@Model() class User with Shared {
  final String name;
  User({required int id, required this.name, String label = 'constructor'}) {
    this.id = id;
    this.label = label;
  }
}
@Model() class Team with Shared {
  Team({required int id, required String label}) {
    this.id = id;
    this.label = label;
  }
}
''');
      final generated = await generateSchema(file.path, dialect: .postgres);
      for (final table in generated.snapshot.tables) {
        expect(table.primaryKey, ['id']);
        expect(
          table.columns.singleWhere((c) => c.name == 'id').generated,
          true,
        );
        expect(table.columns.any((c) => c.name == 'shared_label'), true);
        expect(table.columns.any((c) => c.name == 'local'), false);
      }
      expect(generated.dart, contains('clientDefault: types0.nextLabel'));
      expect(generated.dart, isNot(contains('class User {')));
      expect(generated.dart, isNot(contains('class Team {')));
      expect(generated.snapshotDart, isNot(contains('shared.dart')));
    },
  );

  test(
    'mixin relation fields discover otherwise unexported target models',
    () async {
      await source('relations', '''
@Model() final class Owner({@Id() required final int id});
mixin Owned {
  @Relation(target: Owner, name: 'owner', inverse: 'items') int ownerId = 0;
}
''');
      final file = await source('item', '''
import 'relations.dart';
@Model() class Item with Owned {
  final int id;
  Item({@Id() required this.id, required int ownerId}) { this.ownerId = ownerId; }
}
''');
      final generated = await generateSchema(file.path);
      expect(generated.snapshot.tables.map((table) => table.name), [
        'Item',
        'Owner',
      ]);
      expect(generated.dart, contains('get owner =>'));
      expect(generated.dart, contains('get items =>'));
    },
  );

  test(
    'business-only mixins leave ordinary field construction unchanged',
    () async {
      final file = await source('business', '''
mixin Business {
  @Ignore() final DateTime loadedAt = DateTime.now();
  String businessMethod() => 'business';
}
@Model() final class User({@Id() required final int id}) with Business;
''');
      final generated = await generateSchema(file.path);
      expect(generated.snapshot.tables.single.columns.map((c) => c.name), [
        'id',
      ]);
    },
  );

  test(
    'mixin-owning libraries follow the independent-library boundary',
    () async {
      await source('parts/shared', '''
part 'helper.dart';
mixin Shared { int id = 0; }
''');
      await File('${fixtures.path}/parts/helper.dart')
          .writeAsString("part of 'shared.dart';\n");
      final file = await source('parts/model', '''
import 'shared.dart';
@Model() class User with Shared {
  User({required int id}) { this.id = id; }
}
''');
      await expectLater(
        generateSchema(file.path),
        throwsA(
          isA<GenerationException>().having(
            (e) => e.code,
            'code',
            'SCHEMA.LIBRARY',
          ),
        ),
      );
    },
  );

  for (final (name, declaration, message) in _invalid) {
    test('rejects $name without emitting artifacts', () async {
      final file = await source(name, declaration);
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
      expect(File('${fixtures.path}/$name.orm.dart').existsSync(), false);
      expect(File('${fixtures.path}/$name.snapshot.dart').existsSync(), false);
    });
  }
}

const _invalid = <(String, String, String)>[
  (
    'missing_assignment',
    '''
mixin Fields { int id = 0; }
@Model() class User with Fields { User({required int id}); }
''',
    'Persistent parameters must directly',
  ),
  (
    'missing_parameter',
    '''
mixin Fields { int id = 0; int value = 0; }
@Model() class User with Fields { User({required int id}) { this.id = id; } }
''',
    'Instance field value is not supplied',
  ),
  (
    'transformation',
    '''
mixin Fields { int id = 0; }
@Model() class User with Fields { User({required int id}) { this.id = id + 1; } }
''',
    'must directly store mixin parameters',
  ),
  (
    'duplicate_assignment',
    '''
mixin Fields { int id = 0; }
@Model() class User with Fields { User({required int id}) { this.id = id; this.id = id; } }
''',
    'must directly store mixin parameters',
  ),
  (
    'extra_statement',
    '''
mixin Fields { int id = 0; }
@Model() class User with Fields { User({required int id}) { this.id = id; print(id); } }
''',
    'must directly store mixin parameters',
  ),
  (
    'wrong_nullability',
    '''
mixin Fields { int? id; }
@Model() class User with Fields { User({required int id}) { this.id = id; } }
''',
    'Constructor and stored field types must match',
  ),
  (
    'own_field_conflict',
    '''
mixin Fields { int id = 0; }
@Model() class User with Fields { @override final int id; User({required this.id}); }
''',
    'conflicts with another instance field or accessor',
  ),
  (
    'mixin_field_conflict',
    '''
mixin A { int id = 0; }
mixin B { int id = 1; }
@Model() class User with A, B { User({required int id}) { this.id = id; } }
''',
    'conflicts with another instance field or accessor',
  ),
  (
    'getter_conflict',
    '''
mixin Fields { int id = 0; }
@Model() class User with Fields {
  @override int get id => super.id + 1;
  User({required int id}) { this.id = id; }
}
''',
    'conflicts with another instance field or accessor',
  ),
  (
    'late_storage',
    '''
mixin Fields { late int id; }
@Model() class User with Fields { User({required int id}) { this.id = id; } }
''',
    'mutable, non-late storage',
  ),
  (
    'final_storage',
    '''
mixin Fields { final int value = 1; }
@Model() class User with Fields { final int id; User({required this.id}); }
''',
    'mutable, non-late storage',
  ),
  (
    'initializer_effect',
    '''
int effect() => throw StateError('must not execute');
mixin Fields { int id = effect(); }
@Model() class User with Fields { User({required int id}) { this.id = id; } }
''',
    'constant initializer',
  ),
  (
    'generic_mixin',
    '''
mixin Fields<T> { int id = 0; }
@Model() class User with Fields<int> { User({required int id}) { this.id = id; } }
''',
    'nongeneric',
  ),
  (
    'constrained_mixin',
    '''
mixin Fields { int id = 0; }
mixin Business on Fields { String describe() => '\$id'; }
@Model() class User with Fields, Business { User({required int id}) { this.id = id; } }
''',
    'only Object',
  ),
  (
    'mixin_class',
    '''
mixin class Fields { int id = 0; }
@Model() class User with Fields { User({required int id}) { this.id = id; } }
''',
    'plain mixin declaration',
  ),
  (
    'superclass_storage',
    '''
class Base { int id = 0; }
@Model() class User extends Base { User({required int id}) { this.id = id; } }
''',
    'directly extend Object',
  ),
  (
    'duplicate_metadata',
    '''
mixin Fields { @Id() int id = 0; }
@Model() class User with Fields { User({@Id() required int id}) { this.id = id; } }
''',
    'more than once',
  ),
  (
    'ignored_metadata_conflict',
    '''
mixin Fields { @Ignore() @Column(name: 'hidden') final String hidden = ''; }
@Model() final class User({@Id() required final int id}) with Fields;
''',
    '@Ignore cannot be combined',
  ),
];
