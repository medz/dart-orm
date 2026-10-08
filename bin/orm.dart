import 'dart:io';

import 'package:orm/database.dart';
import 'package:orm/dev.dart';

const _usage =
    'Usage: dart run bin/orm.dart generate --schema path --out path '
    '--name AppDatabase --engine sqlite|postgresql [--check]';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty || arguments.contains('--help')) {
      stdout.writeln(_usage);
      return;
    }
    if (arguments.first != 'generate') {
      throw const FormatException('Expected generate command.');
    }
    final options = <String, String>{};
    var check = false;
    for (var index = 1; index < arguments.length; index++) {
      final key = arguments[index];
      if (key == '--check') {
        if (check) throw const FormatException('Duplicate --check.');
        check = true;
        continue;
      }
      if (!{'--schema', '--out', '--name', '--engine'}.contains(key) ||
          index + 1 == arguments.length ||
          arguments[index + 1].startsWith('--') ||
          options.containsKey(key)) {
        throw FormatException('Invalid or duplicate option $key.');
      }
      options[key] = arguments[++index];
    }
    final schema = options['--schema'];
    final output = options['--out'];
    final engine = switch (options['--engine']) {
      'sqlite' => Engine.sqlite,
      'postgresql' => Engine.postgresql,
      _ => throw const FormatException(
        '--engine must be sqlite or postgresql.',
      ),
    };
    if (schema == null || output == null) {
      throw const FormatException('--schema and --out are required.');
    }
    final sources = await generateSchema(
      schemaPath: schema,
      outputPath: output,
      databaseName: options['--name'] ?? 'AppDatabase',
      engine: engine,
    );
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
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(_usage);
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 74;
  }
}
