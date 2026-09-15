part of '../../migrate.dart';

/// A reviewed, bounded update using this migration's historical table definition.
/// Expressions and completion SQL are trusted migration code. Primary keys must
/// remain immutable, including in application writes and triggers.
final class Backfill extends MigrationStep {
  final TableSchema table;
  final Map<String, String> set;
  final String where;
  final String doneWhen;
  final int batchSize;
  late final List<Column<Object?>> _keys = [
    for (final name in table.primaryKey)
      table.columns.singleWhere((c) => c.name == name),
  ];

  Backfill(
    this.table, {
    required Map<String, String> set,
    this.where = 'TRUE',
    required this.doneWhen,
    this.batchSize = 1000,
  }) : set = Map.unmodifiable(set) {
    SchemaSnapshot([table]);
    if (batchSize < 1 ||
        set.isEmpty ||
        where.trim().isEmpty ||
        set.entries.any(
          (e) =>
              e.value.trim().isEmpty ||
              !table.columns.any((c) => c.name == e.key && !c.generated) ||
              table.primaryKey.contains(e.key),
        )) {
      throw ArgumentError(
        'Backfill needs a positive batch size and assignments to existing non-key columns.',
      );
    }
    if (table.primaryKey.isEmpty ||
        _keys.any((c) => c.nullable || c.codec.sqlType == 'json')) {
      throw const OrmException(
        'MIGRATION.BACKFILL_KEY',
        'Backfill requires a non-null primary key with lossless cursor storage; JSON keys are unsupported.',
      );
    }
    if (_sqlWords(doneWhen).firstOrNull != 'SELECT') {
      throw const OrmException(
        'MIGRATION.PROBE',
        'Backfill completion must be a SELECT returning one boolean.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': 'backfill',
    'table': _tableJson(table),
    'set': set,
    'where': where,
    'doneWhen': doneWhen,
    'batchSize': batchSize,
  };

  List<String> _saveKey(List<Object?> row) => [
    for (var i = 0; i < _keys.length; i++)
      switch (_keys[i].codec.sqlType) {
        'text' => row[i] as String,
        'integer' => (row[i] as int).toString(),
        'bigint' => row[i].toString(),
        'decimal' => Codecs.decimal.decode(row[i]).toString(),
        'date' => Codecs.date.decode(row[i]).toString(),
        'time' => Codecs.time.decode(row[i]).toString(),
        'local_datetime' => Codecs.localDateTime.decode(row[i]).toString(),
        'timestamp' =>
          row[i] is DateTime
              ? (row[i] as DateTime).toUtc().toIso8601String()
              : row[i] as String,
        'boolean' => Codecs.boolean.decode(row[i]) ? '1' : '0',
        'blob' => base64Encode((row[i] as List<int>)),
        'real' when (row[i] as num).isFinite => row[i].toString(),
        _ => throw const OrmException(
          'MIGRATION.BACKFILL_KEY',
          'Backfill keys must have lossless, finite storage values.',
        ),
      },
  ];
  List<Object?> _loadKey(List<String> row, SqlDialect dialect) {
    if (row.length != _keys.length) {
      throw const OrmException(
        'MIGRATION.CHECKPOINT',
        'Backfill cursor key length differs from the historical primary key.',
      );
    }
    return [
      for (var i = 0; i < row.length; i++)
        switch (_keys[i].codec.sqlType) {
          'integer' => int.parse(row[i]),
          'real' => double.parse(row[i]),
          'timestamp' when dialect == SqlDialect.postgres => DateTime.parse(
            row[i],
          ),
          'boolean' =>
            dialect == SqlDialect.postgres ? row[i] == '1' : int.parse(row[i]),
          'blob' => base64Decode(row[i]),
          _ => row[i],
        },
    ];
  }
}

/// Durable counters and primary-key cursors. Keys use lossless strings (binary
/// keys use base64), so JSON transport never rounds 64-bit integer identifiers.
final class BackfillProgress {
  final List<String>? upperKey;
  final List<String>? lastKey;
  final int rows;
  final int batches;
  BackfillProgress._(
    List<String>? upper,
    List<String>? last,
    this.rows,
    this.batches,
  ) : upperKey = upper == null ? null : List.unmodifiable(upper),
      lastKey = last == null ? null : List.unmodifiable(last);
  factory BackfillProgress._read(Object? data) {
    final json = data as Map<String, Object?>;
    if (json['format'] != 1) {
      throw const OrmException(
        'MIGRATION.CHECKPOINT',
        'Unknown backfill checkpoint format.',
      );
    }
    final value = BackfillProgress._(
      (json['upper'] as List<Object?>?)?.cast<String>(),
      (json['last'] as List<Object?>?)?.cast<String>(),
      json['rows'] as int,
      json['batches'] as int,
    );
    if (value.rows < 0 ||
        value.batches < 0 ||
        value.batches > value.rows ||
        (value.rows > 0 && (value.lastKey == null || value.batches == 0)) ||
        (value.rows == 0 && value.lastKey != null) ||
        (value.lastKey != null && value.upperKey == null) ||
        value.upperKey?.isEmpty == true ||
        value.lastKey?.isEmpty == true) {
      throw const OrmException(
        'MIGRATION.CHECKPOINT',
        'Invalid backfill checkpoint.',
      );
    }
    return value;
  }
  Map<String, Object?> toJson() => {
    'format': 1,
    'upper': upperKey,
    'last': lastKey,
    'rows': rows,
    'batches': batches,
  };
}

Future<void> _verifyBackfill(Database<Backend> db, Backfill step) async {
  if (!db.capabilities.returning ||
      db.capabilities.maxParameters < 7 ||
      db.capabilities.maxParameters < step._keys.length * 2) {
    throw const OrmException(
      'MIGRATION.BACKFILL_CAPABILITY',
      'Backfill needs RETURNING and room for both cursor bounds.',
    );
  }
  final result = await verifySchema(db, SchemaSnapshot([step.table]));
  if (!result.matches) {
    throw OrmException('MIGRATION.DRIFT', result.differences.join('\n'));
  }
  if (db.dialect == SqlDialect.postgres) {
    final security = await db.execute(
      SqlCommand(
        r'''SELECT row_security_active(c.oid), pg_table_is_visible(c.oid)
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = current_schema() AND c.relname = $1''',
        [step.table.name],
      ),
    );
    if (security.rows.single[0] == true || security.rows.single[1] != true) {
      throw const OrmException(
        'MIGRATION.BACKFILL_SCOPE',
        'The historical table is shadowed or has active row security. Backfill requires an unshadowed table and a role that sees all its rows.',
      );
    }
  } else if ((await db.execute(
    SqlCommand(
      "SELECT 1 FROM sqlite_temp_schema WHERE type IN ('table', 'view') AND name = ?1 COLLATE NOCASE",
      [step.table.name],
    ),
  )).rows.isNotEmpty) {
    throw const OrmException(
      'MIGRATION.BACKFILL_SCOPE',
      'A temporary object shadows the historical table.',
    );
  }
}

String _mark(SqlDialect dialect, int n) =>
    dialect == SqlDialect.sqlite ? '?$n' : '\$$n';
String _tuple(List<String> values) =>
    values.length == 1 ? values.single : '(${values.join(', ')})';

/// Exactly one transaction: selected rows, writes and frontier advance commit together.
Future<bool> _backfillChunk(
  Database<Backend> tx,
  Migration migration,
  int index,
  Backfill step,
  BackfillProgress? saved,
  _BackfillBudget budget,
  void Function(String) phase,
) async {
  budget.check();
  final names = step.table.primaryKey.map(_quote).toList(),
      table = _quote(step.table.name);
  final columns = names.join(', '), key = _tuple(names);
  phase('scan');
  var progress = saved;
  if (progress == null) {
    final upper = await tx.execute(
      SqlCommand(
        'SELECT $columns FROM $table WHERE (${step.where}) ORDER BY ${names.map((n) => '$n DESC').join(', ')} LIMIT 1',
      ),
    );
    progress = BackfillProgress._(
      upper.rows.isEmpty ? null : step._saveKey(upper.rows.single),
      null,
      0,
      0,
    );
  }
  final parameters = <Object?>[];
  String bound(List<String> values) {
    final start = parameters.length + 1;
    parameters.addAll(step._loadKey(values, tx.dialect));
    return _tuple([
      for (var i = 0; i < values.length; i++) _mark(tx.dialect, start + i),
    ]);
  }

  final capacity = tx.capabilities.maxParameters ~/ names.length;
  final size = step.batchSize < capacity ? step.batchSize : capacity;
  final conditions = [
    if (progress.lastKey != null) '$key > ${bound(progress.lastKey!)}',
    if (progress.upperKey != null) '$key <= ${bound(progress.upperKey!)}',
    '(${step.where})',
  ];
  final selected = progress.upperKey == null
      ? const SqlResult([])
      : await tx.execute(
          SqlCommand(
            'SELECT $columns FROM $table WHERE ${conditions.join(' AND ')} ORDER BY ${names.map((n) => '$n ASC').join(', ')} LIMIT $size${tx.dialect == SqlDialect.postgres ? ' FOR UPDATE' : ''}',
            parameters,
          ),
        );
  if (selected.rows.isEmpty) {
    phase('verify');
    if (!await _probe(tx, step.doneWhen)) {
      throw const OrmException(
        'MIGRATION.POSTCONDITION',
        'Backfill completion condition is false. Inspect the data and checkpoint before resuming.',
      );
    }
    phase('record');
    await _checkpoint(
      tx,
      migration,
      index,
      .complete,
      'complete',
      backfill: progress,
    );
    return true;
  }
  final keys = selected.rows.map(step._saveKey).toList();
  if (keys.map(jsonEncode).toSet().length != keys.length) {
    throw const OrmException(
      'MIGRATION.BACKFILL_KEY',
      'The scan returned duplicate primary keys; its ordering is not unique.',
    );
  }
  parameters.clear();
  final tuples = keys.map(bound).toList();
  final predicate = names.length == 1
      ? '$key IN (${tuples.join(', ')})'
      : '$key IN (${tx.dialect == SqlDialect.sqlite ? 'VALUES ' : ''}${tuples.join(', ')})';
  phase('update');
  final updated = await tx.execute(
    SqlCommand(
      'UPDATE $table SET ${step.set.entries.map((e) => '${_quote(e.key)} = ${e.value}').join(', ')} WHERE $predicate AND (${step.where}) RETURNING $columns',
      parameters,
    ),
    changedTables: [step.table],
  );
  final expected = keys.map(jsonEncode).toSet(),
      actual = updated.rows.map(step._saveKey).map(jsonEncode).toSet();
  if (updated.rows.length != keys.length ||
      actual.length != expected.length ||
      !actual.containsAll(expected)) {
    throw const OrmException(
      'MIGRATION.BACKFILL_CHANGED',
      'Backfill did not update exactly its selected primary keys.',
    );
  }
  // Also detect AFTER triggers deleting or moving selected primary keys.
  final retained = await tx.execute(
    SqlCommand('SELECT count(*) FROM $table WHERE $predicate', parameters),
  );
  if (retained.rows.single.single != keys.length) {
    throw const OrmException(
      'MIGRATION.BACKFILL_CHANGED',
      'A backfill trigger removed or changed selected primary keys.',
    );
  }
  phase('record');
  await _checkpoint(
    tx,
    migration,
    index,
    .running,
    'backfill',
    backfill: BackfillProgress._(
      progress.upperKey,
      keys.last,
      progress.rows + keys.length,
      progress.batches + 1,
    ),
  );
  budget.used();
  return false;
}

final class _BackfillPaused implements Exception {}

final class _BackfillBudget {
  int? remaining;
  _BackfillBudget(this.remaining);
  void check() {
    if (remaining == 0) throw _BackfillPaused();
  }

  void used() {
    if (remaining != null) remaining = remaining! - 1;
  }
}
