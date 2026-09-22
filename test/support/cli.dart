import 'dart:convert';
import 'dart:io';

import 'package:orm/src/cli/config.dart';
import 'package:orm/src/cli/runner.dart';

typedef CliResult = ({int exitCode, String stdout, String stderr});

Future<CliResult> runCli(List<String> args, {OrmConfig? config}) =>
    captureCli(() => runOrmCommand(args, config: config));

// Command tests share the VM, so never change Directory.current or io.exitCode.
// IOOverrides captures output within this invocation's async zone.
Future<CliResult> captureCli(Future<int> Function() command) async {
  final output = _Output();
  final errors = _Output();
  final code = await IOOverrides.runZoned(
    command,
    stdout: () => output,
    stderr: () => errors,
  );
  return (
    exitCode: code,
    stdout: output.buffer.toString(),
    stderr: errors.buffer.toString(),
  );
}

Map<String, Object?> cliReport(CliResult result) =>
    jsonDecode(result.stdout) as Map<String, Object?>;

final class _Output implements Stdout {
  final buffer = StringBuffer();
  @override
  void write(Object? object) => buffer.write(object);
  @override
  void writeln([Object? object = '']) => buffer.writeln(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
