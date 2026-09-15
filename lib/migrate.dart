/// Reviewable schema DDL with checksummed transactional and recoverable migrations.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'orm.dart';

part 'src/migrate/schema.dart';
part 'src/migrate/history.dart';
part 'src/migrate/snapshot.dart';
part 'src/migrate/source.dart';
part 'src/migrate/catalog.dart';
part 'src/migrate/step.dart';
part 'src/migrate/diff.dart';
part 'src/migrate/recovery.dart';
part 'src/migrate/backfill.dart';
part 'src/migrate/sqlite_checks.dart';
part 'src/migrate/checks.dart';
part 'src/migrate/computed.dart';

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

Object? _freezeJson(Object? value) => switch (value) {
  Map<String, Object?> map => Map<String, Object?>.unmodifiable({
    for (final entry in map.entries) entry.key: _freezeJson(entry.value),
  }),
  List<Object?> list => List<Object?>.unmodifiable(list.map(_freezeJson)),
  _ => value,
};
