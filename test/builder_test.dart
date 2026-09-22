@Tags(['core'])
library;

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:orm/builder.dart';
import 'package:orm/generate.dart' show generateSchema;
import 'package:test/test.dart';

void main() {
  late TestReaderWriter files;
  setUp(() async {
    files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
    await files.testing.loadIsolateSources();
  });

  Future<TestBuilderResult> run(
    Map<String, String> inputs,
    Set<String> roots,
  ) => testBuilder(
    _OnlyRoots(roots),
    inputs,
    rootPackage: 'orm',
    readerWriter: files,
    generateFor: roots,
    flattenOutput: true,
  );

  test(
    'build assets and standalone CLI produce identical client and snapshot',
    () async {
      const root = 'test/support/codecs/schema.dart';
      final inputs = <String, String>{};
      for (final name in ['schema.dart', 'types.dart', 'alternate.dart']) {
        final path = 'test/support/codecs/$name';
        inputs['orm|$path'] = await File(path).readAsString();
      }
      final result = await run(inputs, {'orm|$root'});
      expect(result.succeeded, true, reason: result.errors.toString());
      final standalone = await generateSchema(root);
      expect(
        files.testing.readString(
          AssetId('orm', 'test/support/codecs/schema.orm.dart'),
        ),
        standalone.dart,
      );
      expect(
        files.testing.readString(
          AssetId('orm', 'test/support/codecs/schema.snapshot.dart'),
        ),
        standalone.snapshotDart,
      );
      expect(
        files.testing.resolverEntrypointsTracked,
        contains(AssetId('orm', root)),
      );
    },
  );

  test(
    'multiple explicit schema roots resolve shared public types under lib',
    () async {
      const types = '''
enum Status { pending, done }
''';
      final inputs = <String, String>{
        'orm|lib/fixture/types.dart': types,
        for (final name in ['one', 'two'])
          'orm|lib/fixture/$name.dart':
              '''
import 'package:orm/schema.dart';
import 'types.dart';
final row = model('$name', (id: integer(), status: enumeration(Status.values, labels: {Status.pending: 'waiting', Status.done: 'done'})), primaryKey: (r) => r.id);
''',
        'orm|lib/fixture/unrelated.dart': 'const unrelated = 1;',
      };
      final result = await run(inputs, {
        'orm|lib/fixture/one.dart',
        'orm|lib/fixture/two.dart',
      });
      expect(result.succeeded, true, reason: result.errors.toString());
      expect(result.outputs.length, 4);
      for (final name in ['one', 'two']) {
        final output = files.testing.readString(
          AssetId('orm', 'lib/fixture/$name.orm.dart'),
        );
        expect(output, contains('package:orm/fixture/types.dart'));
        expect(output, contains('"waiting"'));
      }
      expect(
        files.testing.resolverEntrypointsTracked,
        isNot(contains(AssetId('orm', 'lib/fixture/unrelated.dart'))),
      );
    },
  );

  test(
    'Record roots follow exported and referenced models through build assets',
    () async {
      final result = await run(
        {
          'orm|lib/fixture/schema.dart':
              "export 'employee.dart' show employee;",
          'orm|lib/fixture/employee.dart': '''
import 'package:orm/schema.dart';
import 'department.dart';
enum Role { member, manager }
final Model employee = model('employees', (
  id: identity(), role: enumeration(Role.values, defaultValue: Role.member),
  departmentId: integer(),
), relations: (e) => (department: references(e.departmentId, () => department),));
''',
          'orm|lib/fixture/department.dart': '''
import 'package:orm/schema.dart';
import 'employee.dart';
final department = model('departments', (id: identity(), name: text()), relations: (d) => (employees: referencedBy(() => employee),));
final unused = model('unused', (bad: 'not a column',));
''',
        },
        {'orm|lib/fixture/schema.dart'},
      );
      expect(result.succeeded, true, reason: result.errors.toString());
      final generated = files.testing.readString(
        AssetId('orm', 'lib/fixture/schema.orm.dart'),
      );
      expect(generated, contains('final class Employee('));
      expect(generated, contains('final class Department('));
      expect(generated, isNot(contains('final class Unused(')));
      expect(generated, contains('package:orm/fixture/employee.dart'));
    },
  );

  for (final (name, body) in [
    (
      'semantic_error',
      'final row = model("rows", (id: identity(),)); int bad = "wrong";',
    ),
    (
      'enum_labels',
      "enum Status { a, b } final row = model('rows', (status: enumeration(Status.values, labels: {Status.a: 'x', Status.b: 'x'}),));",
    ),
    ('no_models', 'const empty = 1;'),
    ('part_file', "part of 'root.dart';"),
  ]) {
    test('invalid $name never publishes partial outputs', () async {
      final path = 'lib/fixture/$name.dart';
      final result = await run(
        {
          'orm|$path':
              "${name == 'part_file' ? '' : "import 'package:orm/schema.dart';"}\n$body",
        },
        {'orm|$path'},
      );
      expect(result.succeeded, false);
      expect(result.errors, isNotEmpty);
      expect(result.outputs, isEmpty);
    });
  }

  test('unknown options fail instead of silently changing build behavior', () {
    expect(
      () => ormBuilder(BuilderOptions({'unknown': true})),
      throwsArgumentError,
    );
  });

  test('schema resolution can consume an earlier builder output', () async {
    final result = await testBuilders(
      [
        _DomainBuilder(),
        _OnlyRoots({'orm|lib/fixture/schema.dart'}),
      ],
      {
        'orm|lib/fixture/models.domain':
            "const readyLabel = 'generated'; enum Status { ready }",
        'orm|lib/fixture/schema.dart': "import 'package:orm/schema.dart'; import 'models.dart'; final row = model('rows', (status: enumeration(Status.values, labels: {Status.ready: readyLabel}),));",
      },
      rootPackage: 'orm',
      readerWriter: files,
      flattenOutput: true,
    );
    expect(result.succeeded, true, reason: result.errors.toString());
    expect(
      files.testing.readString(AssetId('orm', 'lib/fixture/schema.orm.dart')),
      contains('"generated"'),
    );
  });
}

final class _DomainBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    '.domain': ['.dart'],
  };
  @override
  Future<void> build(BuildStep step) => step.writeAsString(
    step.inputId.changeExtension('.dart'),
    step.readAsString(step.inputId),
  );
}

// build_test's default source set also includes every loaded root-package lib
// asset. Apply the explicit root filter here; the process test covers build.yaml.
final class _OnlyRoots(final Set<String> roots) implements Builder {
  final Builder delegate = ormBuilder(BuilderOptions.empty);
  @override
  Map<String, List<String>> get buildExtensions => delegate.buildExtensions;
  @override
  Future<void> build(BuildStep step) async {
    if (roots.contains(step.inputId.toString())) await delegate.build(step);
  }
}
