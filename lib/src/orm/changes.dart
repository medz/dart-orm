import 'dart:async';

import 'package:meta/meta.dart' show internal;

import '../../driver.dart';
import '../../schema_model.dart';

final _hubs = Expando<ChangeHub>();

/// @nodoc
@internal
ChangeHub changesFor(Driver<Backend> driver) => _hubs[driver] ??= ChangeHub();

/// @nodoc
@internal
abstract interface class ChangeSubscription {
  Set<String> get tables;
  void invalidate();
  Future<void> stop();
}

/// @nodoc
@internal
void mergeChanges(Map<String, bool> target, Map<String, bool> source) {
  for (final entry in source.entries) {
    target[entry.key] = (target[entry.key] ?? false) || entry.value;
  }
}

/// Shared by views of the same driver, without global result caching.
/// @nodoc
@internal
final class ChangeHub {
  final _schemas = Expando<bool>();
  final Map<String, TableSchema> _tables = {};
  final Map<String, Map<String, bool>> _deleteEffects = {};
  final Set<ChangeSubscription> watches = {};
  bool closed = false;

  void register(Iterable<TableSchema> schema) {
    if (!closed && _schemas[schema] != true) {
      _schemas[schema] = true;
      for (final table in schema) {
        registerTable(table);
      }
    }
  }

  void registerTable(TableSchema table) {
    if (closed || identical(_tables[table.name], table)) return;
    final previous = _tables[table.name];
    if (previous != null) {
      for (final fk in previous.foreignKeys) {
        final effects = _deleteEffects[fk.target];
        effects?.remove(table.name);
        if (effects?.isEmpty ?? false) _deleteEffects.remove(fk.target);
      }
    }
    _tables[table.name] = table;
    for (final fk in table.foreignKeys) {
      if (!{'CASCADE', 'SET NULL', 'SET DEFAULT'}.contains(fk.onDelete)) {
        continue;
      }
      final effects = _deleteEffects.putIfAbsent(fk.target, () => {});
      effects[table.name] =
          (effects[table.name] ?? false) || fk.onDelete == 'CASCADE';
    }
  }

  void publish(Map<String, bool> changes) {
    if (closed || changes.isEmpty || watches.isEmpty) return;
    final affected = changes.keys.toSet();
    final deletes = [
      for (final e in changes.entries)
        if (e.value) e.key,
    ];
    final visited = <String>{};
    while (deletes.isNotEmpty) {
      final table = deletes.removeLast();
      if (!visited.add(table)) continue;
      for (final effect
          in (_deleteEffects[table] ?? const <String, bool>{}).entries) {
        affected.add(effect.key);
        if (effect.value) deletes.add(effect.key);
      }
    }
    for (final watch in watches.toList()) {
      if (watch.tables.any(affected.contains)) watch.invalidate();
    }
  }

  Future<void> stop() async {
    closed = true;
    await Future.wait(watches.toList().map((watch) => watch.stop()));
    _tables.clear();
    _deleteEffects.clear();
  }
}
