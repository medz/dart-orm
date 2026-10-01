@Tags(['core'])
library;

import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:orm/builder.dart';
import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/cli.dart';

const _prefix = 'lib/fixture/identity_default';
const _schema = "import 'package:orm/schema.dart';\n";
const _defaults = ['@DatabaseDefault(7)', "@DatabaseDefault.sql('7')"];

({Map<String, String> files, String source, String owner}) _fixture(
  String mode,
  String annotation,
) {
  final owner = '$_prefix/${mode == 'directory' ? 'models/' : ''}user.dart';
  final files = <String, String>{
    owner:
        '''$_schema@Model()
final class User({
  @Id(generated: true) $annotation required final int id,
});
''',
  };
  var source = owner;
  if (mode == 'directory') {
    source = '$_prefix/models';
  } else if (mode == 'export') {
    source = '$_prefix/root.dart';
    files[source] = "export 'user.dart';";
  } else if (mode == 'relation') {
    source = '$_prefix/root.dart';
    files[source] = '''${_schema}import 'user.dart';
@Model() final class Post({
  @Id() required final int id,
  @Relation(target: User, name: 'user') required final int userId,
});
''';
  }
  return (files: files, source: source, owner: owner);
}

void main() {
  late Directory project;
  setUp(
    () async =>
        project = await Directory('.dart_tool').createTemp('identity-default-'),
  );
  tearDown(() => project.delete(recursive: true));

  Future<void> write(Map<String, String> files) async {
    for (final entry in files.entries) {
      final file = File(p.join(project.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
  }

  for (final mode in ['explicit', 'directory', 'export', 'relation']) {
    test('standalone $mode rejects database defaults on identities', () async {
      for (final annotation in _defaults) {
        final fixture = _fixture(mode, annotation);
        await write(fixture.files);
        final source = p.absolute(p.join(project.path, fixture.source));
        final output = File(p.join(project.path, 'client.orm.dart'));
        final snapshot = File(p.join(project.path, 'client.snapshot.dart'));
        await output.writeAsString('previous client');
        await snapshot.writeAsString('previous snapshot');
        await expectLater(
          writeGeneratedSchema(source, output: output.path, dialect: .postgres),
          throwsA(
            isA<GenerationException>()
                .having((e) => e.code, 'code', 'SCHEMA.DEFAULT')
                .having(
                  (e) => e.source,
                  'owner',
                  File(p.join(project.path, fixture.owner)).absolute.uri,
                )
                .having((e) => e.line, 'annotation line', 4),
          ),
        );
        if (mode == 'explicit') {
          final result = await runCli([
            'generate',
            source,
            output.absolute.path,
            '--database',
            'postgres',
            '--json',
          ]);
          expect(result.exitCode, isNonZero);
          expect(
            '${result.stdout}${result.stderr}',
            contains('SCHEMA.DEFAULT'),
          );
        }
        expect(await output.readAsString(), 'previous client');
        expect(await snapshot.readAsString(), 'previous snapshot');
      }
    });

    test('builder $mode rejects database defaults on identities', () async {
      for (final annotation in _defaults) {
        final fixture = _fixture(mode, annotation);
        final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
        await files.testing.loadIsolateSources();
        final result = await testBuilder(
          mode == 'directory'
              ? ormBuilder(
                  BuilderOptions({
                    'models': fixture.source,
                    'database': 'postgres',
                  }),
                )
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
        expect(result.errors.join('\n'), contains('SCHEMA.DEFAULT'));
        expect(result.outputs, isEmpty);
      }
    });
  }

  test(
    'engine-neutral field annotations reject identity database defaults',
    () async {
      for (final annotation in _defaults) {
        const source = '$_prefix/fields.dart';
        await write({
          source:
              '''$_schema@Model()
class User {
  @Id(generated: true) $annotation final int id;
  const User({required this.id});
}
''',
        });
        await expectLater(
          generateSchema(p.join(project.path, source)),
          throwsA(
            isA<GenerationException>().having(
              (e) => e.code,
              'code',
              'SCHEMA.DEFAULT',
            ),
          ),
        );
      }
    },
  );

  test('identity client defaults produce PostgreSQL identity without SQL DEFAULT', () async {
    const source = '$_prefix/client.dart';
    await write({
      source:
          '''${_schema}int clientIdentity() => throw StateError('generation called the factory');
@Model() final class User({
  @Id(generated: true) @ClientDefault(clientIdentity) required final int id,
});
''',
    });
    final generated = await generateSchema(
      p.join(project.path, source),
      dialect: .postgres,
    );
    final column = generated.snapshot.tables.single.columns.single;
    expect(column.generated, true);
    expect(column.defaultSql, isNull);
    expect(generated.dart, contains('clientDefault: models.clientIdentity'));
    final ddl = createSchema(
      generated.snapshot.tables,
      .postgres,
    ).map((c) => c.sql).join('\n');
    expect(ddl, contains('GENERATED BY DEFAULT AS IDENTITY'));
    expect(ddl, isNot(contains(' DEFAULT (')));
    final files = TestReaderWriter(rootPackage: 'orm', flattenOutput: true);
    await files.testing.loadIsolateSources();
    final result = await testBuilder(
      _OnlyRoot('orm|$source'),
      {'orm|$source': await File(p.join(project.path, source)).readAsString()},
      rootPackage: 'orm',
      readerWriter: files,
      flattenOutput: true,
    );
    expect(result.succeeded, true, reason: result.errors.toString());
    expect(
      files.testing.readString(
        AssetId('orm', source.replaceFirst('.dart', '.orm.dart')),
      ),
      contains('clientDefault: models.clientIdentity'),
    );
  });

  test('non-generated keys retain database defaults in PostgreSQL DDL', () async {
    const source = '$_prefix/manual.dart';
    await write({
      source:
          '$_schema@Model() final class User({@Id() @DatabaseDefault(7) required final int id});',
    });
    final generated = await generateSchema(
      p.join(project.path, source),
      dialect: .postgres,
    );
    final column = generated.snapshot.tables.single.columns.single;
    expect(column.generated, false);
    expect(column.defaultSql, '7');
    final ddl = createSchema(
      generated.snapshot.tables,
      .postgres,
    ).map((c) => c.sql).join('\n');
    expect(ddl, contains(' DEFAULT (7)'));
    expect(ddl, isNot(contains('IDENTITY')));
  });
}

final class _OnlyRoot(final String root) implements Builder {
  final Builder delegate = ormBuilder(BuilderOptions({'database': 'postgres'}));
  @override
  Map<String, List<String>> get buildExtensions => delegate.buildExtensions;
  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId.toString() == root) await delegate.build(step);
  }
}
