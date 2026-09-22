@Tags(['core'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:orm/cli.dart';
import 'package:orm/src/cli/init.dart';
import 'package:orm/src/cli/output.dart';
import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';
import 'support/cli.dart';

void main() {
  Future<BuildFixture> project() async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    await fixture.file('lib/schema.dart').delete();
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
    final declaration = await fixture.file('lib/schema.dart').readAsString();
    expect(declaration, contains('final task = model('));
    final config = await fixture.file('orm.config.dart').readAsString();
    expect(config, contains('package:orm/drivers/sqlite.dart'));
    expect(config, isNot(contains('package:orm/orm.dart')));
    await fixture.write(
      'lib/schema.dart',
      declaration.replaceFirst(
        'title: text(),',
        'title: text(),\n  detail: text().nullable(),',
      ),
    );
    final first = await report(fixture, ['migrate', 'create', '0001_initial']);
    expect(first['created'], contains('m0001_initial.dart'));
    final initial = fixture.file('migrations/m0001_initial.dart');
    final initialSource = await initial.readAsString();
    expect(initialSource, contains('detail'));
    expect(initialSource, isNot(contains('lib/schema.dart')));
    expect(await fixture.file('app.sqlite').exists(), false);
    expect((await report(fixture, ['migrate', 'apply']))['applied'], [
      '0001_initial',
    ]);
    final firstSnapshot = await fixture
        .file('lib/schema.snapshot.dart')
        .readAsString();
    await fixture.write(
      'lib/schema.dart',
      declaration.replaceFirst(
        'title: text(),',
        'title: text(),\n  detail: text().nullable(),\n  label: text().nullable(),',
      ),
    );
    // No explicit generate: create must read the edited model, even though the
    // configuration imported the previous snapshot before command execution.
    await report(fixture, ['migrate', 'create', '0002_label']);
    expect(
      await fixture.file('lib/schema.snapshot.dart').readAsString(),
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
  }, timeout: const Timeout(Duration(minutes: 3)));

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
import '../orm.config.dart' as project;
Future<void> main() async {
  await project.main(['migrate', 'check', '--json']);
  if (exitCode != 0) return;
  await project.main(['migrate', 'status', '--json']);
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
      await fixture.write('lib/schema.dart', BuildFixture.schema(1));
      final output = fixture.file('lib/custom.orm.dart').path;
      final config = OrmConfig(
        schema: fixture.file('lib/schema.dart').path,
        output: output,
        migrations: fixture.file('migrations').path,
        history: MigrationHistory([], dialect: .postgres),
        snapshot: SchemaSnapshot([]),
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
      await fixture.write('lib/schema.dart', '// User-owned source.\n');
      await expectLater(
        initializeProject(
          ['--database', 'sqlite'],
          CliOutput(true),
          directory: fixture.directory.path,
        ),
        throwsFormatException,
      );
      expect(
        await fixture.file('lib/schema.dart').readAsString(),
        '// User-owned source.\n',
      );
      for (final path in [
        'orm.config.dart',
        'lib/schema.orm.dart',
        'lib/schema.snapshot.dart',
        'migrations/migrations.g.dart',
      ]) {
        expect(await fixture.file(path).exists(), false, reason: path);
      }
    },
  );
}
