@Tags(['core'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:orm/src/cli/config_entrypoint.dart';
import 'package:orm/src/cli/init.dart';
import 'package:orm/src/cli/output.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';
import 'support/cli.dart';

void main() {
  Future<BuildFixture> project() async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    for (final path in ['lib/schema.dart', 'lib/models.dart']) {
      if (await fixture.file(path).exists()) await fixture.file(path).delete();
    }
    return fixture;
  }

  Future<Map<String, Object?>> report(
    BuildFixture fixture,
    List<String> args, {
    int code = 0,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'orm', ...args, '--json'],
      workingDirectory: fixture.directory.path,
      environment: {'DATABASE_URL': ''},
    );
    expect(
      result.exitCode,
      code,
      reason: '${args.join(' ')}\n${result.stdout}\n${result.stderr}',
    );
    return jsonDecode(result.stdout as String) as Map<String, Object?>;
  }

  test('package CLI loads generated configuration and reloads edited models and history', () async {
    final fixture = await project();
    addTearDown(fixture.dispose);
    final initialized = await report(fixture, ['init', '--database', 'sqlite']);
    expect(initialized['database'], 'sqlite');
    expect(initialized['created'], hasLength(5));
    expect(await fixture.file('app.sqlite').exists(), false);
    final declaration = await fixture.file('lib/models.dart').readAsString();
    expect(declaration, contains("@Model(table: 'tasks')"));
    final config = await fixture.file('orm.config.dart').readAsString();
    expect(config, contains('package:orm/drivers/sqlite.dart'));
    expect(config, isNot(contains('package:orm/orm.dart')));
    await fixture.write(
      'lib/models.dart',
      declaration.replaceFirst(
        'required final String title,',
        'required final String title,\n  final String? detail,',
      ),
    );
    final first = await report(fixture, ['migrate', 'create', '0001_initial']);
    expect(first['created'], contains('m0001_initial.dart'));
    final initial = fixture.file('migrations/m0001_initial.dart');
    final initialSource = await initial.readAsString();
    expect(initialSource, contains('detail'));
    expect(initialSource, isNot(contains('lib/models.dart')));
    expect(await fixture.file('app.sqlite').exists(), false);
    expect((await report(fixture, ['migrate', 'apply']))['applied'], [
      '0001_initial',
    ]);
    final firstSnapshot = await fixture
        .file('lib/models.snapshot.dart')
        .readAsString();
    await fixture.write(
      'lib/models.dart',
      declaration.replaceFirst(
        'required final String title,',
        'required final String title,\n  final String? detail,\n  final String? label,',
      ),
    );
    // Verification reads edited DTOs without rewriting generated artifacts.
    expect(
      (await report(fixture, ['migrate', 'verify'], code: 2))['matches'],
      false,
    );
    expect(
      await fixture.file('lib/models.snapshot.dart').readAsString(),
      firstSnapshot,
    );
    // Creation also reads current DTOs without an explicit generate command.
    await report(fixture, ['migrate', 'create', '0002_label']);
    expect(
      await fixture.file('lib/models.snapshot.dart').readAsString(),
      isNot(firstSnapshot),
    );
    expect(
      (await report(fixture, ['migrate', 'verify'], code: 2))['matches'],
      false,
    );
    expect((await report(fixture, ['migrate', 'apply']))['applied'], [
      '0002_label',
    ]);
    expect((await report(fixture, ['migrate', 'verify']))['matches'], true);
    expect(await initial.readAsString(), initialSource);
    for (final path in [
      'lib/models.dart',
      'lib/models.orm.dart',
      'lib/models.snapshot.dart',
    ]) {
      await fixture.file(path).delete();
    }
    expect((await report(fixture, ['migrate', 'check']))['valid'], true);
    expect(
      (await report(fixture, ['migrate', 'status']))['applied'],
      hasLength(2),
    );
  }, timeout: const Timeout(Duration(minutes: 6)));

  for (final engine in ['postgres', 'mysql', 'mariadb']) {
    test(
      '$engine generated configuration compiles and checks history without credentials',
      () async {
        final fixture = await project();
        addTearDown(fixture.dispose);
        final initialized = await captureCli(() async {
          await initializeProject(
            ['--database', engine],
            CliOutput(true),
            directory: fixture.directory.path,
          );
          return 0;
        });
        expect(cliReport(initialized)['database'], engine);
        final registry = await fixture
            .file('migrations/migrations.g.dart')
            .readAsString();
        expect(registry, contains('SqlDialect.$engine'));
        final config = await fixture.file('orm.config.dart').readAsString();
        expect(config, contains('package:orm/drivers/$engine.dart'));
        // Compile the generated configuration once. Only the connection command
        // should need credentials; the preceding history check must succeed.
        await fixture.write('bin/check_config.dart', '''
import 'dart:io';
import 'package:orm/src/cli/config_entrypoint.dart';
import '../orm.config.dart' as project;
import '../migrations/migrations.g.dart';
Future<void> main() async {
  final path = File('orm.config.dart').absolute.path;
  await runConfigEntrypoint(['migrate', 'check', '--json'], project.main,
      path: path, history: migrationHistory);
  if (exitCode != 0) return;
  await runConfigEntrypoint(['migrate', 'status', '--json'], project.main,
      path: path, history: migrationHistory);
}
''');
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', 'orm_build_fixture:check_config'],
          workingDirectory: fixture.directory.path,
          environment: {'DATABASE_URL': ''},
        );
        expect(
          result.exitCode,
          64,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(jsonDecode(result.stdout as String), {
          'valid': true,
          'dialect': engine,
          'migrations': <String>[],
        });
        expect(result.stderr, contains('DATABASE_URL is empty or missing'));
      },
    );
  }

  test(
    'help and option errors are handled without starting a project process',
    () async {
      final help = await runCli(['help', 'migrate']);
      expect(help.exitCode, 0);
      expect(help.stdout, contains('migrate <command>'));
      expect(help.stdout, contains('apply'));
      for (final args in [
        ['init', '--database', 'unknown'],
        ['init', '--database', 'sqlite', '--unexpected'],
        ['--json', '--json'],
        ['--config'],
        ['--config', '--json'],
        ['--config', 'a.dart', '--config', 'b.dart'],
        ['help', 'unknown'],
        ['migration', 'create', '0001_legacy', '--schema', 'unused.json'],
        ['db', 'inspect', '--config', 'unused.dart'],
      ]) {
        final invalid = await runCli([...args, '--json']);
        expect(invalid.exitCode, 64, reason: args.join(' '));
        expect(jsonDecode(invalid.stderr), containsPair('exitCode', 64));
        expect(invalid.stdout, isEmpty);
      }
      final missing = await runCli([
        'migrate',
        'check',
        '--config',
        '${Directory.systemTemp.path}/orm-missing-$pid.dart',
        '--json',
      ]);
      expect(missing.exitCode, 64);
      expect(missing.stderr, contains('Missing'));
    },
  );

  test(
    'project generation honors configuration paths and stays offline',
    () async {
      final fixture = await project();
      addTearDown(fixture.dispose);
      await fixture.write('lib/models.dart', _model);
      final output = fixture.file('lib/custom.orm.dart').path;
      final config = ProjectConfig(
        database: .postgres,
        models: fixture.file('lib/models.dart').path,
        output: output,
        migrations: fixture.file('migrations').path,
        connect: ({required readOnly}) =>
            throw StateError('Generation connected'),
      );
      final generated = await runCli(['generate', '--json'], config: config);
      expect(generated.exitCode, 0, reason: generated.stderr);
      expect(cliReport(generated)['generated'], output);
      expect(await File(output).exists(), true);
      expect(await fixture.file('lib/custom.snapshot.dart').exists(), true);
      final rejected = await runCli([
        'generate',
        '--database',
        'mysql',
        '--json',
      ], config: config);
      expect(rejected.exitCode, 64);
      expect(rejected.stderr, contains('must match'));
    },
  );

  test(
    'init refuses existing files without partially scaffolding a project',
    () async {
      final fixture = await project();
      addTearDown(fixture.dispose);
      await fixture.write('lib/models.dart', '// User-owned source.\n');
      await expectLater(
        initializeProject(
          ['--database', 'sqlite'],
          CliOutput(true),
          directory: fixture.directory.path,
        ),
        throwsFormatException,
      );
      expect(
        await fixture.file('lib/models.dart').readAsString(),
        '// User-owned source.\n',
      );
      for (final path in [
        'orm.config.dart',
        'lib/models.orm.dart',
        'lib/models.snapshot.dart',
        'migrations/migrations.g.dart',
      ]) {
        expect(await fixture.file(path).exists(), false, reason: path);
      }
    },
  );
}

const _model = '''import 'package:orm/schema.dart';
@Model()
final class Item({
  @Id(generated: true) required final int id,
  required final String title,
});
''';
