import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:orm/src/sqlite/web_build.dart';

import 'src/browser_profile.dart';

/// Release Flutter acceptance against an unchanged copy of the product package.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Pass the absolute path to the Flutter SDK.');
  }
  final root = Directory.current.absolute;
  final sdk = Directory(arguments.single).absolute;
  final flutter = '${sdk.path}/bin/flutter';
  final work = Directory('${root.path}/.dart_tool/flutter_web_test');
  if (await work.exists()) await work.delete(recursive: true);
  final package = Directory('${work.path}/orm');
  final app = Directory('${work.path}/app');
  await app.create(recursive: true);
  await package.create(recursive: true);

  Future<void> copyTree(String source, String destination) async {
    final from = Directory(source);
    for (final entry in from.listSync(recursive: true)) {
      if (entry is! File) continue;
      final target = File(
        '$destination/${entry.path.substring(source.length + 1)}',
      );
      await target.parent.create(recursive: true);
      await entry.copy(target.path);
    }
  }

  Future<void> write(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  Future<void> run(String executable, List<String> args, String cwd) async {
    stdout.writeln('Running: ${[executable, ...args].join(' ')}');
    final result = await Process.run(executable, args, workingDirectory: cwd);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) throw StateError('Command failed: $args');
  }

  await copyTree('${root.path}/lib', '${package.path}/lib');
  await File('${root.path}/pubspec.yaml').copy('${package.path}/pubspec.yaml');
  await copyTree('${root.path}/assets', '${package.path}/assets');
  await run('${sdk.path}/bin/cache/dart-sdk/bin/dart', [
    'run',
    'tool/build_sqlite_web.dart',
    '--check',
  ], root.path);
  await write('${app.path}/pubspec.yaml', '''
name: orm_flutter_web_test
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  orm:
    path: ../orm
  sqlite3: 3.6.0
  web: ^1.1.1
flutter:
  uses-material-design: true
''');
  for (final relative in [
    'test/support/browser',
    'test/support/temporal_precision',
    'example/teams',
  ]) {
    await copyTree('${root.path}/$relative', '${app.path}/lib/$relative');
  }
  final checksFile = File('${app.path}/lib/test/support/browser/main.dart');
  var checks = await checksFile.readAsString();
  String replace(String source, String from, String to) {
    if (!source.contains(from)) {
      throw StateError('Browser fixture changed: $from');
    }
    return source.replaceFirst(from, to);
  }

  checks += '\nint Function() flutterFrames = () => 0;\n';
  checks = replace(
    checks,
    'var ticks = 0;',
    'final beforeFrames = flutterFrames();\n        var ticks = 0;',
  );
  checks = replace(
    checks,
    "expect(ticks > 0, 'Main event loop was blocked');",
    "expect(ticks > 0, 'Main event loop was blocked');\n"
        "          expect(flutterFrames() > beforeFrames, 'Flutter animation stopped during SQL');",
  );
  checks = replace(
    checks,
    "location.replace('/?phase=recover')",
    "location.replace('/nested/detail/42?phase=recover')",
  );
  checks = replace(
    checks,
    "result['browser'] = web.window.navigator.userAgent;",
    "result['browser'] = web.window.navigator.userAgent;\n"
        "  result['actualWasm'] = const bool.fromEnvironment('dart.tool.dart2wasm');\n"
        "  result['flutterFrames'] = flutterFrames();\n"
        "  result['baseUri'] = web.document.baseURI;\n"
        "  result['dartUriBase'] = Uri.base.toString();\n"
        "  result['isolated'] = web.window.crossOriginIsolated;",
  );
  checks = replace(
    checks,
    'web.document.body!.textContent = body;',
    '// Keep the Flutter widget tree mounted.',
  );
  await checksFile.writeAsString(checks);
  await write('${app.path}/lib/main.dart', _flutterMain);
  await write('${app.path}/web/index.html', '''
<!DOCTYPE html><html><head><base href="\$FLUTTER_BASE_HREF">
<meta charset="UTF-8"><title>ORM Flutter Web probe</title></head>
<body><script src="flutter_bootstrap.js" async></script></body></html>
''');
  await run(flutter, ['pub', 'get', '--offline'], app.path);
  final reports = <Map<String, Object?>>[];
  for (final mode in ['js', 'wasm']) {
    await run(flutter, [
      'build',
      'web',
      '--release',
      '--no-pub',
      '--base-href',
      '/nested/',
      '--no-web-resources-cdn',
      if (mode == 'wasm') '--wasm',
    ], app.path);
    final output = Directory('${app.path}/build/web');
    for (final isolated in mode == 'js' ? [false] : [false, true]) {
      final report = await _serve(output, isolated);
      report['build'] = mode;
      report['expectedIsolation'] = isolated;
      report['flutterSdk'] = jsonDecode(
        await File('${sdk.path}/bin/cache/flutter.version.json').readAsString(),
      );
      report['sqliteWasmSha256'] = sqliteWasmSha256;
      reports.add(report);
      stdout.writeln(jsonEncode(report));
      await write(
        '${work.path}/report.json',
        '${const JsonEncoder.withIndent('  ').convert(reports)}\n',
      );
      if (report['passed'] != true ||
          report['actualWasm'] != (mode == 'wasm') ||
          report['isolated'] != isolated) {
        throw StateError('Flutter Web probe failed.');
      }
    }
  }
}

Future<Map<String, Object?>> _serve(Directory output, bool isolated) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final complete = Completer<Map<String, Object?>>();
  final requests = <String>[];
  server.listen((request) async {
    try {
      final path = request.uri.path;
      requests.add(path);
      if (isolated) {
        request.response.headers.set(
          'Cross-Origin-Opener-Policy',
          'same-origin',
        );
        request.response.headers.set(
          'Cross-Origin-Embedder-Policy',
          'require-corp',
        );
      }
      if (path == '/report' && request.method == 'POST') {
        final body = await utf8.decoder.bind(request).join();
        if (!complete.isCompleted) {
          complete.complete(jsonDecode(body) as Map<String, Object?>);
        }
        request.response.write('ok');
      } else if (path == '/mismatched-worker.js') {
        final protocol = request.uri.queryParameters['protocol'] == 'old'
            ? sqliteWebProtocol - 1
            : sqliteWebProtocol;
        request.response.headers.contentType = ContentType.parse(
          'text/javascript',
        );
        request.response.write(
          'onmessage=e=>postMessage([e.data[0],true,false,[$protocol,"old-build"]]);',
        );
      } else {
        final relative = path == '/nested/detail/42'
            ? 'index.html'
            : path.startsWith('/nested/')
            ? path.substring(8)
            : '';
        final file = File('${output.path}/$relative');
        if (relative.isEmpty ||
            relative.contains('..') ||
            !await file.exists()) {
          request.response.statusCode = 404;
        } else {
          request.response.headers.contentType = ContentType.parse(
            relative.endsWith('.wasm')
                ? 'application/wasm'
                : relative.endsWith('.js') || relative.endsWith('.mjs')
                ? 'text/javascript'
                : relative.endsWith('.html')
                ? 'text/html'
                : 'application/octet-stream',
          );
          await request.response.addStream(file.openRead());
        }
      }
    } finally {
      await request.response.close();
    }
  });
  final profile = await Directory.systemTemp.createTemp('orm-flutter-web-');
  Process? browser;
  final errors = StringBuffer();
  try {
    browser = await Process.start(
      Platform.environment['CHROME_EXECUTABLE'] ??
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      [
        '--headless=new',
        '--no-first-run',
        '--disable-background-networking',
        '--disable-component-update',
        '--user-data-dir=${profile.path}',
        'http://127.0.0.1:${server.port}/nested/detail/42',
      ],
    );
    browser.stdout.drain<void>();
    browser.stderr.transform(utf8.decoder).listen(errors.write);
    final report = await complete.future.timeout(const Duration(minutes: 3));
    report['requests'] = requests;
    return report;
  } catch (e) {
    stderr.writeln('$errors\nRequests: $requests');
    rethrow;
  } finally {
    browser?.kill();
    if (browser != null) await browser.exitCode;
    await server.close(force: true);
    await deleteBrowserProfile(profile);
  }
}

const _flutterMain = r'''
import 'package:flutter/material.dart';
import 'test/support/browser/main.dart' as acceptance;

void main() => runApp(const MaterialApp(home: Probe()));
class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}
class _ProbeState extends State<Probe> with SingleTickerProviderStateMixin {
  late final AnimationController ticker;
  int frames = 0;
  String status = 'Running ORM checks';
  @override
  void initState() {
    super.initState();
    ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..addListener(() => frames++)..repeat();
    acceptance.flutterFrames = () => frames;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await acceptance.main();
      if (mounted) setState(() => status = 'Completed');
    });
  }
  @override
  void dispose() { ticker.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [RotationTransition(turns: ticker, child: const Text('ORM')),
      Text(status)],
  )));
}
''';
