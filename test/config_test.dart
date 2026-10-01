@Tags(['core'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:orm/config.dart';
import 'package:orm/src/cli/config_entrypoint.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';
import 'support/cli.dart';

void main() {
  test('configuration paths resolve from the config directory', () {
    final directory = p.join(Directory.systemTemp.path, 'orm-config-paths');
    final invocation = ConfigInvocation(
      p.join(directory, 'configuration', 'orm.config.dart'),
    );
    final absolute = p.join(directory, 'absolute.orm.dart');
    final config = ProjectConfig(
      database: .postgres,
      models: '../lib/models',
      output: absolute,
      migrations: '../history',
      defaultNamespace: 'application',
    ).resolve(invocation);
    expect(config.models, p.join(directory, 'lib', 'models'));
    expect(config.output, absolute);
    expect(config.migrations, p.join(directory, 'history'));
    expect(config.database, SqlDialect.postgres);
    expect(config.defaultNamespace, 'application');
  });

  test('defineConfig reports invalid or uninvoked configuration', () {
    expect(
      () => defineConfig(database: .sqlite),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('dart run orm <command>'),
        ),
      ),
    );
    for (final invalid in <void Function()>[
      () => defineConfig(database: .sqlite, models: ''),
      () => defineConfig(database: .sqlite, output: ' '),
      () => defineConfig(database: .sqlite, migrations: ''),
      () => defineConfig(database: .postgres, defaultNamespace: ' '),
    ]) {
      expect(
        invalid,
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('cannot be empty'),
          ),
        ),
      );
    }
  });

  test(
    'configuration and registry compile failures have structured exit codes',
    () async {
      final fixture = await BuildFixture.create(
        ormPath: Directory.current.path,
      );
      addTearDown(fixture.dispose);
      final config = fixture.file('orm.config.dart');
      Future<CliResult> run(String command) => runCli([
        command,
        if (command == 'migrate') 'check',
        '--config',
        config.path,
        '--json',
      ]);
      await fixture.write('orm.config.dart', 'void main() { invalid syntax }');
      final invalidConfig = await run('generate');
      expect(invalidConfig.exitCode, 1, reason: invalidConfig.stderr);
      expect(invalidConfig.stdout, isEmpty);
      final configError =
          jsonDecode(invalidConfig.stderr) as Map<String, dynamic>;
      expect(configError['exitCode'], 1);
      expect(configError['error'], contains('orm.config.dart'));

      await fixture.write(
        'orm.config.dart',
        '''import 'package:orm/config.dart';
void main() { defineConfig(database: .sqlite); }
''',
      );
      await fixture.write(
        'migrations/migrations.g.dart',
        'invalid migration syntax',
      );
      final invalidRegistry = await run('migrate');
      expect(invalidRegistry.exitCode, 1, reason: invalidRegistry.stderr);
      expect(invalidRegistry.stdout, isEmpty);
      final historyError =
          jsonDecode(invalidRegistry.stderr) as Map<String, dynamic>;
      expect(historyError['exitCode'], 1);
      expect(historyError['error'], contains('migrations.g.dart'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('void main configuration bootstraps generation from another working directory', () async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    addTearDown(fixture.dispose);
    await fixture.write('lib/models.dart', '''
import 'package:orm/schema.dart';

@Model()
final class User({
  @Id(generated: true) required final int id,
  required final String name,
});
''');
    await fixture.write('configuration/orm.config.dart', '''
import 'package:orm/config.dart';

void main() {
  defineConfig(
    database: .postgres,
    models: '../lib/models.dart',
    output: '../lib/generated/client.orm.dart',
    migrations: '../history',
    defaultNamespace: 'application',
  );
}
''');
    final workingDirectory = Directory(p.join(fixture.directory.path, 'tool'));
    await workingDirectory.create();
    Future<ProcessResult> run(List<String> arguments) =>
        Process.run(Platform.resolvedExecutable, [
          'run',
          'orm',
          ...arguments,
          '--config',
          '../configuration/orm.config.dart',
          '--json',
        ], workingDirectory: workingDirectory.path);

    expect(await fixture.file('lib/generated/client.orm.dart').exists(), false);
    expect(
      await fixture.file('lib/generated/client.snapshot.dart').exists(),
      false,
    );
    expect(await fixture.file('history/migrations.g.dart').exists(), false);
    final generated = await run(['generate']);
    expect(
      generated.exitCode,
      0,
      reason: '${generated.stdout}\n${generated.stderr}',
    );
    expect(jsonDecode(generated.stdout as String), {
      'generated': fixture.file('lib/generated/client.orm.dart').path,
    });
    expect(await fixture.file('lib/generated/client.orm.dart').exists(), true);
    final snapshot = await fixture
        .file('lib/generated/client.snapshot.dart')
        .readAsString();
    expect(snapshot, contains('namespace: "application"'));
    expect(await fixture.file('history/migrations.g.dart').exists(), false);
    expect(await fixture.file('app.sqlite').exists(), false);

    final rejected = await run(['generate', '--database', 'sqlite']);
    expect(
      rejected.exitCode,
      64,
      reason: '${rejected.stdout}\n${rejected.stderr}',
    );
    expect(rejected.stderr, contains('must match'));
    final migration = await run(['migrate', 'check']);
    expect(
      migration.exitCode,
      0,
      reason: '${migration.stdout}\n${migration.stderr}',
    );
    expect(jsonDecode(migration.stdout as String), {
      'valid': true,
      'dialect': 'postgres',
      'migrations': <String>[],
    });
    expect(await fixture.file('history/migrations.g.dart').exists(), false);

    await fixture.write('configuration/orm.config.dart', '''
import 'package:orm/config.dart';
void main() {
  defineConfig(database: .sqlite, models: '../lib/models.dart');
  defineConfig(database: .sqlite, models: '../lib/models.dart');
}
''');
    final repeated = await run(['generate']);
    expect(
      repeated.exitCode,
      64,
      reason: '${repeated.stdout}\n${repeated.stderr}',
    );
    expect(repeated.stderr, contains('exactly one'));
    expect(await fixture.file('lib/models.orm.dart').exists(), false);
    expect(
      await Directory(p.join(fixture.directory.path, '.dart_tool', 'orm'))
          .list()
          .isEmpty,
      true,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
