import 'dart:typed_data';

import 'package:orm/database.dart';
import 'package:orm/schema.dart';

import 'filter.dart';

/// Generated decoders read positional cells without maps or reflection.
typedef RowDecoder<R> = R Function(List<Object?> row);

/// One explicit ordering direction. Collation belongs to the database engine.
enum Direction { ascending, descending }

/// Ascending order, used with a generated table's orderBy method.
const asc = Direction.ascending;

/// Descending order, used with a generated table's orderBy method.
const desc = Direction.descending;

/// Quotes one physical identifier; arbitrary values must always be bound.
String quoteIdentifier(String name) {
  if (name.isEmpty || name.contains('\u0000')) {
    throw ArgumentError('Invalid SQL identifier');
  }
  return '"${name.replaceAll('"', '""')}"';
}

/// Scalar decoder shared by generated model and record selections.
T decodeValue<T>(Object? value) {
  if (value == null) throw FormatException('Unexpected SQL NULL for $T');
  if (T == DateTime) {
    if (value is DateTime) return value.toUtc() as T;
    if (value is int) {
      return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true) as T;
    }
  }
  if (value is T) return value as T;
  if (T == bool && value is int && (value == 0 || value == 1)) {
    return (value == 1) as T;
  }
  if (T == double && value is num) return value.toDouble() as T;
  if (T == Uint8List && value is List<int>) {
    return Uint8List.fromList(value) as T;
  }
  throw FormatException('Cannot decode ${value.runtimeType} as $T');
}

/// Immutable query scope used by statically generated field-specific facades.
/// SQL field names resolve only within this physical table. Mutation return
/// shapes are decoded from RETURNING; no preparatory SELECT is performed.
final class TableQuery<R> {
  TableQuery(this.session, TableDefinition definition, this.decode)
    : definition = TableDefinition(
        definition.name,
        List.unmodifiable(definition.columns),
      ),
      _filters = const [],
      _orders = const [],
      _limit = null,
      _offset = null {
    _validateDefinition();
  }
  TableQuery._(
    this.session,
    this.definition,
    this.decode,
    this._filters,
    this._orders,
    this._limit,
    this._offset,
  );

  final Session session;
  final TableDefinition definition;
  final RowDecoder<R> decode;
  final List<Map<String, Filter<Object?>>> _filters;
  final List<(String, Direction)> _orders;
  final int? _limit;
  final int? _offset;

  void _validateDefinition() {
    quoteIdentifier(definition.name);
    if (definition.columns.isEmpty) {
      throw ArgumentError('A table requires columns');
    }
    final fields = <String>{};
    final names = <String>{};
    var primaryKeys = 0;
    for (final c in definition.columns) {
      quoteIdentifier(c.name);
      if (c.field.isEmpty || !fields.add(c.field) || !names.add(c.name)) {
        throw ArgumentError('Duplicate column identity');
      }
      if (c.primaryKey) {
        primaryKeys++;
        if (c.nullable) {
          throw ArgumentError('Primary keys cannot be nullable');
        }
      }
      if (c.identity &&
          (!c.primaryKey ||
              c.type != ScalarType.integer ||
              c.defaultValue != null)) {
        throw ArgumentError(
          'Identity requires an integer primary key without a default',
        );
      }
    }
    if (primaryKeys > 1) {
      throw ArgumentError('Composite primary keys are unsupported');
    }
  }

  TableQuery<R> _copy({
    List<Map<String, Filter<Object?>>>? filters,
    List<(String, Direction)>? orders,
    int? limit,
    int? offset,
  }) => TableQuery._(
    session,
    definition,
    decode,
    filters ?? _filters,
    orders ?? _orders,
    limit ?? _limit,
    offset ?? _offset,
  );

  /// Adds an AND group of fields within this table. Empty or unknown fields
  /// throw before SQL. Generated facades expose typed named field arguments.
  TableQuery<R> whereFields(Map<String, Filter<Object?>> fields) {
    for (final key in fields.keys) {
      definition.column(key);
    }
    if (fields.isEmpty) throw ArgumentError('Empty filter');
    return _copy(
      filters: List.unmodifiable([
        ..._filters,
        Map<String, Filter<Object?>>.unmodifiable(fields),
      ]),
    );
  }

  /// Use one field per call; chained calls preserve explicit sort precedence.
  TableQuery<R> orderByFields(Map<String, Direction> fields) {
    if (fields.length != 1) throw ArgumentError('Order one field per call');
    final field = fields.keys.single;
    definition.column(field);
    return _copy(
      orders: List.unmodifiable([..._orders, (field, fields[field]!)]),
    );
  }

  /// Limits reads to [count] rows. Negative values throw before SQL.
  TableQuery<R> limit(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return _copy(limit: count);
  }

  /// Skips [count] rows. Choose explicit ordering for stable pagination.
  TableQuery<R> offset(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count');
    return _copy(offset: count);
  }

  ColumnDefinition get _primary {
    final keys = definition.columns.where((c) => c.primaryKey).toList();
    if (keys.length != 1) {
      throw StateError('Operation requires one primary key');
    }
    return keys.single;
  }

  _Bindings _bindings() => _Bindings(session);
  String _where(_Bindings bindings) {
    final parts = <String>[];
    for (final group in _filters) {
      for (final e in group.entries) {
        final column = definition.column(e.key);
        parts.add(
          e.value.compile(quoteIdentifier(column.name), (v) {
            _checkValue(column, v, filter: true);
            return bindings.bind(v);
          }, column.type),
        );
      }
    }
    return parts.isEmpty
        ? ''
        : ' WHERE ${parts.map((p) => '($p)').join(' AND ')}';
  }

  String _readSuffix(_Bindings bindings) {
    var sql = _where(bindings);
    if (_orders.isNotEmpty) {
      sql +=
          ' ORDER BY ${_orders.map((o) => '${quoteIdentifier(definition.column(o.$1).name)} ${o.$2 == asc ? 'ASC' : 'DESC'}').join(', ')}';
    }
    if (_limit != null) sql += ' LIMIT ${bindings.bind(_limit)}';
    if (_offset != null) {
      if (_limit == null && session.engine == Engine.sqlite) sql += ' LIMIT -1';
      sql += ' OFFSET ${bindings.bind(_offset)}';
    }
    return sql;
  }

  String get _table => quoteIdentifier(definition.name);
  String get _columns =>
      definition.columns.map((c) => quoteIdentifier(c.name)).join(', ');

  /// Reads only the requested Dart fields and returns an immutable list.
  /// Field validation precedes execution; decoder failures propagate.
  Future<List<T>> selectRows<T>(
    List<String> fields,
    RowDecoder<T> decoder,
  ) async {
    if (fields.isEmpty || fields.toSet().length != fields.length) {
      throw ArgumentError('Invalid selection');
    }
    final columns = fields
        .map((f) => quoteIdentifier(definition.column(f).name))
        .join(', ');
    final bindings = _bindings();
    final result = await session.run(
      'SELECT $columns FROM $_table${_readSuffix(bindings)}',
      parameters: bindings.values,
    );
    return List<T>.unmodifiable(result.rows.map(decoder));
  }

  /// Reads complete rows in this immutable query scope.
  Future<List<R>> all() =>
      selectRows([for (final c in definition.columns) c.field], decode);

  /// Reads one key within the filters, or null. Rejects paging and sorting.
  Future<R?> get(Object id) async {
    _rejectPaging();
    final result = await whereFields({_primary.field: eq<Object?>(id)})
        .limit(2)
        .all();
    if (result.length > 1) {
      throw StateError('Primary key returned multiple rows');
    }
    return result.firstOrNull;
  }

  void _returning() {
    if (!session.capabilities.returning) {
      throw UnsupportedError('Driver does not support RETURNING');
    }
  }

  void _rejectPaging() {
    if (_limit != null || _offset != null || _orders.isNotEmpty) {
      throw StateError('Mutation/get scope cannot contain paging or sorting');
    }
  }

  void _checkValue(ColumnDefinition c, Object? value, {bool filter = false}) {
    if (value == null) {
      if (!filter && !c.nullable) {
        throw ArgumentError('${c.field} is not nullable');
      }
      return;
    }
    final valid = switch (c.type) {
      ScalarType.integer => value is int,
      ScalarType.text => value is String,
      ScalarType.boolean => value is bool,
      ScalarType.real => value is num && value.isFinite,
      ScalarType.dateTime => value is DateTime,
      ScalarType.bytes => value is Uint8List,
    };
    if (!valid) throw ArgumentError('Invalid value for ${c.field} (${c.type})');
  }

  /// Inserts one row and returns the engine's RETURNING result.
  /// Requires an unfiltered scope and RETURNING capability. Omitted database
  /// defaults remain omitted; invalid fields and values fail before SQL.
  Future<R> insert(Map<String, Object?> values) async {
    final row = await _insert(values);
    if (row == null) throw StateError('Create must return one row');
    return row;
  }

  /// Inserts a row, or returns null when its supplied unique key already exists.
  /// Other constraint failures propagate. The conflict field must be an
  /// insertable single-column primary/unique key with a provided non-null value.
  /// This operation never changes an existing row or executes a prior SELECT.
  Future<R?> insertIfAbsent(
    Map<String, Object?> values, {
    required String conflictField,
  }) {
    final column = definition.column(conflictField);
    if (column.identity ||
        (!column.primaryKey && !column.unique) ||
        !values.containsKey(conflictField) ||
        values[conflictField] == null) {
      throw ArgumentError(
        'Conflict target requires a supplied non-null unique key',
      );
    }
    return _insert(values, conflictColumn: column);
  }

  Future<R?> _insert(
    Map<String, Object?> values, {
    ColumnDefinition? conflictColumn,
  }) async {
    _returning();
    if (_filters.isNotEmpty) {
      throw StateError('Create requires an unfiltered table');
    }
    _rejectPaging();
    for (final c in definition.columns) {
      if (!values.containsKey(c.field) &&
          !c.nullable &&
          !c.identity &&
          c.defaultValue == null) {
        throw ArgumentError('Missing required field ${c.field}');
      }
    }
    final bindings = _bindings();
    final columns = <String>[];
    final parameters = <String>[];
    for (final e in values.entries) {
      final c = definition.column(e.key);
      if (c.identity) throw ArgumentError('Identity field cannot be inserted');
      _checkValue(c, e.value);
      columns.add(quoteIdentifier(c.name));
      parameters.add(bindings.bind(e.value));
    }
    final clause = columns.isEmpty
        ? 'DEFAULT VALUES'
        : '(${columns.join(', ')}) VALUES (${parameters.join(', ')})';
    final conflict = conflictColumn == null
        ? ''
        : ' ON CONFLICT (${quoteIdentifier(conflictColumn.name)}) DO NOTHING';
    final result = await session.run(
      'INSERT INTO $_table $clause$conflict RETURNING $_columns',
      parameters: bindings.values,
    );
    if (conflictColumn != null && result.rows.isEmpty) return null;
    if (result.rows.length != 1) throw StateError('Create must return one row');
    return decode(result.rows.single);
  }

  /// Updates supplied fields within the key and filters, returning the changed
  /// row or null. Omitted fields remain untouched; nullable null clears a field.
  Future<R?> updateById(Object id, Map<String, Object?> values) async {
    _returning();
    _rejectPaging();
    if (values.isEmpty) {
      throw ArgumentError('Update requires at least one field');
    }
    final scoped = whereFields({_primary.field: eq<Object?>(id)});
    final bindings = _bindings();
    final assignments = <String>[];
    for (final e in values.entries) {
      final c = definition.column(e.key);
      if (c.primaryKey || c.identity) {
        throw ArgumentError('Primary key updates are unsupported');
      }
      _checkValue(c, e.value);
      assignments.add('${quoteIdentifier(c.name)} = ${bindings.bind(e.value)}');
    }
    final result = await session.run(
      'UPDATE $_table SET ${assignments.join(', ')}${scoped._where(bindings)} RETURNING $_columns',
      parameters: bindings.values,
    );
    if (result.rows.length > 1) {
      throw StateError('Primary key update returned multiple rows');
    }
    return result.rows.isEmpty ? null : decode(result.rows.single);
  }

  /// Deletes within the key and filters and returns the affected row count.
  Future<int> deleteById(Object id) async {
    _rejectPaging();
    final scoped = whereFields({_primary.field: eq<Object?>(id)});
    final bindings = _bindings();
    final result = await session.run(
      'DELETE FROM $_table${scoped._where(bindings)}',
      parameters: bindings.values,
    );
    return result.affectedRows;
  }

  /// Adds positive amounts atomically and returns the row, or null if the key,
  /// filters or signed 64-bit integer bounds do not match. SQLite also guards
  /// finite REAL bounds; PostgreSQL reports real overflow as a SQL error.
  Future<R?> incrementById(Object id, Map<String, num> values) =>
      _changeById(id, values, '+');

  /// Subtracts positive amounts with the same guards as [incrementById].
  Future<R?> decrementById(Object id, Map<String, num> values) =>
      _changeById(id, values, '-');
  Future<R?> _changeById(
    Object id,
    Map<String, num> values,
    String operator,
  ) async {
    _returning();
    _rejectPaging();
    if (values.isEmpty) throw ArgumentError('Numeric update requires fields');
    var scoped = whereFields({_primary.field: eq<Object?>(id)});
    final bindings = _bindings();
    final assignments = <String>[];
    final realBounds = <(String, num)>[];
    for (final e in values.entries) {
      final c = definition.column(e.key);
      if (c.primaryKey ||
          c.references != null ||
          c.nullable ||
          (c.type != ScalarType.integer && c.type != ScalarType.real)) {
        throw ArgumentError(
          'Numeric update requires a non-null numeric value column',
        );
      }
      _checkValue(c, e.value);
      if (e.value <= 0) throw ArgumentError('Numeric change must be positive');
      final name = quoteIdentifier(c.name);
      assignments.add('$name = $name $operator ${bindings.bind(e.value)}');
      if (c.type == ScalarType.integer) {
        // SQLite would silently promote an overflowing integer to REAL.
        // Bound the operand instead, preserving exact signed 64-bit storage.
        const maxInteger = 9223372036854775807;
        const minInteger = -9223372036854775808;
        final amount = e.value as int;
        scoped = scoped.whereFields({
          c.field: operator == '+'
              ? lte<Object?>(maxInteger - amount)
              : gte<Object?>(minInteger + amount),
        });
      } else if (session.engine == Engine.sqlite) {
        // SQLite also permits Infinity after REAL arithmetic. Test the same
        // expression in WHERE before changing the stored value.
        realBounds.add((name, e.value));
      }
    }
    final where = scoped._where(bindings);
    const maxReal = 1.7976931348623157e308;
    // Keep positional SQLite bindings in the same order as the SQL text.
    final bounds = realBounds.isEmpty
        ? ''
        : ' AND ${realBounds.map((bound) => '((${bound.$1} $operator ${bindings.bind(bound.$2)}) BETWEEN ${bindings.bind(-maxReal)} AND ${bindings.bind(maxReal)})').join(' AND ')}';
    final result = await session.run(
      'UPDATE $_table SET ${assignments.join(', ')}$where$bounds RETURNING $_columns',
      parameters: bindings.values,
    );
    if (result.rows.length > 1) {
      throw StateError('Primary key update returned multiple rows');
    }
    return result.rows.isEmpty ? null : decode(result.rows.single);
  }

  /// Bounded keyset batches within an explicit transaction. Non-primary-key
  /// ordering and offsets are rejected; the cursor never buffers all results.
  Stream<R> stream({int fetchSize = 500}) async* {
    if (!session.inTransaction) {
      throw StateError('Streaming requires a transaction');
    }
    if (fetchSize < 1 || _offset != null || _orders.isNotEmpty) {
      throw ArgumentError('Streaming uses primary-key order without offsets');
    }
    final primary = _primary;
    if (primary.type != ScalarType.integer && primary.type != ScalarType.text) {
      throw UnsupportedError('Streaming supports integer/text primary keys');
    }
    Object? cursor;
    var remaining = _limit;
    while (remaining == null || remaining > 0) {
      final count = remaining == null || remaining > fetchSize
          ? fetchSize
          : remaining;
      var page = TableQuery<R>._(
        session,
        definition,
        decode,
        _filters,
        [(primary.field, asc)],
        count,
        null,
      );
      if (cursor != null) {
        page = page.whereFields({primary.field: gt<Object?>(cursor)});
      }
      final bindings = page._bindings();
      final result = await session.run(
        'SELECT $_columns FROM $_table${page._readSuffix(bindings)}',
        parameters: bindings.values,
      );
      for (final cells in result.rows) {
        yield decode(cells);
      }
      if (result.rows.length < count) break;
      cursor = result.rows.last[definition.columns.indexOf(primary)];
      if (remaining != null) remaining -= result.rows.length;
    }
  }
}

final class _Bindings {
  _Bindings(this.session);
  final Session session;
  final List<Object?> values = [];
  String bind(Object? value) {
    if (values.length >= session.capabilities.maxParameters) {
      throw UnsupportedError('Query exceeds driver parameter limit');
    }
    values.add(value);
    return session.engine == Engine.postgresql ? '\$${values.length}' : '?';
  }
}
