import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:orm/src/sqlite/assets_io.dart';

import 'browser_profile.dart';
import 'build_fixture.dart';

/// Fresh package generation shared by native, Chrome and optional Flutter probes.
Future<BuildFixture> conditionalDefaultConsumer(String ormPath) async {
  final fixture = await BuildFixture.create(ormPath: ormPath);
  try {
    await fixture.file('lib/schema.dart').delete();
    final pubspec = fixture.file('pubspec.yaml');
    await pubspec.writeAsString(
      (await pubspec.readAsString()).replaceFirst(
        '\ndev_dependencies:',
        '\n  web: ^1.1.1\ndev_dependencies:',
      ),
    );
    await fixture.run(['pub', 'get', '--offline']);
    for (final entry in _files.entries) {
      await fixture.write(entry.key, entry.value);
    }
    for (final platform in ['native', 'web']) {
      await fixture.write(
        'lib/fields_$platform.dart',
        _fields.replaceAll('PLATFORM', platform),
      );
      await fixture.write(
        'lib/helpers_$platform.dart',
        _helpers.replaceAll('PLATFORM', platform),
      );
    }
    // One command generates the client/snapshot and saves immutable history.
    await fixture.run(['run', 'orm', 'migrate', 'create', '0001_initial']);
    return fixture;
  } catch (_) {
    await fixture.dispose();
    rethrow;
  }
}

Future<Map<String, String>> conditionalDefaultHashes(
  BuildFixture fixture,
) async => {
  for (final file in [
    'lib/models.dart',
    'lib/fields_native.dart',
    'lib/fields_web.dart',
    'lib/helpers_native.dart',
    'lib/helpers_web.dart',
    'lib/choice.dart',
    'lib/facade.dart',
    'lib/defaults.dart',
    'lib/models.orm.dart',
    'lib/models.snapshot.dart',
    'lib/migrations/m0001_initial.dart',
    'lib/migrations/migrations.g.dart',
  ])
    file: sha256.convert(await fixture.file(file).readAsBytes()).toString(),
};

Future<Map<String, Object?>> conditionalDefaultNative(
  BuildFixture fixture,
) async {
  final result = await fixture.run(['run', 'bin/native.dart']);
  final report = jsonDecode(
    result.output.split('\n').firstWhere((line) => line.startsWith('{')),
  ) as Map<String, Object?>;
  _check(
    report['passed'] == true && report['target'] == 'native',
    'Native consumer failed: $report',
  );
  return report;
}

Future<void> verifyConditionalDefaultsChrome({
  required bool wasm,
  required String chrome,
}) async {
  final fixture = await conditionalDefaultConsumer(
    Directory.current.absolute.path,
  );
  try {
    final before = await conditionalDefaultHashes(fixture);
    final native = await conditionalDefaultNative(fixture);
    final output = Directory('${fixture.directory.path}/web_output');
    await output.create();
    await copySqliteWebAssets(Directory('${output.path}/orm'));
    await fixture.run([
      'compile',
      wasm ? 'wasm' : 'js',
      if (!wasm) '-O2',
      'bin/browser.dart',
      '-o',
      '${output.path}/main.${wasm ? 'wasm' : 'js'}',
    ]);
    await File('${output.path}/index.html').writeAsString(
      wasm
          ? '''<html><body><script type="module">import {compileStreaming} from './main.mjs';const app=await compileStreaming(fetch('./main.wasm'));const instance=await app.instantiate({});instance.invokeMain();</script></body></html>'''
          : '<html><body><script defer src="main.js"></script></body></html>',
    );
    final report = await _browser(output, chrome);
    _check(
      report['passed'] == true &&
          report['target'] == 'web' &&
          report['actualWasm'] == wasm,
      'Chrome consumer did not run the requested target: $report',
    );
    final after = await conditionalDefaultHashes(fixture);
    _check(
      jsonEncode(before) == jsonEncode(after),
      'Generated artifacts changed between native and Chrome',
    );
    report['native'] = native;
    report['artifactHashes'] = before;
    report['generationCommands'] = 1;
    final evidence = File(
      '.dart_tool/browser/conditional-defaults.${wasm ? 'wasm' : 'js'}.json',
    );
    await evidence.parent.create(recursive: true);
    await evidence.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln(
      'Fresh conditional-default consumer (${wasm ? 'wasm' : 'js'}): passed native + actual Chrome + saved SQLite migration/CRUD.',
    );
  } finally {
    await fixture.dispose();
  }
}

Future<Map<String, Object?>> _browser(Directory output, String chrome) async {
  final complete = Completer<Map<String, Object?>>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <String>[];
  final profile = await Directory.systemTemp.createTemp(
    'orm-conditional-chrome-',
  );
  Process? browser;
  final errors = StringBuffer();
  try {
    server.listen((request) async {
      try {
        if (request.uri.path == '/report' && request.method == 'POST') {
          final report = jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map<String, Object?>;
          if (!complete.isCompleted) complete.complete(report);
          request.response.write('ok');
        } else {
          requests.add(request.uri.path);
          final path = request.uri.path == '/'
              ? '/index.html'
              : request.uri.path;
          if (request.uri.pathSegments.contains('..')) {
            request.response.statusCode = 404;
          } else {
            final file = File('${output.path}$path');
            if (await file.exists()) {
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
        }
      } catch (e, s) {
        if (!complete.isCompleted) complete.completeError(e, s);
      } finally {
        await request.response.close();
      }
    });
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
    final report = await complete.future.timeout(const Duration(minutes: 2));
    report['requests'] = requests;
    return report;
  } catch (e) {
    throw StateError('$e\n$errors\nRequests: $requests');
  } finally {
    browser?.kill();
    if (browser != null) await browser.exitCode;
    await server.close(force: true);
    await deleteBrowserProfile(profile);
  }
}

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

const _fields = r'''
import 'package:orm/schema.dart';
import 'defaults.dart' as defaults;
import 'facade.dart' as helpers;
import 'helpers_PLATFORM.dart' as branch;
export 'helpers_PLATFORM.dart' show branchFactory, Labels, Token, tokenFactory;
typedef _FieldLabels = branch.Labels;
typedef _FieldAlias = _FieldLabels;
String rawFactory() => 'PLATFORM';
mixin Fields {
  @Id(generated: true) int id = 0;
  @ClientDefault(rawFactory) String label = '';
  @ClientDefault(defaults.next) String wrapped = '';
  @ClientDefault(helpers.next) String exported = '';
  @ClientDefault(helpers.Labels.next) String staticLabel = '';
  @ClientDefault(helpers.generic<String>) String genericLabel = '';
  @ClientDefault(helpers.tokenFactory<helpers.Token>) String typedLabel = '';
  @ClientDefault(helpers.alias) String aliasLabel = '';
  @ClientDefault(branch.branchFactory) String externalLabel = '';
  @ClientDefault(_FieldAlias.next) String mixinAlias = '';
  @DatabaseDefault(true) bool active = false;
  String? note;
  @Ignore() final String local = 'local';
  String get platform => 'PLATFORM';
  String describe() => '$platform:$id:$label';
}
''';

const _helpers = r'''
String next() => 'PLATFORM';
String branchFactory() => 'PLATFORM';
class _Labels { static String next() => 'PLATFORM'; }
typedef Labels = _Labels;
T generic<T>() => 'PLATFORM' as T;
class _Token {}
typedef Token = _Token;
String tokenFactory<T>() {
  if (T != Token) throw StateError('Factory received the wrong platform type: $T');
  return 'PLATFORM';
}
String nestedFactory<T>() {
  if (T != Map<Token,List<Token?>>) throw StateError('Factory received wrong nested type: $T');
  return 'PLATFORM';
}
const alias = next;
''';

const _files = {
  'orm.config.dart': r'''
import 'package:orm/config.dart';
void main() => defineConfig(database: .sqlite, migrations: 'lib/migrations',
  connect: ({required bool readOnly}) => throw StateError('Offline generation only'));
''',
  'lib/models.dart': r'''
import 'package:orm/schema.dart';
import 'fields_native.dart' if (dart.library.js_interop) 'fields_web.dart' as chosen;
import 'facade.dart' as helpers;
typedef _First = helpers.Labels;
typedef _Second = _First;
typedef _Type<T> = Map<helpers.Token,List<T?>>;
typedef _Nested = _Type<helpers.Token>;
@Model(table: 'memos')
final class Memo with chosen.Fields {
  final String title;
  final String localAlias;
  final String nestedLabel;
  Memo({required int id, required this.title, String label = 'constructor',
    @ClientDefault(_Second.next) this.localAlias = 'constructor',
    @ClientDefault(helpers.nestedFactory<_Nested>) this.nestedLabel = 'constructor',
    String wrapped = 'constructor', String exported = 'constructor',
    String staticLabel = 'constructor', String genericLabel = 'constructor',
    String typedLabel = 'constructor',
    String aliasLabel = 'constructor',
    String externalLabel = 'constructor',
    String mixinAlias = 'constructor',
    bool active = false, String? note = 'guest'}) {
    this.id = id; this.label = label; this.wrapped = wrapped;
    this.exported = exported; this.active = active; this.note = note;
    this.staticLabel = staticLabel; this.genericLabel = genericLabel; this.aliasLabel = aliasLabel;
    this.externalLabel = externalLabel;
    this.typedLabel = typedLabel;
    this.mixinAlias = mixinAlias;
  }
}
''',
  'lib/choice.dart': "export 'helpers_native.dart' if (dart.library.js_interop) 'helpers_web.dart';\n",
  'lib/facade.dart': "export 'choice.dart' show next, Labels, generic, alias, Token, tokenFactory, nestedFactory;\n",
  'lib/defaults.dart':
      "import 'facade.dart' as helpers;\nString next() => helpers.next();\n",
  'lib/acceptance.dart': r'''
import 'package:orm/sqlite.dart';
import 'package:orm/migrate.dart';
import 'models.dart' as original;
import 'models.orm.dart';
import 'models.snapshot.dart' as physical;
import 'migrations/m0001_initial.dart' as initial;
import 'migrations/migrations.g.dart' as saved;
void check(bool value, String message) { if (!value) throw StateError(message); }
Future<Map<String,Object?>> acceptance() async {
  final target = original.Memo(id: 0, title: 'probe').platform;
  final bindings = {for(final name in ['label','wrapped','exported','static_label','generic_label','alias_label','local_alias','external_label','mixin_alias','typed_label','nested_label'])
    name: memoSchema.columns.singleWhere((c) => c.name == name).clientDefault!()};
  check(bindings.values.every((value) => value == target), 'Factory binding differs from model target: $bindings/$target');
  final db = await sqlite(const SqliteOptions.memory());
  try {
    check(initial.migration.checksum == initial.migrationChecksum, 'Frozen checksum');
    final migrator = Migrator(db.sql);
    check((await migrator.plan(saved.migrationHistory.checked)).single.id == '0001_initial', 'Saved migration plan');
    check((await migrator.apply(saved.migrationHistory.checked)).single == '0001_initial', 'Saved migration apply');
    check((await migrator.apply(saved.migrationHistory.checked)).isEmpty, 'Repeated apply');
    check((await migrator.history()).single.checksum == initial.migrationChecksum, 'Recorded checksum');
    check((await verifySchema(db.sql, physical.schema)).matches, 'Real SQLite catalog');
    final original.Memo row = await db.memo.create(title: 'omitted');
    check(row.label == target && row.wrapped == target && row.exported == target && row.active && row.note == 'guest', 'Stored omission/default precedence');
    check(row.staticLabel == target && row.genericLabel == target && row.aliasLabel == target && row.localAlias == target && row.externalLabel == target && row.mixinAlias == target && row.typedLabel == target && row.nestedLabel == target, 'Stored static/generic/const/local-alias/external/mixin-alias factory values');
    check(row.describe() == '$target:${row.id}:$target', 'Original DTO/mixin method');
    final explicit = await db.memo.create(title: 'explicit', label: .set('manual'), active: .set(false), note: .set(null));
    check(explicit.label == 'manual' && !explicit.active && explicit.note == null, 'Explicit values/null');
    await db.memo.byId(row.id).patch(label: .set('changed'), note: .set(null));
    final read = await db.memo.byId(row.id).single();
    check(read.note == null && read.describe() == '$target:${row.id}:changed', 'Read/update DTO method');
    await db.memo.delete().execute();
    check(await db.memo.count() == 0, 'Delete');
    return {'passed':true,'target':target,'bindings':bindings,'storedOmittedLabel':row.label,
      'fixedWrapperControl':row.wrapped,'indirectExportDefault':row.exported,
      'savedMigrationAndCatalog':true,'crudAndDtoMixinMethods':true,'explicitValuesAndNull':true};
  } finally { await db.close(); }
}
''',
  'bin/native.dart': r'''
import 'dart:convert';
import 'package:orm_build_fixture/acceptance.dart';
Future<void> main() async => print(jsonEncode(await acceptance()));
''',
  'bin/browser.dart': r'''
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:orm_build_fixture/acceptance.dart';
Future<void> main() async {
  Map<String,Object?> report;
  try { report = await acceptance(); } catch(e,s) { report = {'passed':false,'error':'$e','stack':'$s'}; }
  report['actualWasm'] = const bool.fromEnvironment('dart.tool.dart2wasm');
  report['browser'] = web.window.navigator.userAgent;
  web.document.body!.textContent = jsonEncode(report);
  await web.window.fetch('/report'.toJS, web.RequestInit(method:'POST',body:jsonEncode(report).toJS)).toDart;
}
''',
};
