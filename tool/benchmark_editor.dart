import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:orm/generate.dart';

import 'src/build_fixture.dart';
import 'src/editor_server.dart';

Future<void> main(List<String> args) async {
  final smoke = args.contains('--smoke');
  final sameSession = args.contains('--same-session');
  if (args.any((a) => a != '--smoke' && a != '--same-session')) {
    throw ArgumentError('Use --smoke, --same-session, or no arguments.');
  }
  final samples = smoke ? 2 : 20;
  final results = <Map<String, Object?>>[];
  for (final models in smoke ? [10] : [10, 100, 1000]) {
    stdout.writeln('Editor protocol checks for $models models...');
    final fixture = await BuildFixture.create(
      ormPath: Directory.current.path,
      models: models,
    );
    EditorServer? server;
    try {
      final schema = fixture.file('lib/schema.dart');
      await writeGeneratedSchema(schema.path);
      final source = await schema.readAsString();
      final generatedBytes = await fixture.file('lib/schema.orm.dart').length();
      await fixture.write('lib/symbols.dart', _symbols);
      final start = Stopwatch()..start();
      server = await EditorServer.start(fixture.directory.path);
      final diagnosticServerPid = server.process.pid;
      final initializeMicros = start.elapsedMicroseconds;
      await server.ready();
      final projectReadyMicros = start.elapsedMicroseconds;
      final completions = <Map<String, Object?>>[];
      for (final probe in [
        (
          name: 'table_entries',
          file: 'lib/client.dart',
          source: _client('db./*caret*/;'),
          required: ['row0', 'row${models - 1}'],
          forbidden: <String>[],
        ),
        (
          name: 'schema_record_fields',
          file: 'lib/schema.dart',
          source:
              "$source\nfinal editorProbe = model('editor_probes', (id: integer(), title: text(), score: integer(), status: enumeration(Status.values)), primaryKey: (r) => r./*caret*/);\n",
          required: ['id', 'title', 'score', 'status'],
          forbidden: <String>[],
        ),
        (
          name: 'query_fields',
          file: 'lib/client.dart',
          source: _client('db.row0.where((r) => r./*caret*/);'),
          required: ['id', 'title', 'score', 'status'],
          forbidden: <String>[],
        ),
        (
          name: 'create_arguments',
          file: 'lib/client.dart',
          source: _client('await db.row0.create(/*caret*/);'),
          required: ['title:', 'status:'],
          forbidden: <String>[],
        ),
        (
          name: 'projected_record_fields',
          file: 'lib/client.dart',
          source: _client(
            'final rows = await db.row0.select((r) => (r.id,r.title).map((id,title) => (id:id,title:title))).get(); final row = rows.first; row./*caret*/;',
          ),
          required: ['id', 'title'],
          forbidden: ['score', 'status'],
        ),
      ]) {
        final path = fixture.file(probe.file).path;
        final caret = probe.source.indexOf('/*caret*/');
        final text = probe.source.replaceFirst('/*caret*/', '');
        // An editor opens a file in the consumer project, not an absent URI.
        await fixture.write(probe.file, text);
        final readiness = Stopwatch()..start();
        final version = server.open(path, text);
        await server.waitDiagnostics(path, version, matches: (_) => true);
        final analysisReadyMicros = readiness.elapsedMicroseconds;
        Future<({int micros, Map<String, Object?> result})> complete() async {
          final active = server!;
          final watch = Stopwatch()..start();
          final response = await active.request('textDocument/completion', {
            ...editorLocation(path, text, caret),
            'context': {'triggerKind': 1},
          });
          final micros = watch.elapsedMicroseconds;
          final result = response is List
              ? {'items': response, 'isIncomplete': false}
              : response as Map<String, Object?>;
          final items = (result['items'] as List).cast<Map<String, Object?>>();
          final labels = items.map((i) => i['label'] as String).toList();
          for (final wanted in probe.required) {
            if (!labels.any((l) => l == wanted || l.startsWith('$wanted '))) {
              throw StateError(
                '${probe.name} is missing $wanted: $result; diagnostics=${active.diagnostics}; stderr=${active.stderr}',
              );
            }
          }
          for (final unwanted in probe.forbidden) {
            if (labels.contains(unwanted)) {
              throw StateError(
                'Unselected $unwanted leaked into result completion.',
              );
            }
          }
          return (
            micros: micros,
            result: {
              'isIncomplete': result['isIncomplete'],
              'itemCount': items.length,
              'items': [
                for (final item in items.where(
                  (i) => probe.required.any(
                    (r) => (i['label'] as String).startsWith(r),
                  ),
                ))
                  {
                    for (final k in [
                      'label',
                      'kind',
                      'detail',
                      'labelDetails',
                      'insertText',
                      'textEdit',
                    ])
                      if (item[k] != null) k: item[k],
                  },
              ],
            },
          );
        }

        final first = await complete();
        for (var i = 0; i < 2; i++) {
          await complete();
        }
        final times = <int>[];
        for (var i = 0; i < samples; i++) {
          times.add((await complete()).micros);
        }
        completions.add({
          'probe': probe.name,
          'analysisReadyMicros': analysisReadyMicros,
          'firstRequestMicros': first.micros,
          'warm': _stats(times),
          'response': first.result,
          'requiredLabels': probe.required,
          'forbiddenLabels': probe.forbidden,
        });
        stdout.writeln('  completion: ${probe.name}');
        if (probe.file == 'lib/schema.dart') {
          await fixture.write('lib/schema.dart', source);
          server.open(schema.path, source);
        }
      }
      final client = fixture.file('lib/client.dart');
      final diagnosticResults = <Map<String, Object?>>[];
      for (final (name, body, code, token) in [
        (
          'create_type',
          "await db.row0.create(title: 123, status: Status.pending);",
          'argument_type_not_assignable',
          '123',
        ),
        (
          'predicate_type',
          "db.row0.where((r) => r.score.eq(.value('wrong')));",
          'argument_type_not_assignable',
          "'wrong'",
        ),
        (
          'selected_result',
          "final rows = await db.row0.select((r) => r.title).get(); final int wrong = rows.first; print(wrong);",
          'invalid_assignment',
          'rows.first',
        ),
        (
          'missing_selected_field',
          "final rows = await db.row0.select((r) => (r.id,r.title).map((id,title) => (id:id,title:title))).get(); print(rows.first.score);",
          'undefined_getter',
          'score',
        ),
      ]) {
        final text = _client(body), watch = Stopwatch()..start();
        final offset = text.lastIndexOf(token);
        final expectedRange = {
          'start': editorPosition(text, offset),
          'end': editorPosition(text, offset + token.length),
        };
        final version = server.open(client.path, text);
        final event = await server.waitDiagnostics(
          client.path,
          version,
          matches: (d) => d.any(
            (e) =>
                e['code'] == code &&
                _sameRange(e['range'] as Map<String, Object?>, expectedRange),
          ),
        );
        diagnosticResults.add({
          'probe': name,
          'micros': watch.elapsedMicroseconds,
          'version': version,
          'expectedCode': code,
          'expectedRange': expectedRange,
          'diagnostics': event['diagnostics'],
        });
        stdout.writeln('  diagnostic: $name');
      }
      final clean = _client(
        "await db.row0.create(title: 'ok', status: Status.pending);",
      );
      final repair = Stopwatch()..start();
      final cleanVersion = server.open(client.path, clean);
      await server.waitDiagnostics(
        client.path,
        cleanVersion,
        matches: _noErrors,
      );
      final repairMicros = repair.elapsedMicroseconds;
      await fixture.write('lib/client.dart', clean);
      final renameStartup = Stopwatch()..start();
      if (!sameSession) {
        await server.close();
        server = await EditorServer.start(fixture.directory.path);
        await server.ready();
      }
      final renameStartupMicros = sameSession
          ? 0
          : renameStartup.elapsedMicroseconds;
      final renameServerPid = server.process.pid;
      final symbols = fixture.file('lib/symbols.dart');
      server.open(symbols.path, _symbols);
      final renames = <Map<String, Object?>>[];
      for (final (name, marker, newName) in [
        ('model_handle', 'Model person', 'employee'),
        ('schema_field', 'managerId:', 'supervisorId'),
      ]) {
        final text = await symbols.readAsString();
        final offset = text.indexOf(marker) + marker.lastIndexOf(' ') + 1;
        if (!text.contains(marker)) {
          throw StateError('Missing rename marker.');
        }
        final watch = Stopwatch()..start();
        final location = editorLocation(symbols.path, text, offset);
        stdout.writeln('  requesting rename: $name');
        Object? prepare, response;
        Map<String, Object?>? error;
        try {
          prepare = await server.request(
            'textDocument/prepareRename',
            location,
          );
          response = await server.request('textDocument/rename', {
            ...location,
            'newName': newName,
          });
        } on EditorError catch (e) {
          error = e.response;
        }
        final micros = watch.elapsedMicroseconds;
        Map<String, Object?>? applied;
        if (response is Map<String, Object?>) {
          applied = await _applyRename(fixture, server, response);
        }
        final status = error != null
            ? 'rejected'
            : applied == null
            ? 'unavailable'
            : 'applied';
        if (name == 'model_handle' &&
            (applied?['lib/symbols.dart'] as Map?)?['edits'] != 3) {
          throw StateError('Unexpected $name rename: $response / $error');
        }
        renames.add({
          'probe': name,
          'status': status,
          'micros': micros,
          'prepare': prepare,
          'error': error,
          'workspaceEdit': _relative(response, fixture.directory),
          'applied': applied,
        });
        stdout.writeln('  rename: $name ($status)');
      }
      // A valid Dart selector may still violate the ORM's restricted selector AST.
      final invalid =
          "$source\nfinal invalid = model('invalid', (id: integer(),), indexes: (r) => [index([r.id], name: 'invalid_index')]);\n";
      await fixture.write('lib/schema.dart', invalid);
      server.open(schema.path, invalid);
      final dartAnalysis = await fixture.run(['analyze', 'lib/schema.dart']);
      String? generationError;
      try {
        await generateSchema(schema.path);
      } on GenerationException catch (e) {
        generationError = e.message;
      }
      if (generationError == null) {
        throw StateError('The invalid selector passed generation.');
      }
      await fixture.write('lib/schema.dart', source);
      server.open(schema.path, source);
      await server.close();
      server = null;
      final analysis = await fixture.run(['analyze', 'lib']);
      results.add({
        'models': models,
        'sessionPids': {
          'diagnostics': diagnosticServerPid,
          'renames': renameServerPid,
        },
        'sourceBytes': utf8.encode(source).length,
        'generatedBytes': generatedBytes,
        'initializeMicros': initializeMicros,
        'projectReadyMicros': projectReadyMicros,
        'completions': completions,
        'diagnostics': diagnosticResults,
        'repairMicros': repairMicros,
        'renameServerStartupMicros': renameStartupMicros,
        'symbolRenames': renames,
        'ormRule': {
          'dartAnalysisMilliseconds': dartAnalysis.milliseconds,
          'dartAnalysisOutput': dartAnalysis.output,
          'generatorError': generationError,
        },
        'finalAnalyzeMilliseconds': analysis.milliseconds,
      });
      stdout.writeln(
        'Verified completion, diagnostics and rename responses for $models models.',
      );
    } finally {
      await server?.close();
      await fixture.dispose();
    }
  }
  final source = await Process.run('git', ['rev-parse', 'HEAD']);
  final cpu = await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string']);
  final report = {
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
    'runtimeSourceCommit': source.stdout.toString().trim(),
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'cpu': cpu.stdout.toString().trim(),
    'smoke': smoke,
    'sameSession': sameSession,
    'samplesPerWarmProbe': samples,
    'harnessSha256': {
      for (final p in [
        'tool/benchmark_editor.dart',
        'tool/src/editor_server.dart',
        'tool/src/build_fixture.dart',
      ])
        p: sha256.convert(await File(p).readAsBytes()).toString(),
    },
    'scope':
        'Direct stdio LSP client against the installed Dart Analysis Server, isolated consumer packages and real generated APIs; no database. Includes client transport/JSON costs, excludes GUI/plugin rendering and dependency download. ${sameSession ? 'Each scale retains the same server across completion, deliberate errors, repair and symbol renames; PIDs are recorded.' : 'Each scale uses one fresh server for completion/diagnostics and another for symbol renames.'} Startup and initial project analysis are measured separately from completion. First completion follows a fresh diagnostic for the incomplete source and is not a cold OS/cache measurement. Warm probes use unchanged documents after two unrecorded warmups. Diagnostic probes serialize changes and await a fresh notification; this SDK omits document versions. Final CLI analysis verifies the edited sources. Rename probes use model handles and named column declarations, including self and forward references. Regeneration remains a separate step after schema edits.',
    'limits': [
      if (!sameSession) 'This capture restarts the server for renames and does not establish mixed-session rename after diagnostic recovery.',
      'Named Record field rename support depends on the SDK; inspect each probe response. A successful bounded sequence does not establish every IDE/plugin workflow.',
    ],
    'results': results,
  };
  final output = File(
    smoke
        ? '.dart_tool/benchmarks/editor${sameSession ? '-recovery' : ''}-smoke.json'
        : '.dart_tool/benchmarks/editor${sameSession ? '-recovery' : ''}.json',
  );
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln('Saved ${output.path}');
}

String _client(String body) =>
    "import 'package:orm/orm.dart';\nimport 'schema.orm.dart';\nimport 'models.dart';\nFuture<void> read(Database<Backend> db) async { $body }\n";
bool _noErrors(List<Map<String, Object?>> diagnostics) =>
    diagnostics.every((d) => d['severity'] != 1);
bool _sameRange(Map<String, Object?> actual, Map<String, Object?> expected) =>
    ['start', 'end'].every(
      (key) => ['line', 'character'].every(
        (axis) => (actual[key] as Map)[axis] == (expected[key] as Map)[axis],
      ),
    );
Map<String, Object?> _stats(List<int> times) {
  final sorted = [...times]..sort();
  return {
    'samplesMicros': times,
    'p50Micros': sorted[(times.length * .5).ceil() - 1],
    'p95Micros': sorted[(times.length * .95).ceil() - 1],
  };
}

const _symbols = '''
import 'package:orm/schema.dart';
final Model person = model('people', (
  id: identity(), managerId: integer().nullable(),
), relations: (p) => (manager: references(p.managerId, () => person),));
final report = model('reports', (id: identity(), authorId: integer()),
  relations: (r) => (author: references(r.authorId, () => person),));
''';

Object? _relative(Object? value, Directory root) => switch (value) {
  String() => value.replaceAll(root.uri.toString(), 'fixture/'),
  List() => value.map((e) => _relative(e, root)).toList(),
  Map() => {
    for (final e in value.entries)
      _relative(e.key, root).toString(): _relative(e.value, root),
  },
  _ => value,
};
Future<Map<String, Object?>> _applyRename(
  BuildFixture fixture,
  EditorServer server,
  Map<String, Object?> edit,
) async {
  final changes = <String, List<Map<String, Object?>>>{};
  if (edit['changes'] case final Map<String, Object?> changeMap) {
    for (final e in changeMap.entries) {
      changes[e.key] = (e.value as List).cast<Map<String, Object?>>();
    }
  }
  if (edit['documentChanges'] case final List<Object?> documents) {
    for (final d in documents.cast<Map<String, Object?>>()) {
      if (d.containsKey('kind')) {
        throw StateError('Unexpected resource operation.');
      }
      changes[(d['textDocument'] as Map)['uri'] as String] =
          (d['edits'] as List).cast<Map<String, Object?>>();
    }
  }
  final result = <String, Object?>{};
  for (final entry in changes.entries) {
    final file = File.fromUri(Uri.parse(entry.key));
    if (!file.absolute.path.startsWith('${fixture.directory.absolute.path}/')) {
      throw StateError('Rename escaped the disposable fixture.');
    }
    var text = await file.readAsString();
    int offset(Map<String, Object?> p) {
      final lines = text.split('\n');
      return lines.take(p['line'] as int).fold(0, (n, l) => n + l.length + 1) +
          (p['character'] as int);
    }

    final edits = [
      for (final e in entry.value)
        (
          start: offset((e['range'] as Map)['start'] as Map<String, Object?>),
          end: offset((e['range'] as Map)['end'] as Map<String, Object?>),
          text: e['newText'] as String,
        ),
    ]..sort((a, b) => b.start.compareTo(a.start));
    for (final e in edits) {
      text = text.replaceRange(e.start, e.end, e.text);
    }
    await file.writeAsString(text);
    server.open(file.path, text);
    result[file.path.substring(fixture.directory.path.length + 1)] = {
      'edits': edits.length,
      'result': text,
    };
  }
  return result;
}
