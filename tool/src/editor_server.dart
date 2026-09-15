import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A small stdio LSP client for measuring the SDK used by Dart editors.
final class EditorServer {
  final Process process;
  final _pending = <int, Completer<Object?>>{};
  final _bytes = <int>[];
  final _versions = <String, int>{};
  final _editRevisions = <String, int>{};
  final diagnostics = <String, Map<String, Object?>>{};
  final stderr = StringBuffer();
  final notifications = <Map<String, Object?>>[];
  final _initialAnalysis = Completer<void>();
  Completer<void>? _changed;
  int _id = 0, revision = 0;
  int? _exitCode;
  late final StreamSubscription<List<int>> _out;
  late final StreamSubscription<String> _err;
  EditorServer._(this.process) {
    _out = process.stdout.listen(_receive);
    _err = process.stderr.transform(utf8.decoder).listen(stderr.write);
    unawaited(
      process.exitCode.then((code) {
        _exitCode = code;
        for (final pending in _pending.values) {
          pending.completeError(StateError('LSP exited $code: $stderr'));
        }
        _pending.clear();
        _signal();
      }),
    );
  }

  static Future<EditorServer> start(String directory) async {
    final server = EditorServer._(
      await Process.start(Platform.resolvedExecutable, [
        'language-server',
        '--protocol=lsp',
        '--client-id=orm-editor-benchmark',
      ], workingDirectory: directory),
    );
    try {
      final root = Directory(directory).uri.toString();
      await server.request('initialize', {
        'processId': pid,
        'rootUri': root,
        'workspaceFolders': [
          {'uri': root, 'name': 'orm-editor-fixture'},
        ],
        'capabilities': {
          'window': {'workDoneProgress': true},
          'general': {
            'positionEncodings': ['utf-16'],
          },
          'workspace': {
            'configuration': true,
            'workspaceEdit': {'documentChanges': true},
          },
          'textDocument': {
            'completion': {
              'completionItem': {
                'snippetSupport': true,
                'labelDetailsSupport': true,
              },
            },
            'publishDiagnostics': {'versionSupport': true},
            'rename': {'prepareSupport': true},
          },
        },
        'initializationOptions': {'suggestFromUnimportedLibraries': false},
      });
      server.notify('initialized', {});
      return server;
    } catch (_) {
      await server.close();
      rethrow;
    }
  }

  void _send(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
    process.stdin.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
    process.stdin.add(body);
  }

  void notify(String method, Object? params) =>
      _send({'method': method, 'params': params});
  Future<Object?> request(String method, Object? params) async {
    if (_exitCode != null) throw StateError('LSP already exited $_exitCode.');
    final id = ++_id, result = Completer<Object?>();
    _pending[id] = result;
    _send({'id': id, 'method': method, 'params': params});
    try {
      return await result.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw StateError(
            'Timed out: $method $params; notifications=$notifications; stderr=$stderr',
          );
        },
      );
    } finally {
      _pending.remove(id);
    }
  }

  void _receive(List<int> bytes) {
    _bytes.addAll(bytes);
    while (true) {
      var headerEnd = -1;
      for (var i = 0; i + 3 < _bytes.length; i++) {
        if (_bytes[i] == 13 &&
            _bytes[i + 1] == 10 &&
            _bytes[i + 2] == 13 &&
            _bytes[i + 3] == 10) {
          headerEnd = i;
          break;
        }
      }
      if (headerEnd < 0) return;
      final header = ascii.decode(_bytes.sublist(0, headerEnd));
      final length = int.parse(
        RegExp(
          r'Content-Length: (\d+)',
          caseSensitive: false,
        ).firstMatch(header)![1]!,
      );
      final end = headerEnd + 4 + length;
      if (_bytes.length < end) return;
      final message = jsonDecode(
        utf8.decode(_bytes.sublist(headerEnd + 4, end)),
      ) as Map<String, Object?>;
      _bytes.removeRange(0, end);
      _handle(message);
    }
  }

  void _handle(Map<String, Object?> message) {
    if (message['method'] case final String method) {
      if (message.containsKey('id')) {
        notifications.add(message);
        if (notifications.length > 30) notifications.removeAt(0);
        final params = message['params'] as Map<String, Object?>?;
        final result = method == 'workspace/configuration'
            ? [
                for (final _ in params!['items'] as List)
                  {'completeFunctionCalls': true, 'documentation': 'full'},
              ]
            : null;
        _send({'id': message['id'], 'result': result});
      } else if (method == 'textDocument/publishDiagnostics') {
        final params = message['params'] as Map<String, Object?>;
        diagnostics[params['uri'] as String] = {
          ...params,
          'revision': ++revision,
        };
        _signal();
      } else {
        if (method == r'$/progress' &&
            (message['params'] as Map)['token'] == 'ANALYZING' &&
            ((message['params'] as Map)['value'] as Map)['kind'] == 'end' &&
            !_initialAnalysis.isCompleted) {
          _initialAnalysis.complete();
        }
        notifications.add(message);
        if (notifications.length > 30) notifications.removeAt(0);
        if (Platform.environment['ORM_EDITOR_DEBUG'] == '1') {
          stdout.writeln('LSP: $message');
        }
      }
    } else {
      final pending = _pending.remove(message['id']);
      if (pending == null) return;
      if (message['error'] case final Map<String, Object?> error) {
        pending.completeError(EditorError(error));
      } else {
        pending.complete(message['result']);
      }
    }
  }

  void _signal() {
    _changed?.complete();
    _changed = null;
  }

  Future<void> ready() =>
      _initialAnalysis.future.timeout(const Duration(seconds: 60));

  int open(String path, String text) {
    final uri = File(path).absolute.uri.toString();
    final prior = _versions[uri], version = (prior ?? 0) + 1;
    _versions[uri] = version;
    _editRevisions[uri] = revision;
    if (prior == null) {
      notify('textDocument/didOpen', {
        'textDocument': {
          'uri': uri,
          'languageId': 'dart',
          'version': version,
          'text': text,
        },
      });
    } else {
      notify('textDocument/didChange', {
        'textDocument': {'uri': uri, 'version': version},
        'contentChanges': [
          {'text': text},
        ],
      });
    }
    return version;
  }

  Future<Map<String, Object?>> waitDiagnostics(
    String path,
    int version, {
    required bool Function(List<Map<String, Object?>>) matches,
  }) async {
    final uri = File(path).absolute.uri.toString();
    Future<Map<String, Object?>> wait() async {
      while (true) {
        if (_exitCode != null) {
          throw StateError('LSP exited $_exitCode: $stderr');
        }
        // Dart omits versions and suppresses already-empty diagnostics. Call
        // this for deliberate errors and their repair, with serialized edits.
        final current = diagnostics[uri];
        if (current != null &&
            _versions[uri] == version &&
            (current['revision'] as int) > _editRevisions[uri]! &&
            matches(
              (current['diagnostics'] as List).cast<Map<String, Object?>>(),
            )) {
          return current;
        }
        await (_changed ??= Completer<void>()).future;
      }
    }

    return wait().timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw StateError(
          'No matching diagnostics for $uri version $version: $diagnostics; notifications=$notifications; stderr=$stderr',
        );
      },
    );
  }

  Future<void> close() async {
    if (_exitCode == null) {
      try {
        await request('shutdown', null);
        notify('exit', null);
      } catch (_) {
        process.kill();
      }
      await process.stdin.close();
      try {
        await process.exitCode.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
    }
    await _out.cancel();
    await _err.cancel();
  }
}

final class EditorError(final Map<String, Object?> response)
    implements Exception {
  @override
  String toString() => jsonEncode(response);
}

Map<String, int> editorPosition(String source, int offset) {
  final before = source.substring(0, offset), last = before.lastIndexOf('\n');
  return {
    'line': '\n'.allMatches(before).length,
    'character': offset - last - 1,
  };
}

Map<String, Object?> editorLocation(String path, String source, int offset) => {
  'textDocument': {'uri': File(path).absolute.uri.toString()},
  'position': editorPosition(source, offset),
};
