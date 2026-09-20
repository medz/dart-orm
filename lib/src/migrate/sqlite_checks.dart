import 'dart:convert' show jsonDecode, jsonEncode;

import 'columns.dart' show ColumnInfo, temporalCollationKind;
import 'schema.dart' show decimalCheck, integerCheck, temporalCheck;

typedef SqliteToken = ({String text, int start, int end});
typedef SqliteCheck = ({
  String signature,
  String expression,
  String? name,
  int start,
  int end,
});

bool _sqliteWord(int c) =>
    c >= 128 ||
    c >= 48 && c <= 57 ||
    c >= 65 && c <= 90 ||
    c >= 97 && c <= 122 ||
    c == 95 ||
    c == 36;
String sqliteName(String name) => String.fromCharCodes(
  name.codeUnits.map((c) => c >= 65 && c <= 90 ? c + 32 : c),
);

// Tokenize constraint expressions without mistaking quoted defaults/comments for
// constraints. Storage ranges still require exact emitted signatures below.
// This is not a general SQL parser.
List<SqliteToken> sqliteTokens(String sql) {
  final result = <SqliteToken>[];
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

List<SqliteCheck> sqliteChecks(String sql) {
  final tokens = sqliteTokens(sql), checks = <SqliteCheck>[];
  for (var i = 0; i + 1 < tokens.length; i++) {
    if (tokens[i].text != 'CHECK' || tokens[i + 1].text != '(') continue;
    var depth = 1, end = i + 2;
    for (; end < tokens.length; end++) {
      if (tokens[end].text == '(') depth++;
      if (tokens[end].text == ')' && --depth == 0) break;
    }
    if (depth != 0) break;
    final named = i >= 2 && tokens[i - 2].text == 'CONSTRAINT';
    final name = named ? tokens[i - 1] : null;
    checks.add((
      signature: jsonEncode(
        tokens.sublist(i + 2, end).map((t) => t.text).toList(),
      ),
      expression: sql.substring(tokens[i + 1].end, tokens[end].start).trim(),
      name: name == null
          ? null
          : name.text.startsWith('i:') || name.text.startsWith('s:')
          ? name.text.substring(2)
          : sql.substring(name.start, name.end),
      start: named ? tokens[i - 2].start : tokens[i].start,
      end: tokens[end].end,
    ));
    i = end;
  }
  return checks;
}

String _integerSignature(String name, int bits) => jsonEncode(
  sqliteTokens(integerCheck(name, bits)).map((t) => t.text).toList(),
);

int sqliteIntegerBits(String name, List<SqliteCheck> checks) {
  for (final bits in [16, 32]) {
    final signature = _integerSignature(name, bits);
    if (checks.any((c) => c.name == null && c.signature == signature)) {
      return bits;
    }
  }
  return 64;
}

String withoutIntegerChecks(String sql, List<ColumnInfo> columns) {
  final known = {
    for (final c in columns.where((c) => c.temporalPrecision != null))
      _temporalSignature(
        c.name,
        temporalCollationKind(c.collation)!,
        c.temporalPrecision!,
      ),
    for (final c in columns.where((c) => c.decimalPrecision != null))
      _decimalSignature(c.name, c.decimalPrecision!, c.decimalScale ?? 0),
    for (final c in columns.where((c) => c.storageType == 'INTEGER'))
      for (final bits in [16, 32]) _integerSignature(c.name, bits),
  };
  final result = StringBuffer();
  var start = 0;
  for (final check in sqliteChecks(sql)) {
    if (check.name != null || !known.contains(check.signature)) continue;
    result.write(sql.substring(start, check.start));
    start = check.end;
  }
  return (result..write(sql.substring(start))).toString();
}

String _decimalSignature(String name, int precision, int scale) => jsonEncode(
  sqliteTokens(decimalCheck(name, precision, scale))
      .map((t) => t.text)
      .toList(),
);

(int, int)? sqliteDecimalDigits(String name, List<SqliteCheck> checks) {
  for (final check in checks) {
    if (check.name != null) continue;
    final tokens = (jsonDecode(check.signature) as List).cast<String>();
    final index = tokens.indexOf('ORM_DECIMAL_FITS_V1');
    if (index < 0 || index + 7 >= tokens.length) continue;
    final precision = int.tryParse(tokens[index + 4]);
    final end = tokens.indexOf(')', index + 6);
    if (end < 0) continue;
    final scale = int.tryParse(tokens.sublist(index + 6, end).join());
    if (precision == null ||
        precision < 1 ||
        precision > 1000 ||
        scale == null ||
        scale < -1000 ||
        scale > 1000) {
      continue;
    }
    if (check.signature == _decimalSignature(name, precision, scale)) {
      return (precision, scale);
    }
  }
  return null;
}

String? uncoerceDecimalDefault(String sql, int precision, int scale) {
  final tokens = sqliteTokens(sql);
  if (tokens.length < 8 ||
      tokens[0].text != 'ORM_DECIMAL_CAST_V1' ||
      tokens[1].text != '(' ||
      tokens.last.text != ')') {
    return null;
  }
  final separators = <int>[];
  var depth = 0;
  for (var i = 2; i < tokens.length - 1; i++) {
    if (tokens[i].text == '(') depth++;
    if (tokens[i].text == ')') depth--;
    if (depth < 0) return null;
    if (depth == 0 && tokens[i].text == ',') separators.add(i);
  }
  if (separators.length != 2 || depth != 0) return null;
  final [a, b] = separators;
  if (int.tryParse(tokens.sublist(a + 1, b).map((t) => t.text).join()) !=
          precision ||
      int.tryParse(
            tokens.sublist(b + 1, tokens.length - 1).map((t) => t.text).join(),
          ) !=
          scale) {
    return null;
  }
  return sql.substring(tokens[2].start, tokens[a].start).trim();
}

typedef SqliteCollation = ({
  String column,
  String collation,
  int start,
  int end,
});

// Only column-level clauses at the CREATE TABLE body's outer depth. COLLATE
// inside CHECK/default expressions and table/index constraints is not erased.
List<SqliteCollation> sqliteColumnCollations(String sql) {
  final tokens = sqliteTokens(sql), result = <SqliteCollation>[];
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

String withoutStorageCollations(String sql, List<ColumnInfo> columns) {
  final names = {
    for (final c in columns.where((c) => c.storageType == 'TEXT'))
      sqliteName(c.name),
  };
  final result = StringBuffer();
  var start = 0;
  for (final c in sqliteColumnCollations(sql)) {
    if (!names.contains(sqliteName(c.column)) ||
        !{
          'orm_decimal_v1',
          'orm_date_v1',
          'orm_instant_v1',
          'orm_time_v1',
          'orm_local_datetime_v1',
        }.contains(c.collation.toLowerCase())) {
      continue;
    }
    result.write(sql.substring(start, c.start));
    start = c.end;
  }
  return (result..write(sql.substring(start))).toString();
}

String _temporalSignature(String name, String kind, int digits) => jsonEncode(
  sqliteTokens(temporalCheck(name, kind, digits)).map((t) => t.text).toList(),
);
int? sqliteTemporalPrecision(
  String name,
  String kind,
  List<SqliteCheck> checks,
) {
  for (var digits = 0; digits < 6; digits++) {
    final signature = _temporalSignature(name, kind, digits);
    if (checks.any((c) => c.name == null && c.signature == signature)) {
      return digits;
    }
  }
  return null;
}

String? uncoerceTemporal(String sql, String kind, int digits) {
  final tokens = sqliteTokens(sql);
  if (tokens.length < 8 ||
      tokens[0].text != 'ORM_TEMPORAL_CAST_V1' ||
      tokens[1].text != '(' ||
      tokens.last.text != ')') {
    return null;
  }
  final separators = <int>[];
  var depth = 0;
  for (var i = 2; i < tokens.length - 1; i++) {
    if (tokens[i].text == '(') depth++;
    if (tokens[i].text == ')') depth--;
    if (depth < 0) return null;
    if (depth == 0 && tokens[i].text == ',') separators.add(i);
  }
  if (separators.length != 2 || depth != 0) return null;
  final [a, b] = separators;
  if (b != a + 2 ||
      tokens[a + 1].text != 's:$kind' ||
      tokens.length != b + 3 ||
      int.tryParse(tokens[b + 1].text) != digits) {
    return null;
  }
  return sql.substring(tokens[2].start, tokens[a].start).trim();
}
