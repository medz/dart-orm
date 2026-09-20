import 'package:meta/meta.dart' show internal;

import '../../driver.dart';

/// @nodoc
@internal
void checkMysqlTransactionSql(String sql) {
  Never reject() => throw const OrmException(
    'TRANSACTION.STATEMENT',
    'MySQL/MariaDB transactions allow one SELECT, INSERT, UPDATE, DELETE, '
        'REPLACE, WITH, SHOW, DESCRIBE or EXPLAIN statement. Use transaction() '
        'and savepoint() for transaction control; execute DDL outside them.',
  );

  bool letter(int char) =>
      char >= 65 && char <= 90 || char >= 97 && char <= 122;
  var index = 0;
  var hasStatement = false;
  var terminated = false;
  while (index < sql.length) {
    final char = sql.codeUnitAt(index);
    if (char <= 32) {
      index++;
      continue;
    }
    final next = index + 1 < sql.length ? sql.codeUnitAt(index + 1) : -1;
    if (char == 35 ||
        char == 45 &&
            next == 45 &&
            (index + 2 == sql.length || sql.codeUnitAt(index + 2) <= 32)) {
      while (index < sql.length &&
          sql.codeUnitAt(index) != 10 &&
          sql.codeUnitAt(index) != 13) {
        index++;
      }
      continue;
    }
    if (char == 47 && next == 42) {
      final start = index + 2;
      if (start < sql.length &&
          (sql.codeUnitAt(start) == 33 ||
              (sql.codeUnitAt(start) == 77 || sql.codeUnitAt(start) == 109) &&
                  start + 1 < sql.length &&
                  sql.codeUnitAt(start + 1) == 33)) {
        reject(); // MySQL /*! ... */ and MariaDB /*M! ... */ execute SQL.
      }
      final end = sql.indexOf('*/', start);
      if (end < 0) reject();
      final nested = sql.indexOf('/*', start);
      if (nested >= 0 && nested < end) reject();
      index = end + 2;
      continue;
    }
    if (terminated) reject();
    if (!hasStatement) {
      final start = index;
      while (index < sql.length && letter(sql.codeUnitAt(index))) {
        index++;
      }
      final keyword = sql.substring(start, index).toUpperCase();
      if (!const {
        'SELECT',
        'INSERT',
        'UPDATE',
        'DELETE',
        'REPLACE',
        'WITH',
        'SHOW',
        'DESCRIBE',
        'DESC',
        'EXPLAIN',
      }.contains(keyword)) {
        reject();
      }
      hasStatement = true;
      continue;
    }
    if (char == 59) {
      terminated = true;
      index++;
      continue;
    }
    if (char == 39 || char == 34 || char == 96) {
      index++;
      var closed = false;
      while (index < sql.length) {
        final quoted = sql.codeUnitAt(index++);
        // Reject ambiguous escapes instead of relying on a mutable sql_mode.
        // Bound values and doubled quotes work in either backslash mode.
        if (quoted == 92 && index < sql.length) {
          final escaped = sql.codeUnitAt(index);
          if (escaped == char || escaped == 92) reject();
        }
        if (quoted != char) continue;
        if (index < sql.length && sql.codeUnitAt(index) == char) {
          index++;
        } else {
          closed = true;
          break;
        }
      }
      if (!closed) reject();
      continue;
    }
    index++;
  }
  if (!hasStatement) reject();
}
