import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_style/dart_style.dart';
import 'package:orm/generate.dart';

import 'src/authoring.dart';
import 'src/authoring_fixture.dart';
import 'src/build_fixture.dart';
import 'src/editor_server.dart';

Future<void> main(List<String> args) async {
  if (args.any((a) => a != '--smoke')) {
    throw ArgumentError('Use --smoke or no arguments.');
  }
  final smoke = args.contains('--smoke');
  final results = <Map<String, Object?>>[];
  final expected = <String, ({String dart, String snapshot, String schema})>{};
  for (final form in smoke ? ['record'] : authoringSources.keys) {
    stdout.writeln('Checking $form authoring...');
    final fixture = await BuildFixture.create(ormPath: Directory.current.path);
    EditorServer? editor;
    try {
      final author = fixture.file('lib/author.dart');
      final original = DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format('// @dart=3.13\n${authoringSources[form]!}');
      Future<({Map<String, Object?> report, GeneratedSchema generated})> emit(
        String variant,
        String source,
      ) async {
        await fixture.write('lib/author.dart', source);
        final watch = Stopwatch()..start();
        final normalized = await normalizeAuthoring(author.path, form);
        final normalizeMicros = watch.elapsedMicroseconds;
        await fixture.write('lib/schema.dart', normalized.text);
        final generated = await generateSchema(
          fixture.file('lib/schema.dart').path,
        );
        final generationMicros = watch.elapsedMicroseconds - normalizeMicros;
        final snapshot = jsonEncode(generated.snapshot);
        final baseline = expected[variant];
        if (baseline == null) {
          expected[variant] = (
            dart: generated.dart,
            snapshot: snapshot,
            schema: normalized.text,
          );
        } else if (baseline.dart != generated.dart ||
            baseline.snapshot != snapshot ||
            baseline.schema != normalized.text) {
          throw StateError(
            '$form/$variant differs from the Record API or snapshot.',
          );
        }
        await fixture.write('lib/schema.orm.dart', generated.dart);
        await fixture.write('lib/schema.orm.json', snapshot);
        return (
          generated: generated,
          report: {
            'sourceBytes': utf8.encode(source).length,
            'sourceLines': source.trimRight().split('\n').length,
            'modelDeclarationBytes': utf8
                .encode(source.substring(0, source.indexOf('final users =')))
                .length,
            'modelDeclarationLines': source
                .substring(0, source.indexOf('final users ='))
                .trimRight()
                .split('\n')
                .length,
            'normalizeMicros': normalizeMicros,
            'generationMicros': generationMicros,
            'schemaSha256': _hash(normalized.text),
            'clientSha256': _hash(generated.dart),
            'snapshotSha256': _hash(snapshot),
          },
        );
      }

      final base = await emit('base', original);
      _checkSnapshot(base.generated.snapshot);
      await fixture.write('lib/client.dart', authoringConsumer);
      final initialAnalysis = await fixture.run(['analyze', 'lib']);

      final changed = form == 'table'
          ? original.replaceFirst(
              "Column('bio', Codecs.text.nullable()",
              "Column('bio', Codecs.integer.nullable()",
            )
          : original.replaceFirst('String? bio', 'int? bio');
      if (changed == original) {
        throw StateError('Field edit did not change $form source.');
      }
      final fieldEdit = await emit('field_type', changed);
      final fieldErrors = await _consumerErrors(fixture, 'invalid_assignment');
      await fixture.write(
        'lib/client.dart',
        authoringConsumer.replaceFirst('String? bio', 'int? bio'),
      );
      await fixture.run(['analyze', 'lib']);

      await emit('base', original);
      await fixture.write('lib/client.dart', authoringConsumer);
      editor = await EditorServer.start(fixture.directory.path);
      await editor.ready();
      editor.open(author.path, original);
      final marker = form == 'table' ? 'late final email' : 'String email';
      final offset = original.indexOf(marker) + marker.lastIndexOf(' ') + 1;
      if (!original.contains(marker)) {
        throw StateError('Missing rename marker.');
      }
      final location = editorLocation(author.path, original, offset);
      final timer = Stopwatch()..start();
      final prepared = await editor.request(
        'textDocument/prepareRename',
        location,
      );
      final edits = await editor.request('textDocument/rename', {
        ...location,
        'newName': 'contactEmail',
      });
      final renameMicros = timer.elapsedMicroseconds;
      String renamed;
      if (form == 'record') {
        if (prepared != null || edits != null) {
          throw StateError(
            'Record rename behavior changed; review the experiment.',
          );
        }
        renamed = original
            .replaceFirst('String email', 'String contactEmail')
            .replaceAll('u.email', 'u.contactEmail');
      } else {
        renamed = _renameOneFile(
          author.path,
          original,
          edits as Map<String, Object?>,
        );
        if (!renamed.contains('u.contactEmail') ||
            !renamed.contains("'email'")) {
          throw StateError(
            'Rename missed constraints or changed physical mapping.',
          );
        }
      }
      await editor.close();
      editor = null;
      final rename = await emit('rename', renamed);
      if (rename.report['snapshotSha256'] != base.report['snapshotSha256']) {
        throw StateError('A Dart field rename changed the physical schema.');
      }
      final renameErrors = await _consumerErrors(fixture, 'undefined_getter');
      await fixture.write(
        'lib/client.dart',
        authoringConsumer
            .replaceFirst(
              "email: 'a@example.com'",
              "contactEmail: 'a@example.com'",
            )
            .replaceAll('user.email', 'user.contactEmail')
            .replaceAll('u.email', 'u.contactEmail'),
      );
      await fixture.run(['analyze', 'lib']);

      final failures = <Map<String, Object?>>[];
      for (final (name, source, phase, fragment) in [
        (
          'unknown_field',
          original.replaceAll('u.email', 'u.absent'),
          'dart',
          'absent',
        ),
        (
          'computed_selector',
          '$original\nfinal invalid = users.index((u) => 0);\n',
          'generator',
          '0',
        ),
        (
          'duplicate_key_field',
          '$original\nfinal invalid = users.index((u) => (u.id, u.id));\n',
          'generator',
          'u.id',
        ),
        (
          'non_unique_target',
          original.replaceFirst(RegExp(r'final userIdentity = [^;]+;\n'), ''),
          'generator',
          'posts',
        ),
        if (form == 'primary')
          (
            'constructor_logic',
            original.replaceRange(
              original.indexOf(');'),
              original.indexOf(');') + 2,
              ") { this { throw StateError('must not execute'); } }",
            ),
            'authoring',
            'final class User',
          ),
        if (form == 'table')
          (
            'custom_codec',
            original.replaceFirst(
              'Codecs.text.nullable()',
              'Codecs.text.map((v) => v, (v) => v).nullable()',
            ),
            'authoring',
            'Codecs.text',
          ),
      ]) {
        await fixture.write('lib/author.dart', source);
        AuthoringFailure? failure;
        try {
          final normalized = await normalizeAuthoring(author.path, form);
          await fixture.write('lib/schema.dart', normalized.text);
          try {
            await generateSchema(fixture.file('lib/schema.dart').path);
          } on GenerationException catch (e) {
            final match = RegExp(r'\(offset (\d+)\)').firstMatch(e.message);
            if (match == null) rethrow;
            failure = AuthoringFailure(
              'generator',
              name,
              e.message,
              normalized.originalOffset(int.parse(match[1]!)),
              fragment.length,
            );
          }
        } on AuthoringFailure catch (e) {
          failure = e;
        }
        if (failure == null ||
            failure.phase != phase ||
            !source.substring(failure.offset).startsWith(fragment)) {
          throw StateError(
            '$form/$name has the wrong error location: $failure',
          );
        }
        failures.add({'case': name, ...failure.toJson(source)});
      }
      await emit('base', original);
      await fixture.write('lib/client.dart', authoringConsumer);
      final finalAnalysis = await fixture.run(['analyze', 'lib']);
      results.add({
        'form': form,
        'source': original,
        'base': base.report,
        'initialAnalyzeMs': initialAnalysis.milliseconds,
        'fieldTypeEdit': {
          ...fieldEdit.report,
          'source': changed,
          'staleConsumerDiagnostics': fieldErrors,
        },
        'fieldRename': {
          ...rename.report,
          'source': renamed,
          'method': form == 'record' ? 'manual' : 'lsp',
          'lspMicros': renameMicros,
          'prepare': prepared,
          'edit': _relative(edits, fixture.directory),
          'staleConsumerDiagnostics': renameErrors,
          'physicalSnapshotUnchanged': true,
        },
        'errors': failures,
        'finalAnalyzeMs': finalAnalysis.milliseconds,
      });
      stdout.writeln(
        'Verified $form: identical APIs, typed consumers, rename and source errors.',
      );
    } finally {
      await editor?.close();
      await fixture.dispose();
    }
  }
  final commit = await Process.run('git', ['rev-parse', 'HEAD']);
  final report = {
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
    'runtimeSourceCommit': commit.stdout.toString().trim(),
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'smoke': smoke,
    'scope': 'Controlled User/Post/Profile/Follow declaration-frontends experiment. All forms are resolved, normalized to the same Record schema, and sent through the unchanged production generator. Class/table inputs describe schema only; arbitrary constructors/methods and nominal runtime row objects are not implemented. No database execution or runtime performance claim. One timing observation per stage, warm SDK/pub/OS caches, offline dependency resolution excluded. Physical snapshots and generated Dart must be byte-identical for each variant. Record field rename is manual; class/table schema references use a clean LSP server. Generated-client references are independently checked and repaired after regeneration.',
    'harnessSha256': {
      for (final p in [
        'tool/compare_authoring.dart',
        'tool/src/authoring.dart',
        'tool/src/authoring_fixture.dart',
        'tool/src/build_fixture.dart',
        'tool/src/editor_server.dart',
      ])
        p: _hash(await File(p).readAsString()),
    },
    'outputs': {
      for (final entry in expected.entries)
        entry.key: {
          'schema': entry.value.schema,
          'clientSha256': _hash(entry.value.dart),
          'snapshot': jsonDecode(entry.value.snapshot),
        },
    },
    'results': results,
  };
  final path = smoke
      ? '.dart_tool/authoring-smoke.json'
      : 'research/benchmarks/authoring.json';
  await File(path)
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  stdout.writeln('Saved $path');
}

String _hash(String text) => sha256.convert(utf8.encode(text)).toString();

Future<List<String>> _consumerErrors(
  BuildFixture fixture,
  String requiredCode,
) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    'analyze',
    '--format=machine',
    'lib/client.dart',
  ], workingDirectory: fixture.directory.path);
  final output = '${result.stdout}\n${result.stderr}';
  final lines = output
      .split('\n')
      .where((l) => l.startsWith('ERROR|'))
      .map((l) => l.replaceAll(fixture.directory.path, 'fixture'))
      .toList();
  if (result.exitCode == 0 ||
      !lines.any((l) => l.toLowerCase().contains('|$requiredCode|'))) {
    throw StateError('Missing stale-client diagnostic $requiredCode: $output');
  }
  return lines;
}

void _checkSnapshot(Map<String, Object?> snapshot) {
  final tables = (snapshot['tables'] as List).cast<Map<String, Object?>>();
  if (tables.length != 4 ||
      tables.fold(0, (n, t) => n + (t['foreignKeys'] as List).length) != 4 ||
      (tables.singleWhere((t) => t['name'] == 'follows')['primaryKey'] as List)
              .length !=
          3 ||
      (tables.singleWhere((t) => t['name'] == 'profiles')['primaryKey'] as List)
              .length !=
          2) {
    throw StateError(
      'The fixture lost required relation/key metadata: $snapshot',
    );
  }
}

String _renameOneFile(String path, String source, Map<String, Object?> edit) {
  final documents = (edit['documentChanges'] as List)
      .cast<Map<String, Object?>>();
  if (documents.length != 1 ||
      (documents.single['textDocument'] as Map)['uri'] !=
          File(path).absolute.uri.toString()) {
    throw StateError('Rename escaped its authoring source: $edit');
  }
  int offset(Map<String, Object?> p) =>
      source
          .split('\n')
          .take(p['line'] as int)
          .fold(0, (n, l) => n + l.length + 1) +
      (p['character'] as int);
  final edits = [
    for (final e
        in (documents.single['edits'] as List).cast<Map<String, Object?>>())
      (
        start: offset((e['range'] as Map)['start'] as Map<String, Object?>),
        end: offset((e['range'] as Map)['end'] as Map<String, Object?>),
        text: e['newText'] as String,
      ),
  ]..sort((a, b) => b.start.compareTo(a.start));
  if (edits.length != 2) {
    throw StateError(
      'Expected declaration and unique-key reference rename: $edit',
    );
  }
  for (final e in edits) {
    source = source.replaceRange(e.start, e.end, e.text);
  }
  return source;
}

Object? _relative(Object? value, Directory root) => switch (value) {
  String() => value.replaceAll(root.uri.toString(), 'fixture/'),
  List() => value.map((e) => _relative(e, root)).toList(),
  Map() => {
    for (final e in value.entries)
      _relative(e.key, root).toString(): _relative(e.value, root),
  },
  _ => value,
};
