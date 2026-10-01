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
    'build assets and standalone produce identical client and snapshot',
    () async {
      const root = 'example/annotated/models.dart';
      final result = await run(
        {'orm|$root': await File(root).readAsString()},
        {'orm|$root'},
      );
      expect(result.succeeded, true, reason: result.errors.toString());
      final standalone = await generateSchema(root);
      expect(
        files.testing.readString(
          AssetId('orm', 'example/annotated/models.orm.dart'),
        ),
        standalone.dart,
      );
      expect(
        files.testing.readString(
          AssetId('orm', 'example/annotated/models.snapshot.dart'),
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
    'multiple explicit model roots resolve shared public types under lib',
    () async {
      final inputs = <String, String>{
        'orm|lib/fixture/types.dart': 'enum Status { pending, done }',
        for (final name in ['one', 'two'])
          'orm|lib/fixture/$name.dart':
              '''
import 'package:orm/schema.dart';
import 'types.dart';
@Model(table: '$name')
class Row {
  @Id() final int id;
  final Status status;
  const Row({required this.id, required this.status});
}
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
        expect(output, contains('"pending"'));
      }
      expect(
        files.testing.resolverEntrypointsTracked,
        isNot(contains(AssetId('orm', 'lib/fixture/unrelated.dart'))),
      );
    },
  );

  test(
    'model roots follow exports and relations through build assets',
    () async {
      final result = await run(
        {
          'orm|lib/fixture/schema.dart':
              "export 'employee.dart' show Employee;",
          'orm|lib/fixture/employee.dart': '''
import 'package:orm/schema.dart';
import 'department.dart';
enum Role { member, manager }
@Model(table: 'employees')
class Employee {
  @Id(generated: true) final int id;
  final Role role;
  @Relation(target: Department, name: 'department', inverse: 'employees')
  final int departmentId;
  const Employee({required this.id, required this.role, required this.departmentId});
}
''',
          'orm|lib/fixture/department.dart': '''
import 'package:orm/schema.dart';
@Model(table: 'departments')
class Department {
  @Id(generated: true) final int id;
  final String name;
  const Department({required this.id, required this.name});
}
@Model()
class Unused { final Object bad; const Unused({required this.bad}); }
''',
        },
        {'orm|lib/fixture/schema.dart'},
      );
      expect(result.succeeded, true, reason: result.errors.toString());
      final generated = files.testing.readString(
        AssetId('orm', 'lib/fixture/schema.orm.dart'),
      );
      expect(
        generated,
        contains(RegExp(r'Table<\w+\.Employee, EmployeeFields>')),
      );
      expect(generated, contains('DepartmentFields>'));
      expect(generated, isNot(contains('Unused')));
      expect(generated, contains('package:orm/fixture/employee.dart'));
    },
  );

  for (final (name, body) in [
    (
      'semantic_error',
      '@Model() class Row { final int id; const Row({required this.id}); } int bad = "wrong";',
    ),
    (
      'unknown_reference',
      "@Model() @Unique(['missing']) class Row { final int id; const Row({required this.id}); }",
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

  test('model resolution can consume an earlier builder output', () async {
    final result = await testBuilders(
      [
        _DomainBuilder(),
        _OnlyRoots({'orm|lib/fixture/schema.dart'}),
      ],
      {
        'orm|lib/fixture/models.domain': "const readyLabel = 'generated';",
        'orm|lib/fixture/schema.dart': '''
import 'package:orm/schema.dart';
import 'models.dart';
@Model(table: 'rows')
class Row {
  @DatabaseDefault(readyLabel) final String status;
  const Row({required this.status});
}
''',
      },
      rootPackage: 'orm',
      readerWriter: files,
      flattenOutput: true,
    );
    expect(result.succeeded, true, reason: result.errors.toString());
    expect(
      files.testing.readString(AssetId('orm', 'lib/fixture/schema.orm.dart')),
      contains("'generated'"),
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

// build_test's default source set includes every loaded root-package lib asset.
final class _OnlyRoots(final Set<String> roots) implements Builder {
  final Builder delegate = ormBuilder(BuilderOptions.empty);
  @override
  Map<String, List<String>> get buildExtensions => delegate.buildExtensions;
  @override
  Future<void> build(BuildStep step) async {
    if (roots.contains(step.inputId.toString())) await delegate.build(step);
  }
}
