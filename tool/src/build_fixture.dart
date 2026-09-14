import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A disposable consumer package used by process tests and generation benchmarks.
final class BuildFixture {
  final Directory directory;
  BuildFixture._(this.directory);

  static Future<BuildFixture> create({
    required String ormPath,
    int models = 1,
  }) async {
    final result = BuildFixture._(
      await Directory.systemTemp.createTemp('orm-build-'),
    );
    await result.write('pubspec.yaml', '''
name: orm_build_fixture
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  orm:
    path: ${jsonEncode(ormPath)}
dev_dependencies:
  build_runner: ^2.16.1
''');
    await result.write('build.yaml', '''
targets:
  \$default:
    builders:
      orm:orm:
        enabled: true
        generate_for:
          - lib/schema.dart
''');
    await result.write('lib/models.dart', domain());
    await result.write('lib/schema.dart', schema(models));
    await result.write('lib/unrelated.dart', 'const unrelated = 1;\n');
    try {
      await result.run(['pub', 'get', '--offline']);
      return result;
    } catch (_) {
      await result.dispose();
      rethrow;
    }
  }

  static String domain({String label = 'waiting', int defaultScore = 0}) =>
      '''
import 'package:orm/schema.dart';
const defaultScore = '$defaultScore';
enum Status { @EnumValue('$label') pending, ready }
''';

  static String schema(
    int models, {
    bool extra = false,
    bool invalid = false,
  }) =>
      '''
import 'package:orm/schema.dart';
import 'models.dart';
${[for (var i = 0; i < models; i++) '''
typedef Row$i = ({@Id.generated() int id, String title, @Default.sql(defaultScore) int score, Status status${extra && i == 0 ? ', bool enabled' : ''}});
final rows$i = entity<Row$i>(table: 'rows_$i');
'''].join()}
${invalid ? 'int invalid = "not an integer";' : ''}
''';

  File file(String path) => File('${directory.path}/$path');
  Future<void> write(String path, String contents) async {
    final output = file(path);
    await output.parent.create(recursive: true);
    await output.writeAsString(contents, flush: true);
  }

  Future<({int milliseconds, String output})> run(List<String> args) async {
    final watch = Stopwatch()..start();
    final result = await Process.run(
      Platform.resolvedExecutable,
      args,
      workingDirectory: directory.path,
    );
    final output = '${result.stdout}\n${result.stderr}';
    if (result.exitCode != 0) {
      throw StateError(
        'dart ${args.join(' ')} failed (${result.exitCode}):\n$output',
      );
    }
    return (milliseconds: watch.elapsedMilliseconds, output: output);
  }

  Future<BuildWatch> watch() => BuildWatch.start(directory.path);
  Future<void> dispose() => directory.delete(recursive: true);
}

final class BuildWatch {
  final Process process;
  final List<String> _log = [];
  final List<String> _builds = [];
  final List<StreamSubscription<String>> _subscriptions = [];
  Completer<void>? _changed;
  int _next = 0;
  int? _exitCode;
  BuildWatch._(this.process) {
    for (final stream in [process.stdout, process.stderr]) {
      _subscriptions.add(
        stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
          line,
        ) {
          _log.add(line);
          if (_log.length > 100) _log.removeAt(0);
          if (line.contains('Built with build_runner') ||
              line.contains('Failed to build with build_runner')) {
            _builds.add(line);
            _notify();
          }
        }),
      );
    }
    unawaited(
      process.exitCode.then((code) {
        _exitCode = code;
        _notify();
      }),
    );
  }

  static Future<BuildWatch> start(String directory) async => BuildWatch._(
    await Process.start(Platform.resolvedExecutable, [
      'run',
      'build_runner',
      'watch',
    ], workingDirectory: directory),
  );
  void _notify() {
    _changed?.complete();
    _changed = null;
  }

  Future<String> next({bool success = true}) async {
    while (_builds.length <= _next) {
      if (_exitCode != null) {
        throw StateError('Watcher exited ($_exitCode):\n${_log.join('\n')}');
      }
      await (_changed ??= Completer<void>()).future.timeout(
        const Duration(minutes: 2),
        onTimeout: () =>
            throw StateError('Build did not finish:\n${_log.join('\n')}'),
      );
    }
    final result = _builds[_next++];
    if (result.contains('Failed to build') == success) {
      throw StateError('Unexpected build outcome:\n${_log.join('\n')}');
    }
    return result;
  }

  Future<void> close() async {
    process.kill(ProcessSignal.sigint);
    await process.exitCode.timeout(const Duration(seconds: 15));
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> quiet({Duration duration = const Duration(seconds: 1)}) async {
    final count = _builds.length;
    await Future<void>.delayed(duration);
    if (_builds.length != count || _exitCode != null) {
      throw StateError('Watcher did not remain idle:\n${_log.join('\n')}');
    }
  }
}
