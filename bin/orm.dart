import 'dart:io';

import 'package:orm/database.dart';
import 'package:orm/dev.dart';

const _usage = '''Usage:
  dart run orm generate --schema path --out path --name AppDatabase --engine sqlite|postgresql [--check]
  dart run orm migration draft --to snapshot.dart [--from previous.dart] --out migration.dart --version 1 --name initial
''';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty || arguments.contains('--help')) {
      stdout.write(_usage);
      return;
    }
    if (arguments.first == 'generate') {
      await _generate(arguments.skip(1).toList());
    } else if (arguments.length >= 2 &&
        arguments[0] == 'migration' &&
        arguments[1] == 'draft') {
      await _draft(arguments.skip(2).toList());
    } else {
      throw const FormatException('Expected generate or migration draft.');
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.write(_usage);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('${error.message}: ${error.path}');
    exitCode = 74;
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
  }
}

Map<String, String> _options(List<String> arguments, Set<String> allowed) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final key = arguments[index];
    if (!allowed.contains(key) || options.containsKey(key)) {
      throw FormatException('Invalid or duplicate option $key.');
    }
    if (key == '--check') {
      options[key] = '';
    } else {
      if (index + 1 == arguments.length ||
          arguments[index + 1].startsWith('--')) {
        throw FormatException('Missing value for $key.');
      }
      options[key] = arguments[++index];
    }
  }
  return options;
}

String _required(Map<String, String> options, String name) =>
    options[name] ?? (throw FormatException('$name is required.'));

Future<void> _generate(List<String> arguments) async {
  final options = _options(arguments, {
    '--schema',
    '--out',
    '--name',
    '--engine',
    '--check',
  });
  final schema = _required(options, '--schema');
  final output = _required(options, '--out');
  final engine = switch (options['--engine']) {
    'sqlite' => Engine.sqlite,
    'postgresql' => Engine.postgresql,
    _ => throw const FormatException('--engine must be sqlite or postgresql.'),
  };
  final sources = await generateSchema(
    schemaPath: schema,
    outputPath: output,
    databaseName: options['--name'] ?? 'AppDatabase',
    engine: engine,
  );
  final check = options.containsKey('--check');
  final matches = await writeGeneratedSources(
    sources: sources,
    outputPath: output,
    check: check,
  );
  if (!matches) {
    stderr.writeln(
      'Generated sources have drifted: $output, ${snapshotPath(output)}',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln(
    check
        ? 'Generated sources are current.'
        : 'Generated $output and ${snapshotPath(output)}.',
  );
}

Future<void> _draft(List<String> arguments) async {
  final options = _options(arguments, {
    '--from',
    '--to',
    '--out',
    '--version',
    '--name',
  });
  final output = _required(options, '--out');
  final version = int.tryParse(_required(options, '--version'));
  if (version == null || version < 1) {
    throw const FormatException('--version must be a positive integer.');
  }
  final name = _required(options, '--name');
  final after = await readSnapshot(_required(options, '--to'));
  final previous = options['--from'];
  await draftMigration(
    before: previous == null ? null : await readSnapshot(previous),
    after: after,
    version: version,
    name: name,
    outputPath: output,
  );
  stdout.writeln(
    'Drafted $output. Review the SQL and register migration with a static import.',
  );
}
