import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:orm/src/sqlite/assets_io.dart';
import 'package:orm/src/sqlite/web_build.dart';
import 'package:orm/generate.dart';

import 'src/browser_profile.dart';

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
  final checked = await Process.run(Platform.resolvedExecutable, [
    'run',
    'tool/build_sqlite_web.dart',
    '--check',
  ]);
  if (checked.exitCode != 0) {
    throw StateError('${checked.stdout}${checked.stderr}');
  }
  await copySqliteWebAssets(Directory('${assets.path}/orm'));
  final generated = await generateSchema('test/support/browser/schema.dart');
  if (generated.dart !=
          await File('test/support/browser/schema.orm.dart').readAsString() ||
      generated.snapshotDart !=
          await File('test/support/browser/schema.snapshot.dart')
              .readAsString()) {
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
      } else if (request.uri.path == '/mismatched-worker.js') {
        final protocol = request.uri.queryParameters['protocol'] == 'old'
            ? sqliteWebProtocol - 1
            : sqliteWebProtocol;
        request.response.headers.contentType = ContentType.parse(
          'text/javascript',
        );
        request.response.write(
          'onmessage=e=>postMessage([e.data[0],true,false,[$protocol,"old-build"]]);',
        );
      } else if ({
        '/main.js',
        '/main.wasm',
        '/main.mjs',
        '/orm/$sqliteWorkerFile',
        '/orm/$sqliteWasmFile',
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
    await deleteBrowserProfile(profile);
  }
}
