@Tags(['core'])
library;

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:orm/builder.dart';
import 'package:orm/generate.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/cli.dart';

const _prefix = 'lib/fixture/model_library';
const _schema = "import 'package:orm/schema.dart';\n";
const _user = '@Model() final class User({@Id() required final int id});';
const _post = '''
@Model() final class Post({
  @Id() required final int id,
  @Relation(target: User, name: 'user') required final int userId,
});
''';

({Map<String, String> files, String source, String owner}) _fixture(
  String mode,
  bool modelInPart,
) {
  final owner = '$_prefix/${mode == 'directory' ? 'models/' : ''}owner.dart';
  const part = '$_prefix/parts/user.dart';
  final files = <String, String>{
    owner:
        "${_schema}part '${p.url.relative(part, from: p.url.dirname(owner))}';\n${modelInPart ? '' : _user}",
    part:
        "part of '${p.url.relative(owner, from: p.url.dirname(part))}';\n${modelInPart ? _user : 'const generatedHelper = 1;'}",
  };
  var source = owner;
  if (mode == 'directory') {
    source = '$_prefix/models';
  } else if (mode == 'export' || mode == 'transitive_export') {
    source = '$_prefix/root.dart';
    if (mode == 'transitive_export') {
      files['$_prefix/bridge.dart'] = "export 'owner.dart';";
    }
    files[source] = "export '${mode == 'export' ? 'owner' : 'bridge'}.dart';";
  } else if (mode == 'relation') {
    source = '$_prefix/root.dart';
    files[source] = "${_schema}import 'owner.dart';\n$_post";
  }
  return (files: files, source: source, owner: owner);
}

void main() {
  late Directory project;
  setUp(
    () async =>
        project = await Directory('.dart_tool').createTemp('model-library-'),
  );
  tearDown(() => project.delete(recursive: true));

  Future<void> write(Map<String, String> files) async {
    for (final entry in files.entries) {
      final file = File(p.join(project.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
  }

  for (final mode in [
    'explicit',
    'directory',
    'export',
    'transitive_export',
    'relation',
  ]) {
    for (final inPart in [true, false]) {
      test(
        'standalone $mode rejects owning parts with modelInPart=$inPart',
        () async {
          final fixture = _fixture(mode, inPart);
          await write(fixture.files);
          final source = p.absolute(p.join(project.path, fixture.source));
          final output = File(p.join(project.path, 'client.orm.dart'));
          final snapshot = File(p.join(project.path, 'client.snapshot.dart'));
          await output.writeAsString('previous client');
          await snapshot.writeAsString('previous snapshot');
          await expectLater(
            writeGeneratedSchema(source, output: output.path),
            throwsA(
              isA<GenerationException>()
                  .having((e) => e.code, 'code', 'SCHEMA.LIBRARY')
                  .having(
                    (e) => e.source,
                    'owner',
                    File(p.join(project.path, fixture.owner)).absolute.uri,
                  )
                  .having((e) => e.line, 'directive line', 2),
            ),
          );
          if (mode == 'explicit') {
            final result = await runCli([
              'generate',
              source,
              output.absolute.path,
              '--json',
            ]);
            expect(result.exitCode, isNonZero);
            expect(
              '${result.stdout}${result.stderr}',
              contains('SCHEMA.LIBRARY'),
            );
          }
          expect(await output.readAsString(), 'previous client');
          expect(await snapshot.readAsString(), 'previous snapshot');
        },
      );

      test(
        'builder $mode rejects owning parts with modelInPart=$inPart',
        () async {
          final fixture = _fixture(mode, inPart);
          final files = TestReaderWriter(
            rootPackage: 'orm',
            flattenOutput: true,
          );
          await files.testing.loadIsolateSources();
          final result = await testBuilder(
            mode == 'directory'
                ? ormBuilder(BuilderOptions({'models': fixture.source}))
                : _OnlyRoot('orm|${fixture.source}'),
            {
              for (final entry in fixture.files.entries)
                'orm|${entry.key}': entry.value,
            },
            rootPackage: 'orm',
            readerWriter: files,
            flattenOutput: true,
          );
          expect(result.succeeded, false);
          expect(result.errors.join('\n'), contains('SCHEMA.LIBRARY'));
          expect(
            result.errors.join('\n'),
            isNot(contains('Bad state: No element')),
          );
          expect(result.outputs, isEmpty);
        },
      );
    }
  }

  test('unrelated imported parts do not become model libraries', () async {
    final files = <String, String>{
      '$_prefix/root.dart':
          "${_schema}import 'business.dart';\n@Model() final class User({@Id() required final int id}) { int marker() => businessMarker; }",
      '$_prefix/business.dart': "part 'parts/helper.g.dart';",
      '$_prefix/parts/helper.g.dart':
          "part of '../business.dart';\nconst businessMarker = 1;",
    };
    await write(files);
    final standalone = await generateSchema(
      p.join(project.path, '$_prefix/root.dart'),
    );
    expect(standalone.snapshot.tables.map((table) => table.name), ['User']);
    final assets = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
    await assets.testing.loadIsolateSources();
    final result = await testBuilder(
      _OnlyRoot('orm|$_prefix/root.dart'),
      {for (final entry in files.entries) 'orm|${entry.key}': entry.value},
      rootPackage: 'orm',
      readerWriter: assets,
      flattenOutput: true,
    );
    expect(result.succeeded, true, reason: result.errors.toString());
  });
}

final class _OnlyRoot(final String root) implements Builder {
  final Builder delegate = ormBuilder(BuilderOptions({}));
  @override
  Map<String, List<String>> get buildExtensions => delegate.buildExtensions;
  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId.toString() == root) await delegate.build(step);
  }
}
