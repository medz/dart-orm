@Tags(['core'])
library;

import 'dart:io';

import 'package:orm/generate.dart';
import 'package:orm/migrate.dart';
import 'package:orm/src/cli/config_entrypoint.dart';
import 'package:orm/src/cli/runner.dart';
import 'package:test/test.dart';

import 'support/cli.dart';

void main() {
  late Directory temporary;
  late ProjectConfig config;
  late bool connected;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('orm-config-history-');
    connected = false;
    config = ProjectConfig(
      database: .sqlite,
      models: '${temporary.path}/missing-models.dart',
      migrations: '${temporary.path}/migrations',
      connect: ({required readOnly}) {
        connected = true;
        throw StateError('An offline or invalid command opened a connection.');
      },
    );
  });
  tearDown(() async {
    expect(connected, false);
    await temporary.delete(recursive: true);
  });

  Future<CliResult> run(List<String> command, {MigrationHistory? history}) =>
      captureCli(
        () => runOrmCommand(
          ['migrate', ...command, '--json'],
          config: config,
          history: history,
        ),
      );

  Migration migration({bool extra = false}) =>
      Migration.create('0001_initial', [
        TableSchema(
          'items',
          columns: [
            Column('id', Codecs.integer),
            if (extra) Column('label', Codecs.text.nullable()),
          ],
          primaryKey: ['id'],
        ),
      ], dialect: .sqlite);

  test(
    'missing model and history sources allow an offline empty check',
    () async {
      final result = await run(['check']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(cliReport(result), {
        'valid': true,
        'dialect': 'sqlite',
        'migrations': <String>[],
      });
      expect(await Directory(config.migrations).exists(), false);
      expect(await File(config.models).exists(), false);
    },
  );

  test(
    'migration files without a registry are never treated as empty',
    () async {
      final file = File('${config.migrations}/m0001_initial.dart');
      await file.parent.create(recursive: true);
      await file.writeAsString(migrationSource(migration()));
      final result = await run(['apply']);
      expect(result.exitCode, 64, reason: result.stderr);
      expect(result.stderr, contains('without a registry'));
      expect(
        await File('${config.migrations}/migrations.g.dart').exists(),
        false,
      );
    },
  );

  test('registry membership is checked before connecting', () async {
    final first = migration();
    await writeMigration(
      first,
      directory: config.migrations,
      history: MigrationHistory([], dialect: .sqlite),
    );
    final empty = await run([
      'apply',
    ], history: MigrationHistory([], dialect: .sqlite));
    expect(empty.exitCode, 64, reason: empty.stderr);
    expect(empty.stderr, contains('registry is stale'));

    await File('${config.migrations}/m0002_extra.dart')
        .writeAsString('// Not registered.');
    final extra = await run([
      'status',
    ], history: MigrationHistory([(first, first.checksum)], dialect: .sqlite));
    expect(extra.exitCode, 64, reason: extra.stderr);
    expect(extra.stderr, contains('registry is stale'));
  });

  test(
    'fixed history engine is checked before connecting even when empty',
    () async {
      final result = await run([
        'apply',
      ], history: MigrationHistory([], dialect: .postgres));
      expect(result.exitCode, 64, reason: result.stderr);
      expect(result.stderr, contains('fixed migration history engine'));
    },
  );

  test(
    'a non-file registry and unrecognized Dart migration fail closed',
    () async {
      await Directory('${config.migrations}/migrations.g.dart')
          .create(recursive: true);
      final registry = await run([
        'check',
      ], history: MigrationHistory([], dialect: .sqlite));
      expect(registry.exitCode, 64, reason: registry.stderr);
      expect(registry.stderr, contains('regular migration registry'));
      await Directory('${config.migrations}/migrations.g.dart').delete();
      await File('${config.migrations}/unregistered.dart').writeAsString('');
      final file = await run(['check']);
      expect(file.exitCode, 64, reason: file.stderr);
      expect(file.stderr, contains('regular m<id>.dart migration'));
    },
  );

  test(
    'record may update the latest reviewed fingerprint without current models',
    () async {
      final original = migration();
      await writeMigration(
        original,
        directory: config.migrations,
        history: MigrationHistory([], dialect: .sqlite),
      );
      final changed = migration(extra: true);
      final source = File('${config.migrations}/m0001_initial.dart');
      await source.writeAsString(
        migrationSource(changed)
            .replaceFirst(changed.checksum, original.checksum),
      );
      final history = MigrationHistory([
        (changed, original.checksum),
      ], dialect: .sqlite);
      final rejected = await run(['check'], history: history);
      expect(rejected.exitCode, 1, reason: rejected.stderr);
      expect(rejected.stderr, contains('differs from its recorded'));
      final recorded = await run(['record', changed.id], history: history);
      expect(recorded.exitCode, 0, reason: recorded.stderr);
      expect(cliReport(recorded), {
        'recorded': changed.id,
        'checksum': changed.checksum,
      });
      expect(await source.readAsString(), contains(changed.checksum));
      final checked = await run(
        ['check'],
        history: MigrationHistory([
          (changed, changed.checksum),
        ], dialect: .sqlite),
      );
      expect(checked.exitCode, 0, reason: checked.stderr);
      expect(await File(config.models).exists(), false);
    },
  );
}
