import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:orm/generate.dart';

const engineVersion = '3.6.0';
const engineDigest =
    '13d3f11d05b39ba0618a7115fb41640a5d48b6300f5d3f325f554b42bd6688a4';

/// Real Chrome smoke/acceptance runner. Assets remain in .dart_tool/browser.
Future<void> main(List<String> arguments) async {
  if (arguments.any((a) => a != '--wasm')) {
    throw ArgumentError('Use --wasm for a Dart WASM client.');
  }
  final wasm = arguments.contains('--wasm');
  final assets = Directory('.dart_tool/browser').absolute;
  await assets.create(recursive: true);
  final engine = File('${assets.path}/sqlite3.wasm');
  if (!await engine.exists()) {
    final http = HttpClient();
    try {
      final response = await (await http.getUrl(
        Uri.parse(
          'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$engineVersion/sqlite3.wasm',
        ),
      )).close();
      if (response.statusCode != 200) {
        throw StateError('WASM download failed: ${response.statusCode}');
      }
      final bytes = await response.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      if (sha256.convert(bytes).toString() != engineDigest) {
        throw StateError('WASM digest differs.');
      }
      await engine.writeAsBytes(bytes);
    } finally {
      http.close(force: true);
    }
  }
  if ((await sha256.bind(engine.openRead()).first).toString() != engineDigest) {
    throw StateError('Cached WASM digest differs.');
  }
  final generated = await generateSchema('test/support/browser/schema.dart');
  if (generated.dart !=
          await File('test/support/browser/schema.orm.dart').readAsString() ||
      jsonEncode(generated.snapshot) !=
          jsonEncode(
            jsonDecode(
              await File('test/support/browser/schema.orm.json').readAsString(),
            ),
          )) {
    throw StateError('Regenerate the browser schema fixture.');
  }
  Future<void> compile(List<String> args) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      ...args,
    ]);
    if (result.exitCode != 0) {
      throw StateError('${result.stdout}\n${result.stderr}');
    }
  }

  await Future.wait([
    compile([
      'js',
      '-O2',
      'test/support/browser/worker.dart',
      '-o',
      '${assets.path}/worker.js',
    ]),
    compile([
      wasm ? 'wasm' : 'js',
      if (!wasm) '-O2',
      'test/support/browser/main.dart',
      '-o',
      '${assets.path}/main.${wasm ? 'wasm' : 'js'}',
    ]),
  ]);
  final chrome =
      Platform.environment['CHROME_EXECUTABLE'] ??
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  final profile = await Directory.systemTemp.createTemp('orm-browser-');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final result = Completer<Map<String, Object?>>();
  server.listen((request) async {
    try {
      if (request.uri.path == '/report' && request.method == 'POST') {
        final body = await utf8.decoder.bind(request).join();
        if (!result.isCompleted) {
          result.complete(jsonDecode(body) as Map<String, Object?>);
        }
        request.response.write('ok');
      } else if (request.uri.path == '/') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<!doctype html><html><body>Running ORM browser checks${wasm ? '''<script type="module">
import {compileStreaming} from '/main.mjs';
const app = await compileStreaming(fetch('/main.wasm'));
const instance = await app.instantiate({});
instance.invokeMain();
</script>''' : '<script defer src="/main.js"></script>'}</body></html>',
        );
      } else if ({
        '/main.js',
        '/main.wasm',
        '/main.mjs',
        '/worker.js',
        '/sqlite3.wasm',
      }.contains(request.uri.path)) {
        request.response.headers.contentType = ContentType.parse(
          request.uri.path.endsWith('.wasm')
              ? 'application/wasm'
              : 'text/javascript',
        );
        await request.response.addStream(
          File('${assets.path}${request.uri.path}').openRead(),
        );
      } else {
        request.response.statusCode = 404;
      }
    } catch (error) {
      if (!result.isCompleted) result.completeError(error);
    } finally {
      await request.response.close();
    }
  });
  Process? browser;
  final errors = StringBuffer();
  try {
    browser = await Process.start(chrome, [
      '--headless=new',
      '--no-first-run',
      '--disable-background-networking',
      '--disable-component-update',
      '--user-data-dir=${profile.path}',
      'http://127.0.0.1:${server.port}/',
    ]);
    browser.stdout.drain<void>();
    browser.stderr.transform(utf8.decoder).listen(errors.write);
    final report = await result.future.timeout(const Duration(minutes: 2));
    report['dartCompilation'] = wasm ? 'wasm' : 'js';
    report['dartSdk'] = Platform.version;
    report['sqlitePackage'] = engineVersion;
    report['sqliteWasmSha256'] = engineDigest;
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    await File(
      '${assets.path}/report.${wasm ? 'wasm' : 'js'}.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    if (report['passed'] != true) exitCode = 1;
  } catch (error) {
    stderr.writeln('$error\n$errors');
    exitCode = 1;
  } finally {
    browser?.kill();
    if (browser != null) await browser.exitCode;
    await server.close(force: true);
    await profile.delete(recursive: true);
  }
}
