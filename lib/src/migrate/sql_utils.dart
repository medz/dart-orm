// SQL quoting and stable migration value fingerprints.

import 'dart:convert' show jsonEncode, utf8;

import 'package:crypto/crypto.dart' show sha256;

String quoteIdentifier(String identifier) =>
    '"${identifier.replaceAll('"', '""')}"';

String postgresLiteral(String value) {
  var tag = r'$orm$';
  while (value.contains(tag)) {
    tag = '${tag.substring(0, tag.length - 1)}_\$';
  }
  return '$tag$value$tag';
}

Object? canonicalMigrationValue(Object? value) => switch (value) {
  Map<String, Object?> map => {
    for (final key in map.keys.toList()..sort())
      key: canonicalMigrationValue(map[key]),
  },
  List<Object?> list => list.map(canonicalMigrationValue).toList(),
  _ => value,
};

String migrationHash(Object? value) => sha256
    .convert(utf8.encode(jsonEncode(canonicalMigrationValue(value))))
    .toString();

Object? freezeMigrationValue(Object? value) => switch (value) {
  Map<String, Object?> map => Map<String, Object?>.unmodifiable({
    for (final entry in map.entries)
      entry.key: freezeMigrationValue(entry.value),
  }),
  List<Object?> list => List<Object?>.unmodifiable(
    list.map(freezeMigrationValue),
  ),
  _ => value,
};
