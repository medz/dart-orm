import '../../runtime.dart';
import '../../sql.dart';

/// Database preparation evidence; this never proves domain codecs/nullability.
final class SqlCheck {
  /// Whether the database accepted the SQL and projected result labels.
  final bool structureChecked;

  /// Whether native result storage families were compared to codecs.
  final bool storageTypesChecked;

  /// Always false: preparation cannot prove result nullability.
  bool get nullabilityChecked => false;

  /// PostgreSQL native type names keyed by required label; empty on other engines.
  final Map<String, String> nativeTypes;

  SqlCheck._(
    this.structureChecked,
    this.storageTypesChecked,
    Map<String, String> types,
  ) : nativeTypes = Map.unmodifiable(types);
}

var _queryCheckSerial = 0;
bool _mysql(SqlDialect dialect) =>
    dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb;

/// Prepares a SELECT/WITH/VALUES query without executing application expressions.
/// Uses a temporary projected subquery only for checking, never for execution.
/// DML, including RETURNING, is outside this check's scope.
///
/// SQLite/MySQL/MariaDB report structure only; PostgreSQL compares native storage
/// families. This cannot prove nullability, numeric range, domain conversion or
/// duplicate labels that an engine silently renames inside a derived table.
/// Runtime result binding still validates actual labels, including empty results.
/// Prepared resources belong to one session and are always released or discarded.
Future<SqlCheck> checkSqlQuery<R>(SqlDatabase<Backend> db, SqlQuery<R> query) {
  final command = query.sql.compile(db.capabilities);
  final columns = query.result.columns;
  return db.session((session) async {
    String quote(String name) => _mysql(db.dialect)
        ? '`${name.replaceAll('`', '``')}`'
        : '"${name.replaceAll('"', '""')}"';
    final alias = quote('_orm_check');
    final projected =
        'SELECT ${columns.map((c) => '$alias.${quote(c.name)}').join(', ')} '
        'FROM (\n${command.sql}\n) AS $alias';
    List<String>? nativeTypes;
    try {
      if (_mysql(db.dialect)) {
        final name =
            '_orm_check_${DateTime.now().microsecondsSinceEpoch}_${_queryCheckSerial++}';
        var prepared = false;
        await session.execute(SqlCommand('SET @$name = ?', [projected]));
        try {
          // EXPLAIN can execute stored functions while planning a derived
          // table (verified on MariaDB 11.8). PREPARE resolves the projection
          // and placeholders without executing the application statement.
          await session.execute(
            SqlCommand('PREPARE ${quote(name)} FROM @$name'),
          );
          prepared = true;
        } finally {
          try {
            if (prepared) {
              await session.execute(
                SqlCommand('DEALLOCATE PREPARE ${quote(name)}'),
              );
            }
            await session.execute(SqlCommand('SET @$name = NULL'));
          } catch (_) {
            // A failed cleanup must not leave a prepared statement or query
            // text attached to a connection returned to another borrower.
            await session.discard();
            rethrow;
          }
        }
      } else if (db.dialect == SqlDialect.sqlite) {
        await session.execute(
          SqlCommand('EXPLAIN $projected', command.parameters),
        );
      } else {
        final name =
            '_orm_check_${DateTime.now().microsecondsSinceEpoch}_${_queryCheckSerial++}';
        await session.execute(
          SqlCommand('PREPARE ${quote(name)} AS $projected'),
        );
        try {
          final result = await session.execute(
            SqlCommand(
              r'SELECT pg_catalog.format_type(t.kind::oid, NULL) '
              r'FROM pg_catalog.pg_prepared_statements p, '
              r'unnest(p.result_types) WITH ORDINALITY AS t(kind, position) '
              r'WHERE p.name = $1 ORDER BY t.position',
              [name],
            ),
          );
          nativeTypes = [for (final row in result.rows) row.single as String];
          if (nativeTypes.length != columns.length) {
            throw const OrmException(
              'SQL.CHECK',
              'Database returned a different result shape.',
            );
          }
          for (var i = 0; i < columns.length; i++) {
            if (!_queryStorageMatches(
              columns[i].codec.sqlType,
              nativeTypes[i],
            )) {
              throw OrmException(
                'SQL.CHECK',
                '${columns[i].name}: declared ${columns[i].codec.sqlType}, database returns ${nativeTypes[i]}. Use an explicit SQL cast or matching codec storage.',
              );
            }
          }
        } finally {
          try {
            await session.execute(SqlCommand('DEALLOCATE ${quote(name)}'));
          } catch (_) {
            await session.discard();
            rethrow;
          }
        }
      }
    } catch (error) {
      throw OrmException(
        'SQL.CHECK',
        '${db.dialect.name}: $error',
        cause: error,
      );
    }
    return SqlCheck._(true, nativeTypes != null, {
      if (nativeTypes != null)
        for (var i = 0; i < columns.length; i++)
          columns[i].name: nativeTypes[i],
    });
  });
}

bool _queryStorageMatches(String storage, String native) => switch (storage) {
  'integer' ||
  'bigint' ||
  'decimal' => {'smallint', 'integer', 'bigint', 'numeric'}.contains(native),
  'real' => {
    'real',
    'double precision',
    'numeric',
    'smallint',
    'integer',
    'bigint',
  }.contains(native),
  'text' => {'text', 'character varying', 'character', 'name'}.contains(native),
  'boolean' => native == 'boolean',
  'instant' => native == 'timestamp with time zone',
  'date' => native == 'date',
  'time' => native == 'time without time zone',
  'local_datetime' => native == 'timestamp without time zone',
  'json' => {'json', 'jsonb'}.contains(native),
  'blob' => native == 'bytea',
  _ => false,
};
