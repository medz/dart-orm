import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'legacy/seed.dart';
import 'migrations/migrations.g.dart';
import 'schema.orm.dart';

typedef NoteCard = ({int id, String text, bool done, List<String> comments});

/// Runs inside the installed application, using its own persistent database.
Future<Map<String, Object?>> runAcceptance({
  required void Function(List<NoteCard>) onRows,
  required void Function(String) onCheck,
  required int Function() frameCount,
}) async {
  const version = int.fromEnvironment('ORM_SCHEMA_VERSION', defaultValue: 2);
  final config = (await const MethodChannel('orm_acceptance/config')
      .invokeMapMethod<String, Object?>('read'))!;
  final phase = version == 1 ? 'legacy' : config['phase']! as String;
  final path = '${config['filesPath']}/acceptance.sqlite';
  final checks = <String>[];
  final report = <String, Object?>{
    'phase': phase,
    'schemaVersion': version,
    'release': kReleaseMode,
    'dart': Platform.version,
    'os': Platform.operatingSystemVersion,
    'androidApi': config['api'],
    'pid': config['pid'],
    'path': path,
    'checks': checks,
  };
  void check(bool condition, String name) {
    if (!condition) throw StateError(name);
    checks.add(name);
    onCheck(name);
  }

  Database<Sqlite>? database;
  StreamSubscription<List<NoteCard>>? subscription;
  try {
    check(
      await File(path).exists() == (phase != 'legacy'),
      phase == 'legacy' ? 'Fresh database' : 'Existing database retained',
    );
    final migrations = migrationHistory.checked.take(version).toList();
    final db = database = await sqlite(SqliteOptions.file(path));
    report['sqlite'] = (await db.execute(SqlCommand('SELECT sqlite_version()')))
        .rows
        .single
        .single;
    if (phase == 'legacy') {
      await seedLegacy(db, migrations.single);
      final rows = (await db.execute(
        SqlCommand('SELECT id, body, created_at FROM notes ORDER BY id'),
      )).rows;
      check(
        rows.length == 2,
        'Version 1 typed transaction persisted two notes',
      );
      report['legacyRows'] = rows;
    } else {
      check(phase == 'upgrade' || phase == 'reopen', 'Known execution phase');
      final before = await Migrator(db.sql).history();
      check(
        before.map((m) => m.id).join(',') ==
            (phase == 'upgrade'
                ? '0001_initial'
                : '0001_initial,0002_comments'),
        'Expected previous migration history',
      );
      final applied = await Migrator(db.sql).apply(migrations);
      check(
        applied.join(',') == (phase == 'upgrade' ? '0002_comments' : ''),
        phase == 'upgrade'
            ? 'Only version 2 migration applied'
            : 'No migration replay',
      );
      final schema = await verifySchema(db.sql, migrations.last.snapshot!);
      check(schema.matches, 'Live schema matches bundled snapshot');
      report['unmanaged'] = schema.unmanaged.map((o) => o.name).toList();
      final original = await db.notes.byId(1).single();
      check(
        original.text == 'Written by version 1' &&
            original.createdAt == DateTime.utc(2026, 9, 15, 1, 2, 3, 123, 456),
        'Original value and timestamp microseconds preserved',
      );
      check(
        original.done == (phase == 'reopen'),
        'New field default / persisted update',
      );
      final query = db.notes
          .orderBy((n) => [n.id.asc()])
          .select(
            (n) =>
                (
                  n.id,
                  n.text,
                  n.done,
                  n.comments
                      .orderBy((c) => [c.id.asc()])
                      .select((c) => c.text)
                      .many(),
                ).map(
                  (id, text, done, comments) =>
                      (id: id, text: text, done: done, comments: comments),
                ),
          );
      final snapshots = <List<NoteCard>>[];
      Object? watchError;
      subscription = query.watch().listen((rows) {
        snapshots.add(rows);
        onRows(rows);
      }, onError: (Object error) => watchError = error);
      Future<void> waitFor(bool Function(List<NoteCard>) predicate) async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (snapshots.isEmpty || !predicate(snapshots.last)) {
          if (watchError != null) throw watchError!;
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Watch timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      await waitFor((rows) => rows.length == (phase == 'upgrade' ? 2 : 3));
      check(true, 'Initial watch snapshot delivered to Flutter');
      if (phase == 'upgrade') {
        await db.transaction((tx) async {
          final note = await tx.notes.create(
            text: 'Written by version 2',
            createdAt: DateTime.utc(2026, 9, 15, 2),
          );
          await tx.comments.create(
            noteId: note.id,
            text: 'Related in one transaction',
          );
        });
        await waitFor(
          (rows) => rows.length == 3 && rows.last.comments.length == 1,
        );
        check(true, 'Committed relation write refreshed watch');
        final count = snapshots.length;
        final rollback = StateError('Expected rollback');
        try {
          await db.transaction((tx) async {
            await tx.notes.create(
              text: 'Must roll back',
              createdAt: DateTime.utc(2026),
            );
            throw rollback;
          });
        } catch (error) {
          if (!identical(error, rollback)) rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        check(
          snapshots.length == count && (await query.get()).length == 3,
          'Rollback neither persisted nor notified',
        );
        await db.notes.byId(1).patch(done: .set(true));
        await waitFor((rows) => rows.first.done);
        check(true, 'Typed patch refreshed watch');
        var ticks = 0;
        final timer = Timer.periodic(
          const Duration(milliseconds: 16),
          (_) => ticks++,
        );
        final framesBefore = frameCount();
        final watch = Stopwatch()..start();
        try {
          final result = await db.execute(
            SqlCommand(
              'WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<2000000) SELECT sum(x) FROM n',
            ),
            options: const ExecutionOptions(timeout: Duration(seconds: 30)),
          );
          check(
            result.rows.single.single == 2000001000000,
            'Background SQLite computation result',
          );
        } finally {
          timer.cancel();
          watch.stop();
        }
        report['background'] = {
          'elapsedUs': watch.elapsedMicroseconds,
          'timerTicks': ticks,
          'flutterFrames': frameCount() - framesBefore,
        };
        check(
          ticks >= 3 && frameCount() - framesBefore >= 3,
          'Dart timer and Flutter frames advanced during SQLite work',
        );
        final token = CancellationToken();
        final cancel = Timer(const Duration(milliseconds: 50), token.cancel);
        String? cancellation;
        try {
          await db.execute(
            SqlCommand(
              'WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n',
            ),
            options: ExecutionOptions(
              cancellation: token,
              timeout: const Duration(seconds: 30),
            ),
          );
        } on OrmException catch (error) {
          cancellation = error.code;
        } finally {
          cancel.cancel();
        }
        check(
          cancellation == 'OPERATION.CANCELLED',
          'Native SQLite cancellation',
        );
        check(
          (await query.get()).length == 3,
          'Worker usable after cancellation',
        );
      } else {
        check(
          snapshots.last.last.comments.single == 'Related in one transaction',
          'Relation data survived process restart',
        );
      }
      report['watchSnapshots'] = snapshots.length;
      report['rows'] = [
        for (final n in await query.get())
          {'id': n.id, 'text': n.text, 'done': n.done, 'comments': n.comments},
      ];
      await subscription.cancel();
      subscription = null;
    }
    final versionState = await Migrator(db.sql).requireVersion(migrations);
    check(
      versionState.id == migrations.last.id,
      'Application schema compatibility',
    );
    report['history'] = [
      for (final m in await Migrator(db.sql).history())
        {'id': m.id, 'checksum': m.checksum},
    ];
    await db.close();
    database = null;
    final reader = await sqlite(SqliteOptions.readOnly(path));
    try {
      check(
        (await reader.execute(SqlCommand('SELECT count(*) FROM notes')))
                .rows
                .single
                .single ==
            (phase == 'legacy' ? 2 : 3),
        'Closed database reopened read-only',
      );
    } finally {
      await reader.close();
    }
    report['status'] = 'passed';
  } catch (error, stack) {
    report['status'] = 'failed';
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    await subscription?.cancel();
    await database?.close();
  }
  final json = jsonEncode(report);
  await File('${config['filesPath']}/$phase.json')
      .writeAsString(json, flush: true);
  final encoded = base64Encode(utf8.encode(json));
  // The Android Flutter log sink truncated 1,800-character chunks in release.
  const size = 700;
  final count = (encoded.length / size).ceil();
  for (var i = 0; i < count; i++) {
    final end = (i + 1) * size;
    // Machine-readable transport also works in release builds without run-as.
    // ignore: avoid_print
    print(
      'ORM_ACCEPTANCE $phase ${i + 1}/$count ${encoded.substring(i * size, end > encoded.length ? encoded.length : end)}',
    );
  }
  return report;
}
