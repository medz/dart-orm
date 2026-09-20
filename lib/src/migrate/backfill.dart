// Bounded data backfills and durable primary-key cursors.

import 'dart:convert' show base64Decode, base64Encode, jsonEncode;

import '../../driver.dart' show Backend, SqlCommand, SqlDialect, SqlResult;
import '../../runtime.dart' show SqlDatabase;
import '../../schema_model.dart' show Column;
import '../../values.dart' show Codecs, OrmException;
import 'catalog.dart' show verifySchema;
import 'migration.dart' show Migration;
import 'mysql_schema.dart' show isMysqlFamily, mysqlColumnType;
import 'recovery.dart' show checkpoint, probe;
import 'snapshot.dart' show SchemaSnapshot;
import 'sql_utils.dart' show quoteIdentifier;
import 'step.dart' show Backfill;

/// Durable counters and primary-key cursors. Keys use lossless strings (binary
/// keys use base64), so JSON transport never rounds 64-bit integer identifiers.
final class BackfillProgress {
  /// Inclusive primary-key boundary captured when this backfill first scanned.
  ///
  /// Null means that initial scan found no matching rows. Key components are
  /// losslessly encoded strings in the historical primary-key order.
  final List<String>? upperKey;

  /// Last committed primary key; the next batch resumes strictly after it.
  ///
  /// Null means no nonempty batch has been recorded yet.
  final List<String>? lastKey;

  /// Total updated rows recorded across committed batches.
  final int rows;

  /// Number of nonempty batches committed with their cursor checkpoints.
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

  /// Versioned checkpoint data with lossless string-encoded primary keys.
  Map<String, Object?> toJson() => {
    'format': 1,
    'upper': upperKey,
    'last': lastKey,
    'rows': rows,
    'batches': batches,
  };
}

Future<void> verifyBackfill(SqlDatabase<Backend> db, Backfill step) async {
  final cursor = _BackfillCursor(step);
  if ((!db.capabilities.returning && !isMysqlFamily(db.dialect)) ||
      db.capabilities.maxParameters < 7 ||
      db.capabilities.maxParameters < cursor._keys.length * 2) {
    throw const OrmException(
      'MIGRATION.BACKFILL_CAPABILITY',
      'Backfill needs RETURNING and room for both cursor bounds.',
    );
  }
  final result = await verifySchema(db, SchemaSnapshot([step.table]));
  if (!result.matches ||
      (isMysqlFamily(db.dialect) && result.unmanaged.isNotEmpty)) {
    throw OrmException(
      'MIGRATION.DRIFT',
      [
        ...result.differences,
        ...result.unmanaged.map((o) => '${o.kind}: ${o.name}'),
      ].join('\n'),
    );
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
  } else if (db.dialect == SqlDialect.sqlite &&
      (await db.execute(
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

String parameterMarker(SqlDialect dialect, int n) => switch (dialect) {
  SqlDialect.sqlite => '?$n',
  SqlDialect.postgres => '\$$n',
  SqlDialect.mysql || SqlDialect.mariadb => '?',
};
String _tuple(List<String> values) =>
    values.length == 1 ? values.single : '(${values.join(', ')})';

/// Exactly one transaction: selected rows, writes and frontier advance commit together.
Future<bool> backfillChunk(
  SqlDatabase<Backend> tx,
  Migration migration,
  int index,
  Backfill step,
  BackfillProgress? saved,
  BackfillBudget budget,
  void Function(String) phase,
) async {
  budget.check();
  final cursor = _BackfillCursor(step);
  final names = step.table.primaryKey.map(quoteIdentifier).toList(),
      table = quoteIdentifier(step.table.name);
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
      upper.rows.isEmpty ? null : cursor._saveKey(upper.rows.single),
      null,
      0,
      0,
    );
  }
  final parameters = <Object?>[];
  String bound(List<String> values) {
    final start = parameters.length + 1;
    parameters.addAll(cursor._loadKey(values, tx.dialect));
    return _tuple([
      for (var i = 0; i < values.length; i++)
        isMysqlFamily(tx.dialect) &&
                {'bigint', 'decimal'}.contains(cursor._keys[i].codec.sqlType)
            ? 'CAST(${parameterMarker(tx.dialect, start + i)} AS ${mysqlColumnType(cursor._keys[i])})'
            : parameterMarker(tx.dialect, start + i),
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
            'SELECT $columns FROM $table WHERE ${conditions.join(' AND ')} ORDER BY ${names.map((n) => '$n ASC').join(', ')} LIMIT $size${tx.dialect != SqlDialect.sqlite ? ' FOR UPDATE' : ''}',
            parameters,
          ),
        );
  if (selected.rows.isEmpty) {
    phase('verify');
    if (!await probe(tx, step.doneWhen)) {
      throw const OrmException(
        'MIGRATION.POSTCONDITION',
        'Backfill completion condition is false. Inspect the data and checkpoint before resuming.',
      );
    }
    phase('record');
    await checkpoint(
      tx,
      migration,
      index,
      .complete,
      'complete',
      backfill: progress,
    );
    return true;
  }
  final keys = selected.rows.map(cursor._saveKey).toList();
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
      'UPDATE $table SET ${step.set.entries.map((e) => '${quoteIdentifier(e.key)} = ${e.value}').join(', ')} WHERE $predicate${isMysqlFamily(tx.dialect) ? '' : ' AND (${step.where}) RETURNING $columns'}',
      parameters,
    ),
    changedTables: [step.table.name],
  );
  final expected = keys.map(jsonEncode).toSet(),
      actual = (isMysqlFamily(tx.dialect) ? selected.rows : updated.rows)
          .map(cursor._saveKey)
          .map(jsonEncode)
          .toSet();
  if ((!isMysqlFamily(tx.dialect) && updated.rows.length != keys.length) ||
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
  await checkpoint(
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

final class BackfillPaused implements Exception {}

final class BackfillBudget {
  int? remaining;
  BackfillBudget(this.remaining);
  void check() {
    if (remaining == 0) throw BackfillPaused();
  }

  void used() {
    if (remaining != null) remaining = remaining! - 1;
  }
}

final class _BackfillCursor(final Backfill step) {
  late final List<Column<Object?>> _keys = [
    for (final name in step.table.primaryKey)
      step.table.columns.singleWhere((c) => c.name == name),
  ];

  List<String> _saveKey(List<Object?> row) => [
    for (var i = 0; i < _keys.length; i++)
      switch (_keys[i].codec.sqlType) {
        'text' => row[i] as String,
        'integer' => (row[i] as int).toString(),
        'bigint' => row[i].toString(),
        'decimal' => Codecs.decimal.decode(row[i]).toString(),
        'instant' =>
          Codecs.dateTime.encode(Codecs.dateTime.decode(row[i])) as String,
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
          'instant' when isMysqlFamily(dialect) => Codecs.dateTime.decode(
            row[i],
          ),
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

BackfillProgress readBackfillProgress(Object? data) =>
    BackfillProgress._read(data);
