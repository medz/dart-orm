import 'package:sqlite3/common.dart' as sqlite;

import '../../driver.dart';
import 'functions.dart';

int configureSqlite(
  sqlite.CommonDatabase db, {
  required String? journal,
  required Duration busyTimeout,
  bool fullSync = false,
}) {
  registerSqliteFunctions(db);
  db.execute('PRAGMA foreign_keys = ON');
  if (db.select('PRAGMA foreign_keys').single.values.single != 1) {
    throw const OrmException(
      'DRIVER.FOREIGN_KEYS',
      'SQLite foreign keys could not be enabled.',
    );
  }
  db.execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}');
  final actual = db
      .select(
        journal == null
            ? 'PRAGMA journal_mode'
            : 'PRAGMA journal_mode = $journal',
      )
      .single
      .values
      .single;
  if (journal != null && actual != journal) {
    throw OrmException(
      'DRIVER.JOURNAL',
      'Requested $journal, received $actual.',
    );
  }
  if (fullSync) db.execute('PRAGMA synchronous = FULL');
  for (final row in db.select('PRAGMA compile_options')) {
    final option = row.values.single as String;
    if (option.startsWith('MAX_VARIABLE_NUMBER=')) {
      return int.parse(option.split('=').last);
    }
  }
  return 999;
}

/// Synchronous statement ownership shared by the native isolate and web worker.
final class SqliteExecutor {
  final sqlite.CommonDatabase database;
  final _cursors = <int, _Cursor>{};
  int _serial = 0;
  bool _closed = false;
  SqliteExecutor(this.database);

  SqlResult execute(SqlCommand command) {
    final statement = database.prepare(command.sql, checkNoTail: true);
    try {
      final rows = statement.select(sqliteParameters(command.parameters));
      return SqlResult(
        [for (final row in rows) row.values.toList()],
        columns: rows.columnNames,
        affectedRows: statement.isReadOnly ? 0 : database.updatedRows,
      );
    } finally {
      statement.close();
    }
  }

  int openCursor(SqlCommand command) {
    final statement = database.prepare(command.sql, checkNoTail: true);
    try {
      if (!statement.isReadOnly) {
        throw const OrmException(
          'CURSOR.READ_ONLY',
          'Streaming requires a read-only query.',
        );
      }
      final id = ++_serial;
      _cursors[id] = _Cursor(
        statement,
        statement.selectCursor(sqliteParameters(command.parameters)),
      );
      return id;
    } catch (_) {
      statement.close();
      rethrow;
    }
  }

  SqlResult fetch(int id, int count) {
    if (count < 1) throw ArgumentError.value(count, 'count');
    final cursor = _cursors[id];
    if (cursor == null) {
      throw const OrmException('CURSOR.CLOSED', 'Cursor has ended.');
    }
    return cursor.fetch(count);
  }

  void release(int id) => _cursors.remove(id)?.close();
  void close() {
    if (_closed) return;
    _closed = true;
    for (final cursor in _cursors.values) {
      cursor.close();
    }
    _cursors.clear();
    database.close();
  }
}

final class _Cursor(
  final sqlite.CommonPreparedStatement statement,
  final sqlite.IteratingCursor cursor,
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
    if (closed) return;
    closed = true;
    statement.close();
  }
}
