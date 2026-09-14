import 'dart:io';

import 'package:orm/generate.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      arguments.first != 'generate' ||
      arguments.length < 2 ||
      arguments.length > 3) {
    stderr.writeln(
      'Usage: dart run orm generate <schema.dart> [output.orm.dart]',
    );
    exitCode = 64;
    return;
  }
  try {
    await writeGeneratedSchema(
      arguments[1],
      output: arguments.length == 3 ? arguments[2] : null,
    );
    stdout.writeln(
      'Generated ${arguments.length == 3 ? arguments[2] : arguments[1].replaceFirst(RegExp(r'\.dart$'), '.orm.dart')}',
    );
  } on GenerationException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}
