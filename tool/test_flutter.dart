import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const applicationId = 'dev.orm.orm_flutter';

/// Install two built APKs on a dedicated emulator, then restart the upgraded app.
/// Refuses physical devices and an already-installed acceptance application.
Future<void> main(List<String> args) async {
  if (args.length != 4 || !RegExp(r'^emulator-\d+$').hasMatch(args[1])) {
    throw ArgumentError(
      'Usage: dart run tool/test_flutter.dart '
      '<adb> <emulator-PORT> <legacy.apk> <current.apk>',
    );
  }
  final [adb, device, legacy, current] = args;
  Future<ProcessResult> command(
    List<String> arguments, {
    bool checked = true,
  }) async {
    final result = await Process.run(adb, ['-s', device, ...arguments]);
    if (checked && result.exitCode != 0) {
      throw StateError(
        'adb ${arguments.join(' ')}: ${result.stdout}${result.stderr}',
      );
    }
    return result;
  }

  final installed = await command([
    'shell',
    'pm',
    'path',
    applicationId,
  ], checked: false);
  if (installed.exitCode != 0 && installed.exitCode != 1) {
    throw StateError('Cannot inspect installation: ${installed.stderr}');
  }
  if ('${installed.stdout}'.contains('package:')) {
    throw StateError(
      'Use a fresh dedicated emulator or explicitly uninstall '
      'only $applicationId from your test emulator before rerunning.',
    );
  }
  if ('${(await command(['shell', 'getprop', 'ro.kernel.qemu'])).stdout}'
          .trim() !=
      '1') {
    throw StateError('The selected device is not an emulator.');
  }
  final artifacts = Directory('.dart_tool/flutter')
    ..createSync(recursive: true);
  await command(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
  await command(['shell', 'wm', 'dismiss-keyguard']);
  final phases = <Map<String, Object?>>[];
  for (final (phase, apk) in [
    ('legacy', legacy),
    ('upgrade', current),
    ('reopen', null),
  ]) {
    await command(['shell', 'am', 'force-stop', applicationId]);
    if (apk != null) {
      await command(['install', if (phase == 'upgrade') '-r', apk]);
    }
    // This runner exclusively owns the selected test emulator.
    await command(['logcat', '-c']);
    await command([
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$applicationId/.MainActivity',
      '--es',
      'orm_phase',
      phase,
    ]);
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    Map<String, Object?>? report;
    while (report == null) {
      final output =
          '${(await command(['logcat', '-d', '-v', 'raw', '-s', 'flutter:I'])).stdout}';
      await File('${artifacts.path}/$phase.log').writeAsString(output);
      final chunks = <int, String>{};
      var expected = 0;
      for (final match in RegExp(
        'ORM_ACCEPTANCE $phase (\\d+)/(\\d+) ([A-Za-z0-9+/=]+)',
      ).allMatches(output)) {
        final index = int.parse(match[1]!);
        final count = int.parse(match[2]!);
        if (expected != 0 && expected != count) {
          throw StateError('Conflicting report chunks');
        }
        expected = count;
        if (chunks[index] != null && chunks[index] != match[3]) {
          throw StateError('Conflicting report content');
        }
        chunks[index] = match[3]!;
      }
      if (expected > 0 &&
          chunks.length == expected &&
          List.generate(expected, (i) => i + 1).every(chunks.containsKey)) {
        report = jsonDecode(
          utf8.decode(
            base64Decode(
              [for (var i = 1; i <= expected; i++) chunks[i]!].join(),
            ),
          ),
        ) as Map<String, Object?>;
      } else {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError(
            '$phase report timed out; see ${artifacts.path}/$phase.log',
          );
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    await File('${artifacts.path}/$phase.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    if (report['status'] != 'passed' ||
        report['phase'] != phase ||
        report['release'] != (phase != 'legacy')) {
      throw StateError('$phase failed: ${jsonEncode(report)}');
    }
    final pid = '${(await command(['shell', 'pidof', applicationId])).stdout}'
        .trim();
    if (pid != '${report['pid']}') {
      throw StateError('Report process does not match running app');
    }
    final packageInfo =
        '${(await command(['shell', 'dumpsys', 'package', applicationId])).stdout}';
    final versionCode = RegExp(r'versionCode=(\d+)')
        .firstMatch(packageInfo)?[1];
    if (versionCode != (phase == 'legacy' ? '1' : '2')) {
      throw StateError('Unexpected installed APK version: $versionCode');
    }
    report['apkVersionCode'] = int.parse(versionCode!);
    phases.add(report);
    stdout.writeln(
      '$phase: ${(report['checks'] as List).length} checks passed (PID $pid)',
    );
  }
  if (phases.map((p) => p['pid']).toSet().length != 3 ||
      phases.map((p) => p['path']).toSet().length != 1 ||
      jsonEncode(phases[1]['rows']) != jsonEncode(phases[2]['rows']) ||
      jsonEncode(phases[1]['history']) != jsonEncode(phases[2]['history'])) {
    throw StateError(
      'Process, database path, row or history continuity failed',
    );
  }
  // The report precedes setState in the app; let Android's activity fade finish.
  await Future<void>.delayed(const Duration(seconds: 1));
  final screenshot = await Process.run(adb, [
    '-s',
    device,
    'exec-out',
    'screencap',
    '-p',
  ], stdoutEncoding: null);
  if (screenshot.exitCode != 0) throw StateError('${screenshot.stderr}');
  final screenshotFile = File('.dart_tool/flutter/flutter-android.png');
  await screenshotFile.writeAsBytes(screenshot.stdout as List<int>);
  final sources = <String, String>{};
  for (final directory in [
    'lib',
    'example/flutter/lib',
    'example/flutter/assets',
    'example/flutter/android/app/src/main',
  ]) {
    for (final entry in Directory(
      directory,
    ).listSync(recursive: true).whereType<File>()) {
      if (entry.path.endsWith('/GeneratedPluginRegistrant.java')) continue;
      sources[entry.path] = (await sha256.bind(entry.openRead()).first)
          .toString();
    }
  }
  for (final path in [
    'tool/test_flutter.dart',
    'example/flutter/pubspec.yaml',
    'example/flutter/pubspec.lock',
    'example/flutter/.metadata',
    'example/flutter/android/app/build.gradle.kts',
    'example/flutter/android/settings.gradle.kts',
    'example/flutter/android/gradle/wrapper/gradle-wrapper.properties',
  ]) {
    sources[path] = (await sha256.bind(File(path).openRead()).first).toString();
  }
  final git = await Process.run('git', ['rev-parse', 'HEAD']);
  if (git.exitCode != 0) throw StateError('${git.stderr}');
  final properties = await File('example/flutter/android/local.properties')
      .readAsLines();
  final sdk = properties
      .singleWhere((line) => line.startsWith('flutter.sdk='))
      .substring('flutter.sdk='.length);
  final flutter = jsonDecode(
    await File('$sdk/bin/cache/flutter.version.json').readAsString(),
  ) as Map<String, Object?>;
  final result = {
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'runtimeSourceCommit': '${git.stdout}'.trim(),
    'flutter': {
      for (final key in [
        'frameworkVersion',
        'channel',
        'frameworkRevision',
        'engineRevision',
        'dartSdkVersion',
      ])
        key: flutter[key],
    },
    'device': device,
    'abi':
        '${(await command(['shell', 'getprop', 'ro.product.cpu.abi'])).stdout}'
            .trim(),
    'buildFingerprint':
        '${(await command(['shell', 'getprop', 'ro.build.fingerprint'])).stdout}'
            .trim(),
    'apkSha256': {
      for (final (name, path) in [('legacy', legacy), ('current', current)])
        name: (await sha256.bind(File(path).openRead()).first).toString(),
    },
    'sourceSha256': sources,
    'screenshotSha256': (await sha256.bind(screenshotFile.openRead()).first)
        .toString(),
    'phases': phases,
    'limits': [
      'Android arm64 API ${phases.first['androidApi']} emulator; not physical hardware, iOS or macOS Flutter.',
      'Legacy APK debug; upgraded/restarted APK release AOT.',
      'Frame and timer progress demonstrate worker separation, not an FPS benchmark.',
      'Force-stop/relaunch is process persistence evidence, not power-loss testing.',
    ],
  };
  await File('.dart_tool/flutter/flutter.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
  stdout.writeln(
    'Report: .dart_tool/flutter/flutter.json; screenshot: ${screenshotFile.path}',
  );
}
