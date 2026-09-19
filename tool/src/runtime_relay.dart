import 'dart:async';
import 'dart:io';

/// Calibrate this relay's transport delay with a byte echo, independently of
/// PostgreSQL's multi-round-trip prepare/execute/dispose protocol.
Future<List<int>> relayRoundTrips(Duration delay, int samples) async {
  final echo = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = <Socket>[];
  echo.listen((socket) {
    accepted.add(socket);
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.listen(socket.add, onError: (Object _) => socket.destroy());
  });
  final relay = await RuntimeRelay.open('127.0.0.1', echo.port, delay);
  final socket = await Socket.connect('127.0.0.1', relay.server.port);
  socket.setOption(SocketOption.tcpNoDelay, true);
  final replies = StreamIterator(socket);
  try {
    final result = <int>[];
    for (var i = -1; i < samples; i++) {
      final byte = (i + 1) % 256, clock = Stopwatch()..start();
      socket.add([byte]);
      if (!await replies.moveNext().timeout(const Duration(seconds: 10)) ||
          replies.current.length != 1 ||
          replies.current.single != byte) {
        throw StateError('Relay changed or lost data.');
      }
      if (i >= 0) result.add(clock.elapsedMicroseconds);
    }
    if (relay.sentBytes != samples + 1 || relay.receivedBytes != samples + 1) {
      throw StateError('Relay byte accounting differs.');
    }
    return result;
  } finally {
    await replies.cancel();
    socket.destroy();
    await relay.close();
    for (final client in accepted) {
      client.destroy();
    }
    await echo.close();
  }
}

/// Loopback TCP relay. Every received chunk is scheduled once after a fixed
/// one-way delay; chunks are not serially delayed or bandwidth-throttled.
/// Runs outside the benchmark process, including its timers and byte counters.
final class RuntimeRelay {
  final ServerSocket server;
  final String host;
  final int port;
  Duration oneWayDelay;
  final _sockets = <Socket>{};
  var sentBytes = 0, receivedBytes = 0;
  RuntimeRelay._(this.server, this.host, this.port, this.oneWayDelay);

  static Future<RuntimeRelay> open(
    String host,
    int port,
    Duration delay,
  ) async {
    final result = RuntimeRelay._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      host,
      port,
      delay,
    );
    result.server.listen(result._connect);
    return result;
  }

  Future<void> _connect(Socket client) async {
    _sockets.add(client);
    try {
      final upstream = await Socket.connect(host, port);
      _sockets.add(upstream);
      client.setOption(SocketOption.tcpNoDelay, true);
      upstream.setOption(SocketOption.tcpNoDelay, true);
      _pipe(client, upstream, true);
      _pipe(upstream, client, false);
    } catch (_) {
      client.destroy();
      _sockets.remove(client);
    }
  }

  void _pipe(Socket source, Socket target, bool outgoing) {
    final pending = <Timer>{};
    var queuedBytes = 0, ended = false, broken = false;
    late StreamSubscription<List<int>> subscription;
    void fail() {
      broken = true;
      for (final timer in pending) {
        timer.cancel();
      }
      pending.clear();
      source.destroy();
      target.destroy();
      _sockets.remove(source);
      _sockets.remove(target);
    }

    void finish() {
      if (ended && pending.isEmpty && !broken) {
        unawaited(
          target.close().catchError((Object _) {
            fail();
            return target;
          }),
        );
      }
    }

    subscription = source.listen(
      (data) {
        if (outgoing) {
          sentBytes += data.length;
        } else {
          receivedBytes += data.length;
        }
        if (oneWayDelay == Duration.zero) {
          target.add(data);
          return;
        }
        queuedBytes += data.length;
        if (queuedBytes >= 1024 * 1024 && !subscription.isPaused) {
          subscription.pause();
        }
        late Timer timer;
        timer = Timer(oneWayDelay, () {
          pending.remove(timer);
          if (broken) return;
          target.add(data);
          queuedBytes -= data.length;
          if (subscription.isPaused && queuedBytes < 512 * 1024) {
            subscription.resume();
          }
          finish();
        });
        pending.add(timer);
      },
      onError: (Object _) => fail(),
      onDone: () {
        ended = true;
        finish();
      },
    );
    target.done.catchError((Object _) {
      fail();
      return target;
    });
  }

  Map<String, int> get bytes => {'sent': sentBytes, 'received': receivedBytes};
  Future<void> close() async {
    await server.close();
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    _sockets.clear();
  }
}
