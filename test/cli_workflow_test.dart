import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../tool/src/build_fixture.dart';

void main() {
  Future<BuildFixture> project() async {
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    await fixture.file('lib/schema.dart').delete();
    return fixture;
  }

  Future<ProcessResult> run(
    BuildFixture fixture,
    List<String> args, {
    int code = 0,
  }) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'orm', ...args],
      workingDirectory: fixture.directory.path,
      environment: {'DATABASE_URL': ''},
    );
    expect(
      result.exitCode,
      code,
      reason: '${args.join(' ')}\n${result.stdout}\n${result.stderr}',
    );
    return result;
  }

  Future<Map<String, Object?>> report(
    BuildFixture fixture,
    List<String> args, {
    int code = 0,
  }) async {
    final result = await run(fixture, [...args, '--json'], code: code);
    return jsonDecode(result.stdout as String) as Map<String, Object?>;
  }

  test(
    'init through migration apply is a real SQLite consumer workflow',
    () async {
      final fixture = await project();
      try {
        final initialized = await report(fixture, [
          'init',
          '--database',
          'sqlite',
        ]);
        expect(initialized['database'], 'sqlite');
        expect(initialized['created'], hasLength(5));
        expect(await fixture.file('app.sqlite').exists(), false);
        final declaration = await fixture
            .file('lib/schema.dart')
            .readAsString();
        expect(declaration, contains('final class Task'));
        final config = await fixture.file('orm.config.dart').readAsString();
        expect(config, contains('package:orm/drivers/sqlite.dart'));
        expect(config, isNot(contains('package:orm/orm.dart')));
        expect(
          (await report(fixture, ['migrate', 'check']))['migrations'],
          isEmpty,
        );
        expect(await fixture.file('app.sqlite').exists(), false);

        await fixture.write(
          'lib/schema.dart',
          declaration.replaceFirst(
            'required final String title,',
            'required final String title,\n  required final String? detail,',
          ),
        );
        expect(
          (await report(fixture, ['generate']))['generated'],
          'lib/schema.orm.dart',
        );
        final first = await report(fixture, [
          'migrate',
          'create',
          '0001_initial',
        ]);
        expect(first['created'], contains('m0001_initial.dart'));
        final initial = fixture.file('migrations/m0001_initial.dart');
        final initialSource = await initial.readAsString();
        expect(initialSource, contains('detail'));
        expect(initialSource, isNot(contains('lib/schema.dart')));
        expect((await report(fixture, ['migrate', 'check']))['valid'], true);
        await run(fixture, ['migrate', 'plan'], code: 1);
        expect(await fixture.file('app.sqlite').exists(), false);
        expect((await report(fixture, ['migrate', 'apply']))['applied'], [
          '0001_initial',
        ]);
        expect(
          (await report(fixture, ['migrate', 'status']))['applied'],
          hasLength(1),
        );
        expect((await report(fixture, ['migrate', 'verify']))['matches'], true);

        final firstSnapshot = await fixture
            .file('lib/schema.snapshot.dart')
            .readAsString();
        await fixture.write(
          'lib/schema.dart',
          declaration.replaceFirst(
            'required final String title,',
            'required final String title,\n  required final String? detail,\n  required final String? label,',
          ),
        );
        // No explicit generate: create must use the edited model, not the config's
        // previously compiled snapshot.
        await report(fixture, ['migrate', 'create', '0002_label']);
        expect(
          await fixture.file('lib/schema.snapshot.dart').readAsString(),
          isNot(firstSnapshot),
        );
        expect(
          (await report(fixture, ['migrate', 'plan']))['pending'],
          hasLength(1),
        );
        expect(
          (await report(fixture, ['migrate', 'verify'], code: 2))['matches'],
          false,
        );
        expect((await report(fixture, ['migrate', 'apply']))['applied'], [
          '0002_label',
        ]);
        expect((await report(fixture, ['migrate', 'verify']))['matches'], true);
        expect(
          (await report(fixture, [
            'migrate',
            'create',
            '0003_same',
          ]))['created'],
          isNull,
        );
        expect(await initial.readAsString(), initialSource);

        await run(fixture, ['init', '--database', 'sqlite'], code: 64);
        expect(await fixture.file('orm.config.dart').readAsString(), config);
        expect(await initial.readAsString(), initialSource);
      } finally {
        await fixture.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  for (final engine in ['postgres', 'mysql', 'mariadb']) {
    test(
      '$engine init and history validation need no credentials or connection',
      () async {
        final fixture = await project();
        try {
          await report(fixture, ['init', '--database', engine]);
          final registry = await fixture
              .file('migrations/migrations.g.dart')
              .readAsString();
          expect(registry, contains('SqlDialect.$engine'));
          final config = await fixture.file('orm.config.dart').readAsString();
          expect(config, contains('package:orm/drivers/$engine.dart'));
          expect(
            (await report(fixture, ['migrate', 'check']))['dialect'],
            engine,
          );
          await report(fixture, ['generate']);
          final created = await report(fixture, [
            'migrate',
            'create',
            '0001_initial',
          ]);
          expect(created['created'], contains('m0001_initial.dart'));
          expect(
            await fixture.file('migrations/m0001_initial.dart').readAsString(),
            contains('dialect: SqlDialect.$engine'),
          );
          await report(fixture, ['migration', 'registry', 'migrations']);
          expect((await report(fixture, ['migrate', 'check']))['migrations'], [
            '0001_initial',
          ]);
          final missing = await run(fixture, [
            'migrate',
            'status',
            '--json',
          ], code: 64);
          expect(
            '${missing.stderr}',
            contains('DATABASE_URL is empty or missing'),
          );
        } finally {
          await fixture.dispose();
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'help, invalid options and existing files fail without partial scaffolding',
    () async {
      final fixture = await project();
      try {
        final help = await run(fixture, ['help', 'migrate']);
        expect('${help.stdout}', contains('migrate <command>'));
        expect('${help.stdout}', contains('apply'));
        final invalid = await run(fixture, [
          'init',
          '--database',
          'unknown',
          '--json',
        ], code: 64);
        expect(
          // Dart's native-asset hook writes startup diagnostics to stderr.
          jsonDecode(
            (invalid.stderr as String).substring(
              (invalid.stderr as String).indexOf('{"error"'),
            ),
          ),
          containsPair('exitCode', 64),
        );
        await run(fixture, [
          'init',
          '--database',
          'sqlite',
          '--unexpected',
        ], code: 64);
        await run(fixture, ['migrate', 'check'], code: 64);
        await fixture.write('lib/schema.dart', '// User-owned source.\n');
        await run(fixture, ['init', '--database', 'sqlite'], code: 64);
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
      } finally {
        await fixture.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
