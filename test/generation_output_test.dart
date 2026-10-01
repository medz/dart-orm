@Tags(['core'])
library;

import 'dart:io';

import 'package:orm/generate.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';
import 'support/cli.dart';

void main() {
  late Directory project;
  Future<void> write(String path, String contents) async {
    final file = File(p.join(project.path, path));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  setUp(() async {
    project = await Directory('.dart_tool').createTemp('generation-output-');
    await write('models.dart', "export 'domain/barrel.dart';\n");
    await write('domain/barrel.dart', "export 'user.dart';\n");
    await write('domain/user.dart', '''
import 'package:orm/schema.dart';
import 'team.dart';
import 'behavior.dart';

@Model(table: 'users')
final class User with Behavior {
  @Id(generated: true) final int id;
  @Relation(target: Team, name: 'team') final int teamId;
  final String name;
  const User({required this.id, required this.teamId, required this.name});
}
''');
    await write('domain/team.dart', '''
import 'package:orm/schema.dart';

@Model(table: 'teams')
final class Team({@Id(generated: true) required final int id});
''');
    await write('domain/behavior.dart', '''
import 'labels.dart';
mixin Behavior {
  String get name;
  String get label => prefix + name;
}
''');
    await write('domain/labels.dart', "const prefix = 'User: ';\n");
  });
  tearDown(() => project.delete(recursive: true));

  for (final dependency in [
    'models.dart',
    'domain/barrel.dart',
    'domain/user.dart',
    'domain/team.dart',
    'domain/behavior.dart',
    'domain/labels.dart',
  ]) {
    test('generation cannot overwrite $dependency', () async {
      final output = File(p.join(project.path, dependency));
      final original = await output.readAsString();
      final snapshot = File(p.setExtension(output.path, '.snapshot.dart'));
      await snapshot.writeAsString('previous snapshot');
      final result = await runCli([
        'generate',
        File(p.join(project.path, 'models.dart')).absolute.path,
        output.absolute.path,
        '--database',
        'postgres',
        '--json',
      ]);
      expect(result.exitCode, 1, reason: result.stderr);
      expect(result.stderr, contains('SCHEMA.OUTPUT'));
      expect(result.stderr, contains(output.absolute.path));
      expect(await output.readAsString(), original);
      expect(await snapshot.readAsString(), 'previous snapshot');
    });
  }

  test('safe output generates and regenerates from exported models', () async {
    final source = p.join(project.path, 'models.dart');
    final output = p.join(project.path, 'generated', 'client.orm.dart');
    await writeGeneratedSchema(source, output: output, dialect: .postgres);
    final before = await File(output).readAsString();
    expect(before, contains('get user =>'));
    expect(before, contains('get team =>'));
    await writeGeneratedSchema(source, output: output, dialect: .postgres);
    expect(await File(output).readAsString(), before);
  });

  test('snapshot destination cannot replace a selected source', () async {
    final source = p.join(project.path, 'frozen.snapshot.dart');
    await File(p.join(project.path, 'domain/team.dart')).copy(source);
    final original = await File(source).readAsString();
    final output = p.join(project.path, 'frozen.orm.dart');
    await File(output).writeAsString('previous client');
    await expectLater(
      writeGeneratedSchema(source, output: output, dialect: .sqlite),
      throwsA(
        isA<GenerationException>().having(
          (error) => error.code,
          'code',
          'SCHEMA.OUTPUT',
        ),
      ),
    );
    expect(await File(source).readAsString(), original);
    expect(await File(output).readAsString(), 'previous client');
  });

  for (final snapshot in [false, true]) {
    for (final hardLink in [false, true]) {
      test(
        '${snapshot ? 'snapshot' : 'client'} ${hardLink ? 'hard link' : 'symbolic link'} cannot replace a dependency',
        () async {
          final source = File(p.join(project.path, 'domain/labels.dart'));
          final original = await source.readAsString();
          final output = p.join(project.path, 'client.orm.dart');
          final companion = p.join(project.path, 'client.snapshot.dart');
          final alias = snapshot ? companion : output;
          final preserved = File(snapshot ? output : companion);
          await preserved.writeAsString('previous artifact');
          if (hardLink) {
            final result = await Process.run('ln', [
              source.absolute.path,
              alias,
            ]);
            expect(result.exitCode, 0, reason: result.stderr.toString());
          } else {
            await Link(alias).create(source.absolute.path);
          }
          await expectLater(
            writeGeneratedSchema(
              p.join(project.path, 'models.dart'),
              output: output,
              dialect: .sqlite,
            ),
            throwsA(
              isA<GenerationException>().having(
                (error) => error.code,
                'code',
                'SCHEMA.OUTPUT',
              ),
            ),
          );
          expect(await source.readAsString(), original);
          expect(await File(alias).readAsString(), original);
          expect(await preserved.readAsString(), 'previous artifact');
        },
        skip: Platform.isWindows ? 'Fixture needs Unix link creation.' : false,
      );
    }
  }

  test(
    'parent traversal through a directory link cannot replace a dependency',
    () async {
      final directory = Directory(p.join(project.path, 'domain/nested'));
      await directory.create();
      await Link(p.join(project.path, 'alias')).create(directory.absolute.path);
      final source = File(p.join(project.path, 'domain/labels.dart'));
      final original = await source.readAsString();
      final output = '${project.absolute.path}/alias/../labels.dart';
      expect(File(output).readAsStringSync(), original);
      await expectLater(
        writeGeneratedSchema(
          p.join(project.path, 'models.dart'),
          output: output,
          dialect: .sqlite,
        ),
        throwsA(
          isA<GenerationException>().having(
            (error) => error.code,
            'code',
            'SCHEMA.OUTPUT',
          ),
        ),
      );
      expect(await source.readAsString(), original);
      expect(File(p.join(project.path, 'labels.dart')).existsSync(), false);
    },
    skip: Platform.isWindows ? 'Fixture needs Unix directory links.' : false,
  );

  for (final directive in ['import', 'export']) {
    for (final dependency in [
      'platform_stub.dart',
      'fallback/details.dart',
      'platform_web.dart',
      'web/details.dart',
    ]) {
      test('conditional $directive protects unselected $dependency', () async {
        await write('models.dart', '''
export 'domain/barrel.dart';
$directive 'platform_stub.dart'
    if (dart.library.io) 'platform_native.dart'
    if (dart.library.js_interop) 'platform_web.dart';
''');
        await write('platform_stub.dart', "export 'fallback/details.dart';\n");
        await write('fallback/details.dart', '''
export '../platform_stub.dart';
const platformLabel = 'fallback';
''');
        await write(
          'platform_native.dart',
          "const platformLabel = 'native';\n",
        );
        await write('platform_web.dart', "export 'web/details.dart';\n");
        await write('web/details.dart', '''
export '../platform_web.dart';
const platformLabel = 'web';
''');
        final output = File(p.join(project.path, dependency));
        final original = await output.readAsString();
        final snapshot = File(p.setExtension(output.path, '.snapshot.dart'));
        await snapshot.writeAsString('previous snapshot');
        await expectLater(
          writeGeneratedSchema(
            p.join(project.path, 'models.dart'),
            output: output.path,
            dialect: .sqlite,
          ),
          throwsA(
            isA<GenerationException>().having(
              (error) => error.code,
              'code',
              'SCHEMA.OUTPUT',
            ),
          ),
        );
        expect(await output.readAsString(), original);
        expect(await snapshot.readAsString(), 'previous snapshot');
      });
    }
  }

  test('source-side symbolic link protects its target', () async {
    final target = File(p.join(project.path, 'domain/labels.dart'));
    final original = await target.readAsString();
    await Link(p.join(project.path, 'domain/labels_alias.dart'))
        .create(target.absolute.path);
    final behavior = File(p.join(project.path, 'domain/behavior.dart'));
    await behavior.writeAsString(
      (await behavior.readAsString()).replaceFirst(
        "'labels.dart'",
        "'labels_alias.dart'",
      ),
    );
    await expectLater(
      writeGeneratedSchema(
        p.join(project.path, 'models.dart'),
        output: target.path,
        dialect: .sqlite,
      ),
      throwsA(
        isA<GenerationException>().having(
          (error) => error.code,
          'code',
          'SCHEMA.OUTPUT',
        ),
      ),
    );
    expect(await target.readAsString(), original);
  }, skip: Platform.isWindows ? 'Fixture needs Unix file links.' : false);

  test('nested config protects source dependencies before generation and migration creation', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    addTearDown(fixture.dispose);
    await fixture.file('lib/schema.dart').delete();
    await fixture.write('lib/models.dart', "export 'domain/user.dart';\n");
    await fixture.write('lib/domain/user.dart', '''
import 'package:orm/schema.dart';
import '../labels.dart';
@Model(table: 'users')
final class User({
  @Id(generated: true) required final int id,
  required final String name,
}) {
  String get label => prefix + name;
}
''');
    const helper = "const prefix = 'User: ';\n";
    await fixture.write('lib/labels.dart', helper);
    await fixture.write('lib/labels.snapshot.dart', '// previous snapshot\n');
    Future<void> configure(String output) => fixture.write(
      'configuration/development.dart',
      '''import 'package:orm/config.dart';
void main() => defineConfig(
  database: .postgres,
  models: '../lib/models.dart',
  output: '$output',
  migrations: '../history',
  defaultNamespace: 'application',
  connect: ({required readOnly}) => throw StateError('Offline command connected'),
);
''',
    );
    await configure('../lib/labels.dart');
    Future<CliResult> run(List<String> command) => runCli([
      ...command,
      '--config',
      fixture.file('configuration/development.dart').path,
      '--json',
    ]);
    for (final command in [
      ['generate'],
      ['migrate', 'create', '0001_initial'],
    ]) {
      final result = await run(command);
      expect(result.exitCode, 1, reason: result.stderr);
      expect(result.stderr, contains('SCHEMA.OUTPUT'));
      expect(await fixture.file('lib/labels.dart').readAsString(), helper);
      expect(
        await fixture.file('lib/labels.snapshot.dart').readAsString(),
        '// previous snapshot\n',
      );
      expect(await fixture.file('history').exists(), false);
    }
    await configure('../lib/generated/client.orm.dart');
    final generated = await run(['generate']);
    expect(generated.exitCode, 0, reason: generated.stderr);
    final created = await run(['migrate', 'create', '0001_initial']);
    expect(created.exitCode, 0, reason: created.stderr);
    expect(await fixture.file('history/m0001_initial.dart').exists(), true);
    expect(
      await fixture.file('lib/generated/client.snapshot.dart').readAsString(),
      contains('namespace: "application"'),
    );
    await fixture.run(['analyze']);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
