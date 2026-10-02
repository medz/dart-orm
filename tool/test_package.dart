import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'src/browser_profile.dart';

/// Checks a safely unpacked pub archive in an independent pure Dart application.
/// The optional second argument saves the report outside the temporary consumer.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    throw ArgumentError('Use <unpacked-package> [report.json].');
  }
  final package = Directory(await Directory(args.first).resolveSymbolicLinks());
  final version = RegExp(r'^version: (.+)$', multiLine: true)
      .firstMatch(await File('${package.path}/pubspec.yaml').readAsString())!
      .group(1)!;
  final consumer = await Directory.systemTemp.createTemp('orm-package-');
  final root = await consumer.resolveSymbolicLinks();
  final commands = <String>[];
  final logs = StringBuffer();
  Future<void> write(String path, String source) async {
    final file = File('$root/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(source);
  }

  Future<String> run(List<String> arguments) async {
    commands.add('dart ${arguments.join(' ')}');
    stdout.writeln(commands.last);
    final result = await Process.run(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: root,
    );
    final output = '${result.stdout}\n${result.stderr}';
    logs.writeln('${commands.last}\n$output');
    if (result.exitCode != 0) throw StateError(output);
    return output;
  }

  Future<String> hash(String path) async =>
      (await sha256.bind(File('$root/$path').openRead()).first).toString();
  try {
    await write('pubspec.yaml', '''
name: package_consumer
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  orm:
    path: ${jsonEncode(package.path)}
  web: ^1.1.1
dev_dependencies:
  build_runner: ^2.16.1
''');
    await run(['pub', 'get', '--offline']);
    final configFile = File('$root/.dart_tool/package_config.json');
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, Object?>;
    final orm = (config['packages'] as List)
        .cast<Map<String, Object?>>()
        .singleWhere((p) => p['name'] == 'orm');
    final resolved = configFile.uri.resolve(orm['rootUri'] as String);
    _check(
      await Directory.fromUri(resolved).resolveSymbolicLinks() == package.path,
      'Consumer must resolve ORM exclusively from the unpacked archive.',
    );
    await run(['run', 'orm', '--help']);
    await run(['run', 'orm', 'init', '--database', 'sqlite']);
    await write('lib/models.dart', _models);
    await run(['run', 'orm', 'generate']);
    final cliClient = await hash('lib/models.orm.dart');
    final cliSnapshot = await hash('lib/models.snapshot.dart');
    await File('$root/lib/models.orm.dart').delete();
    await File('$root/lib/models.snapshot.dart').delete();
    await write('build.yaml', '''
targets:
  \$default:
    builders:
      orm:orm:
        enabled: true
        generate_for:
          - lib/models.dart
''');
    await run(['run', 'build_runner', 'build']);
    _check(
      await hash('lib/models.orm.dart') == cliClient &&
          await hash('lib/models.snapshot.dart') == cliSnapshot,
      'CLI and build_runner must generate identical sources from a first build.',
    );
    for (final command in [
      ['migrate', 'create', '0001_initial'],
      ['migrate', 'check'],
      ['migrate', 'apply'],
      ['migrate', 'status'],
      ['migrate', 'verify'],
      ['web-assets'],
      ['web-assets', 'web/custom'],
    ]) {
      await run(['run', 'orm', ...command]);
    }
    final assetHashes = <String, String>{};
    await for (final asset in Directory(
      '${package.path}/assets/sqlite',
    ).list()) {
      if (asset is! File) continue;
      final name = asset.uri.pathSegments.last;
      final expected = (await sha256.bind(asset.openRead()).first).toString();
      _check(
        await hash('web/orm/$name') == expected &&
            await hash('web/custom/$name') == expected,
        'CLI must export the archive assets unchanged: $name.',
      );
      assetHashes[name] = expected;
    }
    await write('lib/checks.dart', _checks);
    await write('bin/native.dart', '''
import 'dart:convert';
import 'package:package_consumer/checks.dart';
Future<void> main() async => print(jsonEncode(await checks()));
''');
    await write('web/main.dart', _browser);
    await run(['analyze']);
    final nativeOutput = await run(['run', 'bin/native.dart']);
    final native = jsonDecode(
      nativeOutput.split('\n').firstWhere((line) => line.startsWith('{')),
    );
    final browsers = <Map<String, Object?>>[];
    for (final mode in ['js', 'wasm']) {
      await run([
        'compile',
        mode,
        if (mode == 'js') '-O2',
        'web/main.dart',
        '-o',
        'web/main.$mode',
      ]);
      await write(
        'web/index.html',
        mode == 'js'
            ? '<html><body><script defer src="main.js"></script></body></html>'
            : '''<html><body><script type="module">
import {compileStreaming} from './main.mjs';
const app = await compileStreaming(fetch('./main.wasm'));
const instance = await app.instantiate({}); instance.invokeMain();
</script></body></html>''',
      );
      final report = await _chrome(Directory('$root/web'));
      _check(report['passed'] == true, 'Chrome $mode failed: $report');
      _check(
        report['actualWasm'] == (mode == 'wasm'),
        'Wrong browser compiler.',
      );
      final requests = report['requests'] as List;
      for (final name in assetHashes.keys) {
        _check(requests.contains('/orm/$name'), 'Chrome did not load $name.');
      }
      report['compiler'] = mode;
      browsers.add(report);
    }
    final report = {
      'passed': true,
      'version': version,
      'sdk': Platform.version,
      'packageRoot': package.path,
      'consumerOrmRoot': resolved.toString(),
      'commands': commands,
      'clientSha256': cliClient,
      'snapshotSha256': cliSnapshot,
      'assets': assetHashes,
      'native': native,
      'browser': browsers,
    };
    final json = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
    stdout.write(json);
    if (args.length == 2) {
      final target = File(args[1]);
      await target.parent.create(recursive: true);
      await target.writeAsString(json);
      await File('${args[1]}.log').writeAsString(logs.toString());
    }
  } finally {
    await consumer.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _chrome(Directory output) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final profile = await Directory.systemTemp.createTemp('orm-package-chrome-');
  final complete = Completer<Map<String, Object?>>();
  final requests = <String>[];
  final errors = StringBuffer();
  Process? browser;
  try {
    server.listen((request) async {
      try {
        if (request.uri.path == '/report' && request.method == 'POST') {
          final report = jsonDecode(await utf8.decoder.bind(request).join());
          if (!complete.isCompleted) complete.complete((report as Map).cast());
          request.response.write('ok');
        } else {
          final path = request.uri.path == '/'
              ? '/index.html'
              : request.uri.path;
          requests.add(path);
          final file = File('${output.path}$path');
          if (!request.uri.pathSegments.contains('..') && await file.exists()) {
            request.response.headers.contentType = ContentType.parse(
              path.endsWith('.html')
                  ? 'text/html'
                  : path.endsWith('.wasm')
                  ? 'application/wasm'
                  : 'text/javascript',
            );
            await request.response.addStream(file.openRead());
          } else {
            request.response.statusCode = 404;
          }
        }
      } catch (error, stack) {
        if (!complete.isCompleted) complete.completeError(error, stack);
      } finally {
        await request.response.close();
      }
    });
    browser = await Process.start(
      Platform.environment['CHROME_EXECUTABLE'] ??
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      [
        '--headless=new',
        '--no-first-run',
        '--disable-background-networking',
        '--disable-component-update',
        '--user-data-dir=${profile.path}',
        'http://127.0.0.1:${server.port}/',
      ],
    );
    browser.stdout.drain<void>();
    browser.stderr.transform(utf8.decoder).listen(errors.write);
    final report = await complete.future.timeout(const Duration(minutes: 2));
    report['requests'] = requests;
    return report;
  } catch (error) {
    throw StateError('$error\n$errors\nRequests: $requests');
  } finally {
    browser?.kill();
    if (browser != null) await browser.exitCode;
    await server.close(force: true);
    await deleteBrowserProfile(profile);
  }
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

const _models = r'''
import 'package:orm/schema.dart';
@Model(table: 'tasks')
final class Task({
  @Id(generated: true) required final int id,
  required final String title,
  final String? note,
  @DatabaseDefault(false) final bool done = false,
  @DatabaseDefault(0) final int score = 0,
});
@Model(table: 'comments')
final class Comment({
  @Id(generated: true) required final int id,
  @Relation(target: Task, name: 'task', inverse: 'comments')
  required final int taskId,
  required final String body,
});
@Projection()
final class TaskCard({required final int id, required final String title});
@Projection()
typedef CommentCard = ({int id, String body});
@Projection()
final class TaskView({
  required final int id,
  required final String title,
  required final List<CommentCard> comments,
});
''';

const _checks = r'''
import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';
import 'package:orm/sqlite.dart';
import 'package:orm/migrate.dart';
import 'models.orm.dart';
import '../migrations/migrations.g.dart' as saved;
Future<Map<String, Object?>> checks() async {
  final passed = <String>[];
  void check(bool condition, String label) {
    if (!condition) throw StateError(label);
    passed.add(label);
  }
  final events = <QueryEvent>[];
  final db = Database.fromSql(await sqlite(const SqliteOptions.memory(), onQuery: events.add));
  try {
    final migrator = Migrator(db.sql);
    check((await migrator.apply(saved.migrationHistory.checked)).single == '0001_initial', 'frozen migration apply');
    check((await migrator.apply(saved.migrationHistory.checked)).isEmpty, 'idempotent history');
    final Task task = await db.task.create(title: 'Draft', note: 'old');
    check(!task.done && task.score == 0, 'ordinary create and defaults');
    final Future<int> insert = db.task.insert(taskInsert(title: 'Other'));
    check(await insert == 1, 'ordinary insert Future');
    check(await db.task.insertMany([taskInsert(title: 'Third')]) == 1, 'ordinary batch insert');
    final patch = taskPatch.overlay([taskPatch(note: null), taskPatch.values(score: .expression((t) => t.score.plus(2))), taskPatch(title: 'Reviewed')]);
    check(!taskPatch.isEmpty(patch) && await db.task.byId(task.id).update(patch) == 1, 'typed patch overlay');
    final updated = await db.task.byId(task.id).single();
    check(updated.note == null && updated.score == 2, 'explicit null and expression');
    check(await db.task.byId(task.id).patch(done: true) == 1, 'ordinary patch Future');
    var calls = 0;
    final plan = db.task.byId(task.id).plan.update(taskPatch.values(score: .expression((t) { calls++; return t.score.plus(1); })));
    check(calls == 0, 'inert plan');
    final int returned = await plan.returning().select((t) => t.score).single();
    check(returned == 3 && calls == 1, 'plan RETURNING');
    final prepared = db.task.plan.insert(taskInsert(title: 'Prepared')).prepare();
    check(prepared.compile().parameters.contains('Prepared') && await prepared.execute() == 1, 'prepared insert');
    await db.comment.create(taskId: task.id, body: 'First');
    await db.comment.create(taskId: task.id, body: 'Second');
    events.clear();
    final TaskView nested = await db.task.byId(task.id).select((t) => taskView(id: t.id, title: t.title, comments: t.comments.orderBy((c) => [c.id.asc()]).select((c) => commentCard(id: c.id, body: c.body)).many())).single();
    check(nested.comments.map((c) => c.body).join(',') == 'First,Second' && events.length == 2, 'nested named shape and observable batch');
    final cte = db.task.select((t) => taskCard.sql(id: t.id, title: t.title)).asCte('cards');
    final TaskCard card = await cte.where((c) => c.id.eq(.value(task.id))).single();
    check(card.title == 'Reviewed', 'named Projection CTE');
    final scalar = db.task.select((t) => t.title).asCte('titles');
    check((await scalar.where((c) => c.ref((t) => t.title).eq(.value('Reviewed'))).single()) == 'Reviewed', 'scalar CTE direct query');
    events.clear();
    await db.transaction((tx) async { await tx.task.byId(task.id).patch(title: 'Committed'); });
    check(events.first.sql.startsWith('BEGIN') && events.last.sql == 'COMMIT', 'observable transaction commit');
    try {
      await db.transaction((tx) async { await tx.task.byId(task.id).patch(title: 'Rolled back'); throw StateError('rollback'); });
    } on StateError catch (e) { if (e.message != 'rollback') rethrow; }
    check((await db.task.byId(task.id).single()).title == 'Committed', 'transaction rollback');
    final Future<int> deleted = db.task.where((t) => t.title.eq(.value('Other'))).delete();
    check(await deleted == 1 && await db.task.count() == 3, 'ordinary delete Future');
    return {'passed': true, 'checks': passed};
  } finally { await db.close(); }
}
''';

const _browser = r'''
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:package_consumer/checks.dart';
Future<void> main() async {
  Map<String, Object?> result;
  try { result = await checks(); }
  catch (error, stack) { result = {'passed': false, 'error': '$error', 'stack': '$stack'}; }
  result['actualWasm'] = const bool.fromEnvironment('dart.tool.dart2wasm');
  result['browser'] = web.window.navigator.userAgent;
  final body = jsonEncode(result);
  web.document.body!.textContent = body;
  await web.window.fetch('/report'.toJS, web.RequestInit(method: 'POST', body: body.toJS)).toDart;
}
''';
