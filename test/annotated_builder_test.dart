@Tags(['core'])
library;

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:orm/builder.dart';
import 'package:orm/generate.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  test('builder options reject wrong annotation option types', () {
    for (final options in [
      {'default_namespace': 1},
      {'database': 'postgres', 'models': 1},
      {'database': false},
    ]) {
      expect(() => ormBuilder(BuilderOptions(options)), throwsArgumentError);
    }
  });

  test(
    'individual build assets detect DTOs and preserve standalone parity',
    () async {
      const root = 'example/annotated/models.dart';
      final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
      await files.testing.loadIsolateSources();
      final result = await testBuilder(
        _OnlyRoot('orm|$root', {
          'database': 'postgres',
          'default_namespace': 'app',
        }),
        {'orm|$root': await File(root).readAsString()},
        rootPackage: 'orm',
        readerWriter: files,
        generateFor: {'orm|$root'},
        flattenOutput: true,
      );
      expect(result.succeeded, true, reason: result.errors.toString());
      final standalone = await generateSchema(
        root,
        dialect: .postgres,
        defaultNamespace: 'app',
      );
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
    },
  );

  test(
    'builder resolves imported optional mixin storage and metadata',
    () async {
      const root = 'lib/fixture/mixin_model.dart';
      final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
      await files.testing.loadIsolateSources();
      final result = await testBuilder(
        _OnlyRoot('orm|$root', {'database': 'postgres'}),
        {
          'orm|$root': '''
import 'package:orm/schema.dart';
import 'shared.dart';
@Model() class User with Shared {
  final String name;
  User({required int id, required this.name, bool active = false}) {
    this.id = id;
    this.active = active;
  }
}
''',
          'orm|lib/fixture/shared.dart': '''
import 'package:orm/schema.dart';
mixin Shared {
  @Id(generated: true) int id = 0;
  @DatabaseDefault(true) bool active = false;
  String describe() => '\$id: \$active';
}
''',
        },
        rootPackage: 'orm',
        readerWriter: files,
        generateFor: {'orm|$root'},
        flattenOutput: true,
      );
      expect(result.succeeded, true, reason: result.errors.toString());
      final client = files.testing.readString(
        AssetId('orm', 'lib/fixture/mixin_model.orm.dart'),
      );
      final snapshot = files.testing.readString(
        AssetId('orm', 'lib/fixture/mixin_model.snapshot.dart'),
      );
      expect(client, contains('models.User(id: v0, name: v1, active: v2)'));
      expect(snapshot, contains('generated: true'));
      expect(snapshot, contains('defaultSql: "true"'));
    },
  );

  test('model directory assets recursively discover source files without PG path namespaces', () async {
    final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
    await files.testing.loadIsolateSources();
    final result = await testBuilder(
      ormBuilder(
        BuilderOptions({
          'models': 'lib/fixture/models',
          'database': 'postgres',
          'default_namespace': 'app',
        }),
      ),
      {
        'orm|lib/fixture/models/direct.dart': _user,
        'orm|lib/fixture/models/features/audit/nested.dart': _audit,
        'orm|lib/fixture/models/features/old.orm.dart':
            'invalid generated content',
        'orm|lib/fixture/models/features/old.snapshot.dart':
            'invalid generated content',
      },
      rootPackage: 'orm',
      readerWriter: files,
      flattenOutput: true,
    );
    expect(result.succeeded, true, reason: result.errors.toString());
    final client = files.testing.readString(
      AssetId('orm', 'lib/fixture/models.orm.dart'),
    );
    final snapshot = files.testing.readString(
      AssetId('orm', 'lib/fixture/models.snapshot.dart'),
    );
    expect(client, contains('get user =>'));
    expect(client, contains('get audit =>'));
    expect(client, isNot(contains('FeaturesAudit')));
    expect(snapshot, contains('namespace: "app"'));
    expect(snapshot, contains('namespace: "audit"'));
  });

  test('directory builder supports engine-neutral model discovery', () async {
    final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
    await files.testing.loadIsolateSources();
    final result = await testBuilder(
      ormBuilder(BuilderOptions({'models': 'lib/fixture/models'})),
      {'orm|lib/fixture/models/nested/user.dart': _user},
      rootPackage: 'orm',
      readerWriter: files,
      flattenOutput: true,
    );
    expect(result.succeeded, true, reason: result.errors.toString());
    final snapshot = files.testing.readString(
      AssetId('orm', 'lib/fixture/models.snapshot.dart'),
    );
    expect(snapshot, contains('"User"'));
    expect(snapshot, isNot(contains('namespace:')));
  });

  test('directory builder rejects unrelated generated part roots', () async {
    final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
    await files.testing.loadIsolateSources();
    final result = await testBuilder(
      ormBuilder(BuilderOptions({'models': 'lib/fixture/models'})),
      {
        'orm|lib/fixture/models/user.dart': _user.replaceFirst(
          "import 'package:orm/schema.dart';",
          "import 'package:orm/schema.dart';\npart 'helper.g.dart';",
        ),
        'orm|lib/fixture/models/helper.g.dart':
            "part of 'user.dart';\nconst generatedHelper = 1;\n",
      },
      rootPackage: 'orm',
      readerWriter: files,
      flattenOutput: true,
    );
    expect(result.succeeded, false);
    expect(
      result.errors.join('\n'),
      contains('Use independent Dart model libraries'),
    );
    expect(result.outputs, isEmpty);
  });

  test(
    'directory build rejects semantic errors in referenced external models',
    () async {
      final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
      await files.testing.loadIsolateSources();
      final result = await testBuilder(
        ormBuilder(
          BuilderOptions({
            'models': 'lib/fixture/models',
            'database': 'postgres',
          }),
        ),
        {
          'orm|lib/fixture/models/root.dart': """
import 'package:orm/schema.dart';
import '../target.dart';
@Model()
class Root {
  @Id() final int id;
  @Relation(target: Target, name: 'target') final int targetId;
  const Root({required this.id, required this.targetId});
}
""",
          'orm|lib/fixture/target.dart': """
import 'package:orm/schema.dart';
@Model()
class Target {
  @Id() final int id;
  const Target({required this.id});
}
int broken = 'not an integer';
""",
        },
        rootPackage: 'orm',
        readerWriter: files,
        flattenOutput: true,
      );
      expect(result.succeeded, false);
      expect(result.errors, isNotEmpty);
      expect(result.outputs, isEmpty);
    },
  );

  test('real recursive DTO build is deterministic and matches standalone generation', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    try {
      await fixture.file('lib/schema.dart').delete();
      await fixture.write('build.yaml', '''
targets:
  \$default:
    builders:
      orm:orm:
        enabled: true
        options:
          models: lib/dtos
          database: postgres
          default_namespace: app
''');
      await fixture.write('lib/dtos/user.dart', _user);
      await fixture.write('lib/dtos/features/audit/events.dart', _audit);
      final first = await fixture.run(['run', 'build_runner', 'build']);
      expect(first.output, contains('wrote 2 outputs'));
      final client = fixture.file('lib/dtos.orm.dart');
      final snapshot = fixture.file('lib/dtos.snapshot.dart');
      final result = await generateSchema(
        fixture.file('lib/dtos').path,
        dialect: .postgres,
        defaultNamespace: 'app',
      );
      expect(await client.readAsString(), result.dart);
      expect(await snapshot.readAsString(), result.snapshotDart);
      final modified = (await client.stat()).modified;
      final second = await fixture.run(['run', 'build_runner', 'build']);
      expect(second.output, contains('wrote 0 outputs'));
      expect((await client.stat()).modified, modified);
      await fixture.run(['analyze', 'lib']);
    } finally {
      await fixture.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

final class _OnlyRoot(final String root, Map<String, dynamic> options)
    implements Builder {
  final Builder delegate = ormBuilder(BuilderOptions(options));
  @override
  Map<String, List<String>> get buildExtensions => delegate.buildExtensions;
  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId.toString() == root) await delegate.build(step);
  }
}

const _user = '''
import 'package:orm/schema.dart';
@Model()
class User {
  @Id(generated: true) final int id;
  final String name;
  const User({required this.id, required this.name});
}
''';

const _audit = '''
import 'package:orm/schema.dart';
@Model(namespace: 'audit')
class Audit {
  @Id() final int id;
  const Audit({required this.id});
}
''';
