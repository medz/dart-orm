import 'dart:convert';

import 'package:dart_style/dart_style.dart';

String snakeCase(String value) => value
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
    .toLowerCase();
String dartLiteral(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
String dartStringList(List<String> values) =>
    '[${values.map(dartLiteral).join(', ')}]';
bool sameStrings(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((v) => v);

String formatMigration(String source) =>
    DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
        .format(source);
