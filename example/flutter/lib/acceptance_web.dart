import 'package:flutter/foundation.dart';
import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import 'migrations/migrations.g.dart';
import 'schema.orm.dart';

typedef NoteCard = ({int id, String text, bool done, List<String> comments});

Future<Map<String, Object?>> runAcceptance({
  required void Function(List<NoteCard>) onRows,
  required void Function(String) onCheck,
  required int Function() frameCount,
}) async {
  final report = <String, Object?>{
    'phase': 'web',
    'release': kReleaseMode,
    'sqlite': 'opening',
  };
  Database<Sqlite>? database;
  void check(bool condition, String name) {
    if (!condition) throw StateError(name);
    onCheck(name);
  }

  try {
    final db = database = await sqlite(
      const SqliteOptions.persistent('flutter-example'),
    );
    report['sqlite'] = (await db.execute(SqlCommand('SELECT sqlite_version()')))
        .rows
        .single
        .single;
    await Migrator(db.sql).apply(migrationHistory.checked);
    check(
      (await verifySchema(
        db.sql,
        migrationHistory.checked.last.snapshot!,
      )).matches,
      'Bundled Dart migrations match the browser database',
    );
    if (await db.note.count() == 0) {
      await db.transaction((tx) async {
        final note = await tx.note.create(
          text: 'Stored in the browser',
          createdAt: DateTime.now().toUtc(),
        );
        await tx.comment.create(
          noteId: note.id,
          text: 'Written in the same transaction',
        );
      });
    }
    final rows = await db.note
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
        )
        .get();
    onRows(rows);
    check(
      rows.isNotEmpty && rows.first.comments.isNotEmpty,
      'Typed records and relationships loaded into Flutter',
    );
    final frames = frameCount();
    await db.execute(
      SqlCommand(
        'WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<1000000) SELECT SUM(x) FROM n',
      ),
    );
    check(
      frameCount() > frames,
      'Flutter animation advanced during worker SQL',
    );
    report['status'] = 'passed';
  } catch (error) {
    report['status'] = 'failed';
    report['error'] = error.toString();
  } finally {
    await database?.close();
  }
  return report;
}
