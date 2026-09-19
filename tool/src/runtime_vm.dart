import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A small JSON-RPC client for the SDK service protocol. Runs in the controller
/// process so JSON decoding and service responses are outside the measured heap.
final class RuntimeVm {
  final WebSocket socket;
  final String isolate;
  final _pending = <int, Completer<Map<String, Object?>>>{};
  final classes = <int, String>{};
  late final StreamSubscription<Object?> _subscription;
  var _next = 0;
  RuntimeVm._(this.socket, this.isolate) {
    _subscription = socket.listen((message) {
      final json = jsonDecode(message as String) as Map<String, Object?>;
      final pending = _pending.remove(json['id']);
      if (pending == null) return;
      if (json['error'] case final error?) {
        pending.completeError(StateError('$error'));
      } else {
        pending.complete(json['result'] as Map<String, Object?>);
      }
    });
  }

  static Future<RuntimeVm> connect(String uri, String isolate) async {
    final url = Uri.parse(uri).resolve('ws').replace(scheme: 'ws');
    return RuntimeVm._(await WebSocket.connect('$url'), isolate);
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    final id = ++_next, result = Completer<Map<String, Object?>>();
    _pending[id] = result;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': {'isolateId': isolate, ...params},
      }),
    );
    return result.future.timeout(const Duration(seconds: 30));
  }

  Future<Map<String, Object?>> heap() async {
    final profile = await call('getAllocationProfile', {'gc': true});
    // Dart 3.13.3 emits current counts for the accumulated fields as well.
    // Only use fields whose live-heap meaning matches the implementation.
    return {
      'memoryUsage': profile['memoryUsage'],
      'gcTimestamp': profile['dateLastServiceGC'],
      'classes': [
        for (final row
            in (profile['members'] as List).cast<Map<String, Object?>>())
          if ({
            '_Record',
            '_List',
            '_GrowableList',
            '_Map',
            '_SelectionPlan',
          }.contains((row['class'] as Map)['name']))
            {
              'name': (row['class'] as Map)['name'],
              'instancesCurrent': row['instancesCurrent'],
              'bytesCurrent': row['bytesCurrent'],
            },
      ],
    };
  }

  Future<void> trace(bool enable) async {
    if (classes.isEmpty) {
      final response = await call('getClassList');
      for (final row
          in (response['classes'] as List).cast<Map<String, Object?>>()) {
        if ({
          '_Record',
          '_List',
          '_GrowableList',
          '_Map',
          '_SelectionPlan',
          '_Combined',
        }.contains(row['name'])) {
          classes[int.parse((row['id'] as String).split('/').last)] =
              row['name'] as String;
        }
      }
      if (!classes.containsValue('_Record')) {
        throw StateError('Record allocation class not found.');
      }
    }
    for (final id in classes.keys) {
      await call('setTraceClassAllocation', {
        'classId': 'classes/$id',
        'enable': enable,
      });
    }
  }

  Future<Map<String, Object?>> allocations(int start, int end) async {
    final profile = await call('getAllocationTraces', {
      'timeOriginMicros': start,
      'timeExtentMicros': end - start,
    });
    final samples = (profile['samples'] as List).cast<Map<String, Object?>>();
    final counts = <String, int>{}, topFrames = <String, int>{};
    final functions = profile['functions'] as List;
    var truncated = 0;
    for (final sample in samples) {
      final name = classes[sample['classId']] ?? 'class/${sample['classId']}';
      counts.update(name, (n) => n + 1, ifAbsent: () => 1);
      if (sample['truncated'] == true) truncated++;
      final stack = sample['stack'] as List;
      if (stack.isNotEmpty) {
        final function =
            (functions[stack.first as int] as Map)['function'] as Map;
        final frame = function['name'] as String? ?? 'unknown';
        topFrames.update(frame, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    if (samples.isEmpty) {
      throw StateError('Allocation tracing returned no samples.');
    }
    final sortedFrames = topFrames.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'tracedClasses': classes.values.toList(),
      'sampleCount': samples.length,
      'counts': counts,
      'truncatedStacks': truncated,
      'topAllocationFrames': [
        for (final e in sortedFrames.take(12))
          {'function': e.key, 'samples': e.value},
      ],
      'scope': 'Selected allocation traces in the main query isolate; not all object allocations or allocated bytes. Timing is measured separately with tracing disabled.',
    };
  }

  Future<void> close() async {
    await _subscription.cancel();
    await socket.close();
  }
}
