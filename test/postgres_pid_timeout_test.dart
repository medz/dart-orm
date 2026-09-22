import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:orm/drivers/postgres.dart';
import 'package:orm/runtime.dart';
import 'package:test/test.dart';

Matcher _code(String code) =>
    isA<OrmException>().having((error) => error.code, 'code', code);

void main() {
  final address = Platform.environment['ORM_TEST_POSTGRES'];
  group(
    'PostgreSQL PID discovery deadline',
    () {
      late SqlDatabase<Postgres> admin, db;
      late _PidProxy proxy;
      final table = 'orm_pid_deadline_$pid';
      setUp(() async {
        final url = Uri.parse(address!);
        admin = SqlDatabase(
          PostgresDriver(PostgresOptions(url: url, tls: .disable)),
        );
        await admin.execute(
          SqlCommand('CREATE TABLE "$table" (id BIGINT PRIMARY KEY)'),
        );
        proxy = await _PidProxy.open(url);
      });
      tearDown(() async {
        // Closing the test transport also unblocks the old buggy implementation,
        // so a failing regression cannot hang pool shutdown.
        await proxy.close();
        await db.close();
        try {
          await admin.execute(SqlCommand('DROP TABLE "$table"'));
        } finally {
          await admin.close();
        }
      });

      for (final mode in [
        'explicit timeout',
        'default timeout',
        'cancellation',
      ]) {
        test('$mode stops a stalled first PID query before any write', () async {
          db = SqlDatabase(
            PostgresDriver(
              PostgresOptions(
                url: proxy.url,
                tls: .disable,
                maxConnections: 1,
                queryTimeout: mode == 'default timeout'
                    ? const Duration(milliseconds: 100)
                    : const Duration(seconds: 2),
              ),
            ),
          );
          final token = CancellationToken();
          final pending = db.execute(
            SqlCommand('INSERT INTO "$table" VALUES (1)'),
            options: ExecutionOptions(
              timeout: mode == 'explicit timeout'
                  ? const Duration(milliseconds: 100)
                  : null,
              cancellation: mode == 'cancellation' ? token : null,
            ),
          );
          final expected = expectLater(
            pending.timeout(const Duration(seconds: 3)),
            throwsA(
              _code(
                mode == 'cancellation'
                    ? 'OPERATION.CANCELLED'
                    : 'OPERATION.TIMEOUT',
              ),
            ),
          );
          await proxy.blocked.future.timeout(const Duration(seconds: 2));
          if (mode == 'cancellation') token.cancel();
          await expected;
          expect(
            proxy.userQueries.where((sql) => sql.contains('INSERT')),
            isEmpty,
          );
          expect(
            (await admin.execute(SqlCommand('SELECT count(*) FROM "$table"')))
                .rows
                .single
                .single,
            0,
          );
          // The stalled physical connection must be discarded. Its replacement
          // discovers one PID, then reuses that cached value for later work.
          await db.execute(
            SqlCommand('INSERT INTO "$table" VALUES (2)'),
            options: const ExecutionOptions(timeout: Duration(seconds: 2)),
          );
          expect(
            (await db.execute(SqlCommand('SELECT id FROM "$table"')))
                .rows
                .single
                .single,
            2,
          );
          expect(proxy.pidQueries, 2);
        });
      }

      test('PID discovery and application SQL share one timeout budget', () async {
        db = SqlDatabase(
          PostgresDriver(
            PostgresOptions(url: proxy.url, tls: .disable, maxConnections: 1),
          ),
        );
        await db.session((session) async {
          // Leave room for transport scheduling under concurrent compilation.
          // 1s discovering the PID + 1.5s of SQL exceeds the shared 2s budget,
          // but would succeed if SQL incorrectly received a fresh 2s budget.
          final pending = session.execute(
            SqlCommand('SELECT pg_sleep(1.5)'),
            options: const ExecutionOptions(timeout: Duration(seconds: 2)),
          );
          final expected = expectLater(
            pending.timeout(const Duration(seconds: 5)),
            throwsA(_code('OPERATION.TIMEOUT')),
          );
          await proxy.blocked.future.timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(seconds: 1));
          proxy.release();
          // Catch inside the lease: package:postgres discards connections if
          // any error escapes the withConnection callback.
          await expected;
        });
        expect(proxy.userQueries, contains('SELECT pg_sleep(1.5)'));
        expect(
          (await db.execute(SqlCommand('SELECT 42'))).rows.single.single,
          42,
        );
        expect(
          proxy.pidQueries,
          1,
          reason: 'a confirmed cancellation keeps the cached live connection reusable',
        );
      });
    },
    skip: address == null
        ? 'Set ORM_TEST_POSTGRES for real transport regressions.'
        : false,
  );
}

/// Forward the real PostgreSQL wire protocol, pausing the first PID Parse frame
/// and everything after it. No server reply can accidentally resolve that probe.
final class _PidProxy {
  final Uri target;
  final ServerSocket listener;
  final List<_ProxyConnection> connections = [];
  final blocked = Completer<void>();
  final userQueries = <String>[];
  int pidQueries = 0;
  bool holdNextPid = true;
  _ProxyConnection? held;
  _PidProxy(this.target, this.listener);
  Uri get url => target.replace(host: '127.0.0.1', port: listener.port);
  static Future<_PidProxy> open(Uri target) async {
    final result = _PidProxy(
      target,
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    result.listener.listen((client) async {
      final server = await Socket.connect(
        target.host,
        target.hasPort ? target.port : 5432,
      );
      final connection = _ProxyConnection(result, client, server);
      result.connections.add(connection);
      connection.start();
    });
    return result;
  }

  void release() => held?.release();
  Future<void> close() async {
    await listener.close();
    for (final connection in connections) {
      connection.close();
    }
  }
}

final class _ProxyConnection {
  final _PidProxy proxy;
  final Socket client, server;
  final List<int> pending = [], held = [];
  bool startup = true, paused = false;
  _ProxyConnection(this.proxy, this.client, this.server);
  void start() {
    server.listen(client.add, onError: (Object _) => close(), onDone: close);
    client.listen(_receive, onError: (Object _) => close(), onDone: close);
  }

  int _length(int offset) => ByteData.sublistView(
    Uint8List.fromList(pending),
    offset,
    offset + 4,
  ).getUint32(0);
  void _receive(List<int> bytes) {
    pending.addAll(bytes);
    while (pending.length >= (startup ? 4 : 5)) {
      final length = startup ? _length(0) : _length(1) + 1;
      if (pending.length < length) return;
      final frame = pending.sublist(0, length);
      pending.removeRange(0, length);
      if (!startup && frame[0] == 80) {
        final nameEnd = frame.indexOf(0, 5);
        final sqlEnd = frame.indexOf(0, nameEnd + 1);
        final sql = utf8.decode(frame.sublist(nameEnd + 1, sqlEnd));
        if (sql == 'SELECT pg_backend_pid()') {
          proxy.pidQueries++;
          if (proxy.holdNextPid) {
            proxy.holdNextPid = false;
            paused = true;
            proxy.held = this;
            proxy.blocked.complete();
          }
        } else {
          proxy.userQueries.add(sql);
        }
      }
      startup = false;
      if (paused) {
        held.addAll(frame);
      } else {
        server.add(frame);
      }
    }
  }

  void release() {
    paused = false;
    server.add(List<int>.of(held));
    held.clear();
  }

  void close() {
    client.destroy();
    server.destroy();
  }
}
