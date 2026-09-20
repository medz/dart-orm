import 'dart:convert';
import 'dart:io';

import 'src/build_fixture.dart';

Future<void> main(List<String> args) async {
  final output = args.isEmpty
      ? '.dart_tool/benchmarks/generation.json'
      : args.single;
  final versions = await packageVersions();
  final results = <Map<String, Object?>>[];
  for (final models in [10, 100, 1000]) {
    print('Measuring $models models...');
    final fixture = await BuildFixture.create(
      ormPath: Directory.current.path,
      models: models,
    );
    BuildWatch? watcher;
    try {
      final cold = await fixture.run(['run', 'build_runner', 'build']);
      final unchanged = await fixture.run(['run', 'build_runner', 'build']);
      if (!unchanged.output.contains('wrote 0 outputs')) {
        throw StateError('Unchanged build rewrote outputs.');
      }
      final start = Stopwatch()..start();
      watcher = await fixture.watch();
      await watcher.next();
      final watchStart = start.elapsedMilliseconds;
      Future<int> edit(String file, String contents) async {
        final elapsed = Stopwatch()..start();
        await fixture.write(file, contents);
        await watcher!.next();
        return elapsed.elapsedMilliseconds;
      }

      final field = await edit(
        'lib/schema.dart',
        BuildFixture.schema(models, extra: true),
      );
      final imported = await edit(
        'lib/models.dart',
        BuildFixture.domain(label: 'changed', defaultScore: 9),
      );
      final client = fixture.file('lib/schema.orm.dart');
      final before = (await client.stat()).modified;
      await fixture.write('lib/unrelated.dart', 'const unrelated = 2;\n');
      await watcher.quiet();
      if ((await client.stat()).modified != before) {
        throw StateError('Unrelated edit rewrote client.');
      }
      await watcher.close();
      watcher = null;
      final analysis = await fixture.run(['analyze', 'lib']);
      final snapshotSource = await fixture
          .file('lib/schema.snapshot.dart')
          .readAsString();
      if (RegExp(r'TableSchema\(').allMatches(snapshotSource).length !=
          models) {
        throw StateError('Incorrect table count in generated Dart snapshot.');
      }
      final value = <String, Object?>{
        'models': models,
        'builder_mode': RegExp(r'Built with build_runner/(\w+)')
            .firstMatch(cold.output)
            ?.group(1),
        'schema_bytes': await fixture.file('lib/schema.dart').length(),
        'generated_dart_bytes': await client.length(),
        'snapshot_dart_bytes': await fixture
            .file('lib/schema.snapshot.dart')
            .length(),
        'cold_build_ms': cold.milliseconds,
        'no_change_build_ms': unchanged.milliseconds,
        'watch_start_ms': watchStart,
        'watch_field_edit_ms': field,
        'watch_import_edit_ms': imported,
        'unrelated_edit_triggered_build': false,
        'unrelated_observation_ms': 1000,
        'analyze_ms': analysis.milliseconds,
      };
      results.add(value);
      print(jsonEncode(value));
    } finally {
      await watcher?.close();
      await fixture.dispose();
    }
  }
  final cpu = Platform.isMacOS
      ? (await Process.run('sysctl', [
          '-n',
          'machdep.cpu.brand_string',
        ])).stdout.toString().trim()
      : null;
  final report = {
    'recorded_at_utc': DateTime.now().toUtc().toIso8601String(),
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'cpu': cpu,
    'logical_processors': Platform.numberOfProcessors,
    'packages': versions,
    'method': 'One sample per case in a fresh consumer package; dependency download excluded; shared SDK/pub/native caches warm. Timings include process startup or filesystem watch detection as applicable. No p50/p95 claim.',
    'results': results,
  };
  final file = File(output);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  print('Saved $output');
}

Future<Map<String, String?>> packageVersions() async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, Object?>;
  final packages = (config['packages'] as List<Object?>)
      .cast<Map<String, Object?>>();
  final result = <String, String?>{};
  for (final name in ['build_runner', 'build', 'dart_style', 'analyzer']) {
    final entry = packages.singleWhere((entry) => entry['name'] == name);
    final root = Directory.fromUri(
      configFile.uri.resolve(entry['rootUri'] as String),
    );
    final file = File.fromUri(root.uri.resolve('pubspec.yaml'));
    result[name] = RegExp(
      r'^version: ([^\r\n]+)',
      multiLine: true,
    ).firstMatch(await file.readAsString())?.group(1);
  }
  return result;
}
