part of '../../sqlite.dart';

final class _NativeCursor(
  final native.PreparedStatement statement,
  final native.IteratingCursor cursor,
) {
  bool closed = false;
  List<String> columns = const [];
  SqlResult fetch(int count) {
    if (closed) return SqlResult(const [], columns: columns);
    final rows = <List<Object?>>[];
    while (rows.length < count) {
      if (!cursor.moveNext()) {
        columns = cursor.columnNames;
        close();
        break;
      }
      rows.add(cursor.current.values.toList());
    }
    columns = cursor.columnNames;
    return SqlResult(rows, columns: columns);
  }

  void close() {
    if (!closed) {
      closed = true;
      statement.close();
    }
  }
}

void _sqliteMain((SendPort, SqliteOptions) init) async {
  final (response, options) = init;
  native.Database? db;
  final commands = ReceivePort();
  final cursors = <int, _NativeCursor>{};
  var nextCursor = 0, published = false;
  try {
    db = native.sqlite3.open(
      options.path,
      mode: options.readOnly
          ? native.OpenMode.readOnly
          : native.OpenMode.readWriteCreate,
    );
    db.execute('PRAGMA foreign_keys = ON');
    if (db.select('PRAGMA foreign_keys').single.values.single != 1) {
      throw const OrmException(
        'DRIVER.FOREIGN_KEYS',
        'SQLite foreign key enforcement could not be enabled.',
      );
    }
    db.execute('PRAGMA busy_timeout = ${options.busyTimeout.inMilliseconds}');
    final journal = db
        .select(
          options.journal == null
              ? 'PRAGMA journal_mode'
              : 'PRAGMA journal_mode = ${options.journal!.name}',
        )
        .single
        .values
        .single;
    if (options.journal != null && journal != options.journal!.name) {
      throw OrmException(
        'DRIVER.JOURNAL',
        'Requested ${options.journal!.name}, received $journal.',
      );
    }
    var maxParameters = 999;
    for (final row in db.select('PRAGMA compile_options')) {
      final option = row.values.single as String;
      if (option.startsWith('MAX_VARIABLE_NUMBER=')) {
        maxParameters = int.parse(option.split('=').last);
      }
    }
    response.send([
      0,
      commands.sendPort,
      maxParameters,
      native.sqlite3.version.versionNumber,
      db.handle.address,
    ]);
    published = true;
    await for (final message in commands) {
      final (id, command) = message as (int, Object?);
      if (command == null) {
        for (final cursor in cursors.values) {
          cursor.close();
        }
        cursors.clear();
        db!.close();
        db = null;
        response.send([id, const SqlResult([]), false]);
        break;
      }
      try {
        SqlResult result;
        switch (command) {
          case SqlCommand():
            final statement = db!.prepare(command.sql, checkNoTail: true);
            try {
              final rows = statement.select(command.parameters);
              result = SqlResult(
                [for (final row in rows) row.values.toList()],
                columns: rows.columnNames,
                affectedRows: statement.isReadOnly ? 0 : db.updatedRows,
              );
            } finally {
              statement.close();
            }
          case _OpenCursor():
            final statement = db!.prepare(
              command.command.sql,
              checkNoTail: true,
            );
            try {
              if (!statement.isReadOnly) {
                throw const OrmException(
                  'CURSOR.READ_ONLY',
                  'Streaming cursors require a read-only query.',
                );
              }
              final cursor = _NativeCursor(
                statement,
                statement.selectCursor(command.command.parameters),
              );
              final cursorId = ++nextCursor;
              cursors[cursorId] = cursor;
              result = SqlResult([
                [cursorId],
              ]);
            } catch (_) {
              statement.close();
              rethrow;
            }
          case _FetchCursor():
            result = cursors[command.cursor]!.fetch(command.count);
          case _CloseCursor():
            cursors.remove(command.cursor)?.close();
            result = const SqlResult([]);
          default:
            throw const OrmException(
              'DRIVER.WORKER',
              'Invalid SQLite worker command.',
            );
        }
        response.send([id, result, !db!.autocommit]);
      } on native.SqliteException catch (e) {
        response.send([
          id,
          SqliteFailure(e.resultCode, e.extendedResultCode, e.message),
          !db!.autocommit,
        ]);
      } catch (e) {
        response.send([
          id,
          e is OrmException ? e : OrmException('DRIVER.SQLITE', e.toString()),
          !db!.autocommit,
        ]);
      }
    }
  } catch (e) {
    final error = OrmException('DRIVER.OPEN', e.toString());
    if (published && db != null) {
      final acknowledged = ReceivePort();
      response.send([-1, error, acknowledged.sendPort]);
      await acknowledged.first;
      acknowledged.close();
    } else {
      response.send([0, error]);
    }
  } finally {
    for (final cursor in cursors.values) {
      cursor.close();
    }
    db?.close();
    commands.close();
  }
}
