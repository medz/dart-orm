part of '../../migrate.dart';

typedef _SqliteToken = ({String text, int start, int end});
typedef _SqliteCheck = ({String signature, int start, int end});

// Recognize only the range expressions emitted by this ORM, without mistaking
// quoted defaults/comments for constraints. This is not a general SQL parser.
List<_SqliteToken> _sqliteTokens(String sql) {
  final result = <_SqliteToken>[];
  var i = 0;
  while (i < sql.length) {
    if (sql[i].trim().isEmpty) {
      i++;
      continue;
    }
    if (sql.startsWith('--', i)) {
      final end = sql.indexOf('\n', i + 2);
      i = end < 0 ? sql.length : end + 1;
      continue;
    }
    if (sql.startsWith('/*', i)) {
      final end = sql.indexOf('*/', i + 2);
      i = end < 0 ? sql.length : end + 2;
      continue;
    }
    final start = i, first = sql[i];
    String text;
    if ({"'", '"', '`', '['}.contains(first)) {
      final close = first == '[' ? ']' : first;
      final value = StringBuffer();
      i++;
      while (i < sql.length) {
        if (sql[i] == close) {
          i++;
          if (first != '[' && i < sql.length && sql[i] == close) {
            value.write(close);
            i++;
            continue;
          }
          break;
        }
        value.write(sql[i++]);
      }
      text = '${first == "'" ? 's' : 'i'}:${value.toString()}';
    } else if (RegExp(r'[a-zA-Z0-9_]').hasMatch(first)) {
      i++;
      while (i < sql.length && RegExp(r'[a-zA-Z0-9_]').hasMatch(sql[i])) {
        i++;
      }
      text = sql.substring(start, i).toUpperCase();
    } else {
      text = sql[i++];
    }
    result.add((text: text, start: start, end: i));
  }
  return result;
}

List<_SqliteCheck> _sqliteChecks(String sql) {
  final tokens = _sqliteTokens(sql), checks = <_SqliteCheck>[];
  for (var i = 0; i + 1 < tokens.length; i++) {
    if (tokens[i].text != 'CHECK' || tokens[i + 1].text != '(') continue;
    var depth = 1, end = i + 2;
    for (; end < tokens.length; end++) {
      if (tokens[end].text == '(') depth++;
      if (tokens[end].text == ')' && --depth == 0) break;
    }
    if (depth != 0) break;
    checks.add((
      signature: jsonEncode(
        tokens.sublist(i + 2, end).map((t) => t.text).toList(),
      ),
      start: tokens[i].start,
      end: tokens[end].end,
    ));
    i = end;
  }
  return checks;
}

String _integerSignature(String name, int bits) => jsonEncode(
  _sqliteTokens(_integerCheck(name, bits)).map((t) => t.text).toList(),
);

int _sqliteIntegerBits(String name, List<_SqliteCheck> checks) {
  for (final bits in [16, 32]) {
    final signature = _integerSignature(name, bits);
    if (checks.any((c) => c.signature == signature)) return bits;
  }
  return 64;
}

String _withoutIntegerChecks(String sql, List<ColumnInfo> columns) {
  final known = {
    for (final c in columns.where((c) => c.storageType == 'INTEGER'))
      for (final bits in [16, 32]) _integerSignature(c.name, bits),
  };
  final result = StringBuffer();
  var start = 0;
  for (final check in _sqliteChecks(sql)) {
    if (!known.contains(check.signature)) continue;
    result.write(sql.substring(start, check.start));
    start = check.end;
  }
  return (result..write(sql.substring(start))).toString();
}
