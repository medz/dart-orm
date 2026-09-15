import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:orm/migrate.dart';
import 'package:orm/postgres.dart';
import 'package:orm/sqlite.dart';

import '../example/schema.orm.dart';
import 'src/runtime_cases.dart';
import 'src/runtime_relay.dart';
import 'src/runtime_vm.dart';

const _prefix = '@@orm-runtime ';

Future<void> main(List<String> args) async {
  if (args.firstOrNull == '--worker') {
    await _worker(args[1]);
    return;
  }
  final smoke = args.contains('--smoke');
  final samples = smoke ? 5 : 200, warmup = smoke ? 2 : 20;
  final url = Platform.environment['ORM_TEST_POSTGRES'];
  if (url == null) {
    throw StateError(
      'Set ORM_TEST_POSTGRES to a disposable local PostgreSQL database.',
    );
  }
  final endpoint = Uri.parse(url);
  final results = <Map<String, Object?>>[];
  for (final scenario in [
    'sqlite_wal',
    'postgres_loopback',
    'postgres_delay_20ms',
  ]) {
    RuntimeRelay? relay;
    _Worker? worker;
    try {
      if (scenario.startsWith('postgres')) {
        relay = await RuntimeRelay.open(
          endpoint.host,
          endpoint.hasPort ? endpoint.port : 5432,
          Duration.zero,
        );
      }
      worker = await _Worker.start(
        scenario,
        relay == null
            ? null
            : endpoint
                  .replace(host: '127.0.0.1', port: relay.server.port)
                  .toString(),
      );
      final ready = await worker.next();
      if (relay != null && scenario == 'postgres_delay_20ms') {
        relay.oneWayDelay = const Duration(milliseconds: 10);
      }
      final echo = relay == null
          ? null
          : await relayRoundTrips(relay.oneWayDelay, smoke ? 2 : 10);
      final ping = await worker.call({
        'action': 'ping',
        'runs': smoke ? 2 : 10,
      });
      final cases = <Map<String, Object?>>[];
      for (final name in runtimeCases) {
        print('$scenario / $name: paired latency and throughput');
        final latency = await worker.call({
          'action': 'latency',
          'case': name,
          'samples': samples,
          'warmup': warmup,
        });
        final concurrency = await worker.call({
          'action': 'concurrent',
          'case': name,
          'samples': samples,
          'clients': 8,
        });
        final contention = await worker.call({
          'action': 'contention',
          'case': name,
          'samples': smoke ? 8 : 64,
          'clients': 8,
        });
        final probes = <String, Object?>{};
        for (final lane in ['raw', 'orm']) {
          final before = relay?.bytes;
          final probe = await worker.call({
            'action': 'probe',
            'case': name,
            'lane': lane,
          });
          final after = relay?.bytes;
          if (before != null && after != null) {
            probe['postgresProtocolBytes'] = {
              for (final key in before.keys) key: after[key]! - before[key]!,
            };
          }
          probes[lane] = probe;
        }
        final row = <String, Object?>{
          'case': name,
          'latency': latency,
          'concurrent': concurrency,
          'observedContention': contention,
          'probes': probes,
        };
        // Memory/trace runs follow all timing in a fresh process below. Enabling
        // tracing can deoptimize code, so it must not precede later latency cases.
        cases.add(row);
      }
      final info = Map<String, Object?>.of(ready)
        ..remove('serviceUri')
        ..remove('isolateId');
      results.add({
        'scenario': scenario,
        'environment': info,
        'oneWayDelayMs': relay?.oneWayDelay.inMilliseconds ?? 0,
        if (echo != null)
          'echoRoundTripMicros': _stats(echo, echo.fold(0, (sum, n) => sum + n))
            ..remove('operationsPerSecond'),
        'selectOneMicros': ping,
        'cases': cases,
      });
    } finally {
      await worker?.close();
      await relay?.close();
    }
  }
  // Local profiling is sufficient to inspect query-layer object creation;
  // repeating it through a latency relay would not isolate additional Dart work.
  for (final backend in ['sqlite_wal', 'postgres_loopback']) {
    print('$backend: separate heap and allocation trace process');
    final worker = await _Worker.start(backend, url, profile: true);
    RuntimeVm? vm;
    try {
      final ready = await worker.next();
      vm = await RuntimeVm.connect(
        ready['serviceUri'] as String,
        ready['isolateId'] as String,
      );
      for (final name in runtimeCases) {
        await worker.call({
          'action': 'latency',
          'case': name,
          'samples': 2,
          'warmup': warmup,
        });
        await vm.trace(true);
        final memory = <String, Object?>{};
        for (final lane in ['raw', 'orm']) {
          await worker.call({'action': 'clear'});
          final before = await vm.heap();
          final batch = await worker.call({
            'action': 'profile',
            'case': name,
            'lane': lane,
            'runs': 3,
          });
          final traces = await vm.allocations(
            batch['startMicros'] as int,
            batch['endMicros'] as int,
          );
          final after = await vm.heap();
          memory[lane] = {
            'batch': batch,
            'heapBefore': before,
            'heapWithLastResult': after,
            'allocationTraces': traces,
          };
        }
        await vm.trace(false);
        final target = results.singleWhere((r) => r['scenario'] == backend);
        ((target['cases'] as List).cast<Map<String, Object?>>().singleWhere(
          (r) => r['case'] == name,
        ))['memory'] = memory;
      }
    } finally {
      await vm?.close();
      await worker.close();
    }
  }
  final source = await Process.run('git', ['rev-parse', 'HEAD']);
  if (source.exitCode != 0) {
    throw StateError('Cannot identify measured source.');
  }
  final cpu = await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string']);
  final files = [
    'tool/benchmark_runtime.dart',
    'tool/src/runtime_cases.dart',
    'tool/src/runtime_relay.dart',
    'tool/src/runtime_vm.dart',
  ];
  final report = {
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceCommit': source.stdout.toString().trim(),
    'harnessSha256': {
      for (final file in files)
        file: sha256.convert(await File(file).readAsBytes()).toString(),
    },
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'cpu': cpu.stdout.toString().trim(),
    'samplesPerLane': samples,
    'warmupPairs': warmup,
    'smoke': smoke,
    'scope': 'Warm native JIT, reused query objects; raw uses the same public Driver and precompiled identical SQL with manual same-codec mapping. ORM includes compilation. Default hooks and allocation tracing are disabled in timing. Loopback relay has no loss or bandwidth limit; delayed scenario is controlled TCP latency, not a remote-server measurement. PostgreSQL protocol bytes exclude TCP/IP headers. SQLite byte counts are UTF-8 JSON of driver rows, not IPC wire bytes. Heap fields are live isolate-group memory; traces count selected classes only, not total allocated bytes.',
    'fixture': {
      'users': 100,
      'postsPerUser': 10,
      'selectedPostsPerUser': 3,
      'nullableNicknames': true,
      'sqlite': 'temporary file, WAL, warm cache',
      'postgresPool': 4,
      'concurrentClients': 8,
    },
    'results': results,
  };
  final output = File(
    smoke
        ? '.dart_tool/runtime-smoke.json'
        : 'research/benchmarks/runtime.json',
  );
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  print('Verified and saved ${output.path}');
}

final class _Worker {
  final Process process;
  final StreamIterator<String> lines;
  final List<String> errors = [];
  late final StreamSubscription<String> _stderr;
  _Worker._(this.process)
    : lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ) {
    _stderr = process.stderr.transform(utf8.decoder).listen(errors.add);
  }
  static Future<_Worker> start(
    String backend,
    String? url, {
    bool profile = false,
  }) async => _Worker._(
    await Process.start(
      Platform.resolvedExecutable,
      [
        if (profile) '--profiler',
        if (profile) '--sample-buffer-duration=60',
        'run',
        if (profile) '--enable-vm-service=0',
        if (profile) '--no-dds',
        'tool/benchmark_runtime.dart',
        '--worker',
        backend,
      ],
      environment: {'ORM_TEST_POSTGRES': ?url},
    ),
  );
  Future<Map<String, Object?>> next() async {
    while (await lines.moveNext().timeout(const Duration(minutes: 3))) {
      final line = lines.current;
      if (line.startsWith(_prefix)) {
        return jsonDecode(line.substring(_prefix.length))
            as Map<String, Object?>;
      }
    }
    throw StateError('Benchmark worker exited: ${errors.join()}');
  }

  Future<Map<String, Object?>> call(Map<String, Object?> request) {
    process.stdin.writeln(jsonEncode(request));
    return next();
  }

  Future<void> close() async {
    await process.stdin.close();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await lines.cancel();
    await _stderr.cancel();
    if (code != 0) {
      throw StateError('Benchmark worker failed ($code): ${errors.join()}');
    }
  }
}

void _reply(Map<String, Object?> result) =>
    print('$_prefix${jsonEncode(result)}');
Map<String, Object?> _stats(List<int> samples, int wallMicros) {
  final sorted = samples.toList()..sort();
  return {
    'samplesMicros': samples,
    'p50Micros': sorted[(sorted.length * .5).ceil() - 1],
    'p95Micros': sorted[(sorted.length * .95).ceil() - 1],
    'minMicros': sorted.first,
    'maxMicros': sorted.last,
    'wallMicros': wallMicros,
    'operationsPerSecond': samples.length * 1000000 / wallMicros,
  };
}

Future<void> _worker(String backend) async {
  final temp = await Directory.systemTemp.createTemp('orm-runtime-');
  final schema = 'orm_runtime_${DateTime.now().microsecondsSinceEpoch}';
  final Database<Backend> db = backend == 'sqlite_wal'
      ? await sqlite(SqliteOptions.file('${temp.path}/data.sqlite'))
      : postgres(
          PostgresOptions(
            url: Uri.parse(Platform.environment['ORM_TEST_POSTGRES']!),
            tls: .disable,
            schema: schema,
            maxConnections: 4,
          ),
        );
  var created = false;
  List<Object?>? retained;
  try {
    if (backend != 'sqlite_wal') {
      await db.execute(SqlCommand('CREATE SCHEMA "$schema"'));
      created = true;
    }
    await Migrator(db).apply([Migration.create('0001_benchmark', appSchema)]);
    final nick = List.filled(16, 'long nickname 漢字').join();
    final title = List.filled(8, 'post title 漢字').join();
    await db.execute(
      SqlCommand(
        "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100) INSERT INTO users(id,email,nickname,score) SELECT 10000+x, 'user-' || x || '@example.invalid', CASE WHEN x%3=0 THEN NULL ELSE '$nick' END, x%10 FROM n",
      ),
    );
    await db.execute(
      SqlCommand(
        "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1000) INSERT INTO posts(id,author_id,title,created_at) SELECT x, 10001+(x-1)/10, '$title' || x, '2026-01-01 00:00:00+00' FROM n",
      ),
    );
    final cases = {
      for (final name in runtimeCases)
        name: await RuntimeCase.prepare(db, name),
    };
    // Open every PostgreSQL pool slot before concurrency measurements.
    if (backend != 'sqlite_wal') {
      final ready = Completer<void>();
      var leases = 0;
      await Future.wait([
        for (var i = 0; i < 4; i++)
          db.driver.run((c) async {
            await c.execute(SqlCommand('SELECT 1'));
            if (++leases == 4) ready.complete();
            await ready.future;
          }),
      ]);
    }
    final version = (await db.execute(
      SqlCommand(
        backend == 'sqlite_wal'
            ? 'SELECT sqlite_version()'
            : "SELECT current_setting('server_version')",
      ),
    )).rows.single.single;
    _reply({
      'backend': backend,
      'databaseVersion': version,
      'serviceUri': '${(await developer.Service.getInfo()).serverUri}',
      'isolateId': developer.Service.getIsolateId(Isolate.current),
      'pid': pid,
    });
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final request = jsonDecode(line) as Map<String, Object?>;
      final action = request['action'];
      if (action == 'clear') {
        retained = null;
        _reply({});
        continue;
      }
      if (action == 'ping') {
        final samples = <int>[];
        for (var i = 0; i < (request['runs'] as int); i++) {
          final clock = Stopwatch()..start();
          await db.driver.run((c) => c.execute(SqlCommand('SELECT 1')));
          samples.add(clock.elapsedMicroseconds);
        }
        _reply(_stats(samples, samples.fold(0, (sum, n) => sum + n)));
        continue;
      }
      final test = cases[request['case']]!;
      final lane = request['lane'] as String?;
      if (action == 'latency') {
        for (var i = 0; i < (request['warmup'] as int); i++) {
          await test.raw();
          await test.query.get();
        }
        final samples = {'raw': <int>[], 'orm': <int>[]};
        for (var i = 0; i < (request['samples'] as int); i++) {
          for (final lane in i.isEven ? ['raw', 'orm'] : ['orm', 'raw']) {
            final clock = Stopwatch()..start();
            final rows = await test.run(lane);
            samples[lane]!.add(clock.elapsedMicroseconds);
            if (rows.length != (test.name == 'aggregate' ? 10 : 100)) {
              throw StateError('Incomplete sample.');
            }
          }
        }
        _reply({
          for (final e in samples.entries)
            e.key: _stats(e.value, e.value.fold(0, (sum, n) => sum + n)),
        });
      } else if (action == 'concurrent') {
        final result = <String, Object?>{};
        for (final lane in ['raw', 'orm']) {
          final samples = <int>[];
          var next = 0;
          final wall = Stopwatch()..start();
          await Future.wait([
            for (var i = 0; i < (request['clients'] as int); i++)
              () async {
                while (next < (request['samples'] as int)) {
                  next++;
                  final clock = Stopwatch()..start();
                  final rows = await test.run(lane);
                  samples.add(clock.elapsedMicroseconds);
                  if (rows.length != (test.name == 'aggregate' ? 10 : 100)) {
                    throw StateError('Incomplete concurrent sample.');
                  }
                }
              }(),
          ]);
          result[lane] = _stats(samples, wall.elapsedMicroseconds);
        }
        _reply(result);
      } else if (action == 'contention') {
        final result = <String, Object?>{};
        for (final lane in ['raw', 'orm']) {
          final capture = CaptureDriver(db.driver, retainResults: false);
          final query = runtimeQuery(Database(capture), test.name);
          var next = 0;
          await Future.wait([
            for (var i = 0; i < (request['clients'] as int); i++)
              () async {
                while (next < (request['samples'] as int)) {
                  next++;
                  if (lane == 'raw') {
                    await test.raw(driver: capture);
                  } else {
                    await query.get();
                  }
                }
              }(),
          ]);
          result[lane] = {
            'acquisition': _stats(
              capture.acquireMicros,
              capture.acquireMicros.fold(0, (sum, n) => sum + n),
            )..remove('operationsPerSecond'),
            'sqlMicros': capture.sqlMicros,
            'scope': 'Separate instrumented eight-client run; acquisition includes driver lease/setup, not only native pool queue time.',
          };
        }
        _reply(result);
      } else if (action == 'probe') {
        final capture = CaptureDriver(db.driver), decode = <DecodeEvent>[];
        final rows = lane == 'raw'
            ? await test.raw(driver: capture)
            : await runtimeQuery(
                Database(capture, onDecode: decode.add),
                test.name,
              ).get();
        if (capture.commands.length != test.commands.length) {
          throw StateError('Raw and ORM statement counts differ.');
        }
        for (final (i, command) in capture.commands.indexed) {
          if (command.sql != test.commands[i].sql ||
              jsonEncode(command.parameters) !=
                  jsonEncode(test.commands[i].parameters)) {
            throw StateError('Raw and ORM SQL/parameters differ.');
          }
        }
        _reply({
          'sql': [
            for (final c in capture.commands)
              {'sql': c.sql, 'parameters': c.parameters},
          ],
          'returnedRows': capture.results.map((r) => r.rows.length).toList(),
          'driverRowsUtf8JsonBytes': capture.results
              .map((r) => utf8.encode(jsonEncode(r.rows)).length)
              .toList(),
          'outputUtf8JsonBytes': utf8
              .encode(jsonEncode(canonicalRows(rows)))
              .length,
          'acquireMicros': capture.acquireMicros,
          'sqlMicros': capture.sqlMicros,
          'ormDecodeMicros': decode
              .map((e) => e.elapsed.inMicroseconds)
              .toList(),
        });
      } else if (action == 'profile') {
        final beforeRss = ProcessInfo.currentRss,
            start = developer.Timeline.now;
        for (var i = 0; i < (request['runs'] as int); i++) {
          retained = await test.run(lane!);
        }
        final end = developer.Timeline.now;
        _reply({
          'runs': request['runs'],
          'startMicros': start,
          'endMicros': end,
          'retainedRootRows': retained!.length,
          'rssBefore': beforeRss,
          'rssAfter': ProcessInfo.currentRss,
          'processLifetimeMaxRss': ProcessInfo.maxRss,
        });
      } else {
        throw StateError('Unknown benchmark action.');
      }
    }
  } finally {
    try {
      if (created) {
        await db.execute(SqlCommand('DROP SCHEMA "$schema" CASCADE'));
      }
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  }
}
