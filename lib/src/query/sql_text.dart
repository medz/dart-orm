import 'package:meta/meta.dart';

import '../../driver.dart';
import 'nodes.dart';

/// @nodoc
@internal
final class SqlText {
  final List<Object> parts;
  final Set<String> parameters;
  const SqlText(this.parts, this.parameters);
}

/// @nodoc
@internal
final class SqlSlot {
  final String name;
  const SqlSlot(this.name);
}

/// @nodoc
@internal
SqlText scanSql(String source, SqlDialect dialect, {bool fragment = false}) {
  checkSqlText(source);
  if (source.contains('\u0000')) {
    throw const OrmException('SQL.TEXT', 'SQL contains a null character.');
  }
  final mysql = dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb;
  final parts = <Object>[], names = <String>{};
  final text = StringBuffer();
  var i = 0, ended = false;
  var content = false;
  bool identifier(int code) =>
      code >= 65 && code <= 90 || code >= 97 && code <= 122 || code == 95;
  bool continuation(int code) => identifier(code) || code >= 48 && code <= 57;
  Never fail(String message) =>
      throw OrmException('SQL.TEXT', '$message at offset $i.');
  while (i < source.length) {
    final c = source[i];
    if (c.trim().isEmpty) {
      text.write(c);
      i++;
      continue;
    }
    if (source.startsWith('--', i) &&
            (!mysql ||
                i + 2 == source.length ||
                source.codeUnitAt(i + 2) <= 32) ||
        mysql && c == '#') {
      final end = source.indexOf('\n', i);
      text.write(source.substring(i, end < 0 ? source.length : end));
      i = end < 0 ? source.length : end;
      continue;
    }
    if (source.startsWith('/*', i)) {
      if (mysql &&
          (source.startsWith('/*!', i) || source.startsWith('/*M!', i))) {
        fail('Executable comments are not allowed in SQL');
      }
      final start = i;
      i += 2;
      var depth = 1;
      while (i < source.length && depth > 0) {
        if (dialect == SqlDialect.postgres && source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      if (depth != 0) fail('Unterminated block comment');
      text.write(source.substring(start, i));
      continue;
    }
    if (ended) fail('Only one SQL statement is allowed');
    if (c != ';') content = true;
    if (c == ';') {
      ended = true;
      if (fragment) text.write(c);
      i++;
      continue;
    }
    if (c == "'" ||
        c == '"' ||
        (dialect == SqlDialect.sqlite || mysql) && c == '`' ||
        dialect == SqlDialect.sqlite && c == '[') {
      final start = i, close = c == '[' ? ']' : c;
      final escapes =
          c == "'" &&
          dialect == SqlDialect.postgres &&
          i > 0 &&
          source[i - 1].toUpperCase() == 'E' &&
          (i < 2 || !continuation(source.codeUnitAt(i - 2)));
      i++;
      var closed = false;
      while (i < source.length) {
        if (source[i] == '\\' && mysql && (c == "'" || c == '"')) {
          fail('Bind values instead of mode-dependent MySQL backslash strings');
        } else if (source[i] == '\\' &&
            c == "'" &&
            dialect == SqlDialect.postgres) {
          if (!escapes) {
            fail("Use E-strings or dollar quotes for PostgreSQL backslashes");
          }
          i += 2;
        } else if (source[i] == close) {
          i++;
          if (close != ']' && i < source.length && source[i] == close) {
            i++;
          } else {
            closed = true;
            break;
          }
        } else {
          i++;
        }
      }
      if (!closed) fail('Unterminated quote');
      text.write(source.substring(start, i));
      continue;
    }
    if (c == r'$') {
      final tag = dialect == SqlDialect.postgres
          ? RegExp(r'^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$')
                .firstMatch(source.substring(i))
                ?.group(0)
          : null;
      if (tag == null) fail('Use :name parameters');
      final end = source.indexOf(tag, i + tag.length);
      if (end < 0) fail('Unterminated dollar quote');
      text.write(source.substring(i, end + tag.length));
      i = end + tag.length;
      continue;
    }
    if (c == ':' &&
        (i == 0 || source[i - 1] != ':') &&
        i + 1 < source.length &&
        identifier(source.codeUnitAt(i + 1))) {
      var end = i + 2;
      while (end < source.length && continuation(source.codeUnitAt(end))) {
        end++;
      }
      final name = source.substring(i + 1, end);
      parts.add(text.toString());
      text.clear();
      parts.add(SqlSlot(name));
      names.add(name);
      i = end;
      continue;
    }
    if (c == '?' && (dialect == SqlDialect.sqlite || mysql) ||
        c == '@' && dialect == SqlDialect.sqlite) {
      fail('Use :name parameters');
    }
    if (c == '\u0001' || c == '\u0002') fail('Reserved control character');
    if (identifier(source.codeUnitAt(i))) {
      var end = i + 1;
      while (end < source.length &&
          (continuation(source.codeUnitAt(end)) ||
              dialect == SqlDialect.postgres && source[end] == r'$')) {
        end++;
      }
      content = true;
      text.write(source.substring(i, end));
      i = end;
      continue;
    }
    text.write(c);
    i++;
  }
  if (!fragment && !content) fail('SQL is empty');
  parts.add(text.toString());
  return SqlText(List.unmodifiable(parts), Set.unmodifiable(names));
}
