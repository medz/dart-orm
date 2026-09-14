/// Reviewable schema DDL and checksummed, transactional migration history.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'orm.dart';

part 'src/migrate/schema.dart';
part 'src/migrate/history.dart';
part 'src/migrate/snapshot.dart';
part 'src/migrate/catalog.dart';

String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

Object? _canonical(Object? value) => switch (value) {
  Map<String, Object?> map => {
    for (final key in map.keys.toList()..sort()) key: _canonical(map[key]),
  },
  List<Object?> list => list.map(_canonical).toList(),
  _ => value,
};
String _hash(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();
