part of '../../migrate.dart';

typedef _SqliteToken = ({String text, int start, int end});
typedef _SqliteCheck = ({String signature, int start, int end});

bool _sqliteWord(int c) =>
    c >= 128 ||
    c >= 48 && c <= 57 ||
    c >= 65 && c <= 90 ||
    c >= 97 && c <= 122 ||
    c == 95 ||
    c == 36;
String _sqliteName(String name) => String.fromCharCodes(
  name.codeUnits.map((c) => c >= 65 && c <= 90 ? c + 32 : c),
);

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
    } else if (_sqliteWord(sql.codeUnitAt(i))) {
      i++;
      while (i < sql.length && _sqliteWord(sql.codeUnitAt(i))) {
        i++;
      }
      text = String.fromCharCodes(
        sql
            .substring(start, i)
            .codeUnits
            .map((c) => c >= 97 && c <= 122 ? c - 32 : c),
      );
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

typedef _SqliteCollation = ({
  String column,
  String collation,
  int start,
  int end,
});

// Only column-level clauses at the CREATE TABLE body's outer depth. COLLATE
// inside CHECK/default expressions and table/index constraints is not erased.
List<_SqliteCollation> _sqliteColumnCollations(String sql) {
  final tokens = _sqliteTokens(sql), result = <_SqliteCollation>[];
  var depth = 0;
  String? column;
  var beginning = false;
  String identifier(String token) =>
      token.startsWith('i:') || token.startsWith('s:')
      ? token.substring(2)
      : token;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.text == '(') {
      depth++;
      if (depth == 1) beginning = true;
    } else if (token.text == ')') {
      depth--;
    } else if (depth == 1 && token.text == ',') {
      beginning = true;
      column = null;
    } else if (depth == 1 && beginning) {
      column =
          {
            'CONSTRAINT',
            'PRIMARY',
            'UNIQUE',
            'CHECK',
            'FOREIGN',
          }.contains(token.text)
          ? null
          : identifier(token.text);
      beginning = false;
    } else if (depth == 1 &&
        column != null &&
        token.text == 'COLLATE' &&
        i + 1 < tokens.length) {
      final next = tokens[++i];
      result.add((
        column: column,
        collation: identifier(next.text),
        start: token.start,
        end: next.end,
      ));
    }
  }
  return result;
}

String _withoutDecimalCollations(String sql, List<ColumnInfo> columns) {
  final names = {
    for (final c in columns.where((c) => c.storageType == 'TEXT'))
      _sqliteName(c.name),
  };
  final result = StringBuffer();
  var start = 0;
  for (final c in _sqliteColumnCollations(sql)) {
    if (!names.contains(_sqliteName(c.column)) ||
        c.collation.toLowerCase() != 'orm_decimal_v1') {
      continue;
    }
    result.write(sql.substring(start, c.start));
    start = c.end;
  }
  return (result..write(sql.substring(start))).toString();
}
