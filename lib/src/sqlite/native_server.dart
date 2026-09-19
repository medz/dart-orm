part of 'native.dart';

void _sqliteMain((SendPort, SqliteOptions) init) async {
  final (response, options) = init;
  native.Database? db;
  final commands = ReceivePort();
  SqliteExecutor? executor;
  var published = false;
  try {
    db = native.sqlite3.open(
      options.path,
      mode: options.readOnly
          ? native.OpenMode.readOnly
          : native.OpenMode.readWriteCreate,
    );
    executor = SqliteExecutor(db);
    final maxParameters = configureSqlite(
      db,
      journal: options.journal?.name,
      busyTimeout: options.busyTimeout,
    );
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
        executor!.close();
        executor = null;
        db = null;
        response.send([id, const SqlResult([]), false]);
        break;
      }
      try {
        SqlResult result;
        switch (command) {
          case SqlCommand():
            result = executor!.execute(command);
          case _OpenCursor():
            result = SqlResult([
              [executor!.openCursor(command.command)],
            ]);
          case _FetchCursor():
            result = executor!.fetch(command.cursor, command.count);
          case _CloseCursor():
            executor!.release(command.cursor);
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
    if (executor != null) {
      executor.close();
    } else {
      db?.close();
    }
    commands.close();
  }
}
