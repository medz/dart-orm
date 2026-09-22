import 'dart:typed_data';

import '../../driver.dart';
import '../../schema_model.dart';
import 'nodes.dart';
import 'result.dart';
import 'sql_text.dart';
import 'table.dart';

/// A value encoded once with an explicit storage codec, independent of a session.
/// Mutable bytes are copied. Use a JSON codec for maps and lists.
final class SqlValue<T> {
  final Object? _encoded;
  final String _storage;

  /// Encodes now; subsequent compilation never calls the codec again.
  SqlValue(T value, Codec<T> codec)
    : _encoded = _snapshot(codec.encode(value)),
      _storage = codec.sqlType;
}

Object? _snapshot(Object? value) => switch (value) {
  null || String() || num() || bool() || DateTime() || SqlReal() => value,
  Uint8List() => Uint8List.fromList(value).asUnmodifiableView(),
  _ => throw ArgumentError('Use a codec to encode this SQL parameter.'),
};

/// Reuses a physical column's codec for raw parameters and result labels.
extension ColumnSql<T> on Column<T> {
  /// Encodes a bound value using this column's domain type.
  SqlValue<T> bind(T value) => SqlValue(value, codec);

  /// Describes a result label without inheriting physical column constraints.
  ResultColumn<T> result({String? as}) => ResultColumn(as ?? name, codec);
}

/// Reuses a table field's codec without capturing its alias or connection.
extension FieldSql<T> on ReadField<T> {
  /// Encodes a bound value using this field's domain type.
  SqlValue<T> bind(T value) => SqlValue(value, codec);

  /// Describes the physical name or an explicit SQL result alias.
  ResultColumn<T> result({String? as}) =>
      ResultColumn(as ?? definition.name, codec);
}

/// Immutable SQL text, values and composition, with no connection or row cache.
///
/// Text is trusted SQL. Supply application values through named parameters;
/// placeholders cannot stand for identifiers or SQL syntax. Native SQL is not
/// translated between engines. Compilation checks lexical boundaries and one
/// statement, while the database checks SQL semantics.
sealed class Sql {
  const Sql._();

  /// Captures text and exactly its `:name` parameters. Repeated local names share
  /// a value. Use [SqlValue] for domain types and explicit storage codecs.
  /// Raw scalar values retain the driver's type inference; maps/lists require
  /// a codec. Byte buffers and the parameter map are copied at construction.
  factory Sql(String text, {Map<String, Object?> parameters = const {}}) =>
      _TextSql(text, parameters);

  /// Joins trusted text and [Sql] fragments at complete lexical boundaries.
  /// A newline separates parts so comments and tokens cannot span boundaries.
  /// Each nested fragment owns its parameter names; matching names never collide.
  factory Sql.parts(Iterable<Object> parts) => _PartsSql(parts);

  /// Quotes one identifier, including any literal dots in its name.
  factory Sql.identifier(String name) => _IdentifierSql(name);

  /// Quotes physical table and namespace separately. Namespaces require PostgreSQL.
  factory Sql.table(TableSchema table) => _TableSql(table);

  /// Selects exactly the current dialect; missing branches fail before execution.
  factory Sql.dialects(Map<SqlDialect, Sql> variants) => _DialectSql(variants);

  /// A single bound value for use in lists or other composed SQL.
  static Sql value(Object? value) =>
      Sql(':value', parameters: {'value': value});

  /// Joins fragments using trusted SQL syntax. An empty collection is empty SQL;
  /// callers must choose their own empty-list semantics for `IN` clauses.
  static Sql join(Iterable<Sql> parts, {String separator = ', '}) => Sql.parts([
    for (final (index, part) in parts.indexed) ...[
      if (index > 0) separator,
      part,
    ],
  ]);

  void _append(_SqlSource source);

  /// Compiles once for the current capabilities without acquiring a connection.
  /// Accepts one trailing semicolon. Parameter limits use actual protocol slots.
  SqlCommand compile(Capabilities capabilities) {
    final writer = SqlWriter(
      capabilities.dialect,
      {},
      exactDecimal: capabilities.exactDecimal,
      temporal: capabilities.temporal,
    );
    final source = _SqlSource(writer);
    _append(source);
    final parsed = scanSql(source.text.toString(), capabilities.dialect);
    final slots = <String, String>{};
    final text = parsed.parts.map((part) {
      if (part is String) return part;
      final name = (part as SqlSlot).name;
      return slots.putIfAbsent(name, () {
        final value = source.parameters[name];
        if (value is SqlValue<Object?>) {
          SqlNode node = ParameterNode(value._encoded, sqlType: value._storage);
          if (value._storage == 'decimal') node = DecimalNode(node);
          if ({
            'date',
            'time',
            'local_datetime',
            'instant',
          }.contains(value._storage)) {
            node = TemporalNode(node, value._storage);
          }
          return node.write(writer);
        }
        return writer.parameter(value);
      });
    }).join();
    final command = writer.finish(text);
    if (command.parameters.length > capabilities.maxParameters) {
      throw const OrmException(
        'QUERY.PARAMETERS',
        'SQL exceeds the parameter limit.',
      );
    }
    return command;
  }

  /// Attaches an optional result contract; no SQL is rewritten or executed.
  SqlQuery<R> returns<R>(ResultShape<R> result) => SqlQuery(this, result);
}

final class _SqlSource {
  final SqlWriter writer;
  final text = StringBuffer();
  final parameters = <String, Object?>{};
  _SqlSource(this.writer);
}

final class _TextSql extends Sql {
  final String text;
  final Map<String, Object?> parameters;
  final _parsed = <SqlDialect, SqlText>{};
  _TextSql(this.text, Map<String, Object?> parameters)
    : parameters = Map.unmodifiable({
        for (final entry in parameters.entries)
          entry.key: switch (entry.value) {
            SqlValue<Object?> value => value,
            SqlJson value => SqlValue(value, Codecs.jsonDocument),
            final value => _snapshot(value),
          },
      }),
      super._();

  @override
  void _append(_SqlSource source) {
    final parsed = _parsed.putIfAbsent(
      source.writer.dialect,
      () => scanSql(text, source.writer.dialect, fragment: true),
    );
    if (parsed.parameters.length != parameters.length ||
        !parsed.parameters.every(parameters.containsKey)) {
      throw const OrmException(
        'SQL.PARAMETERS',
        'SQL parameter names do not match the supplied values.',
      );
    }
    final names = <String, String>{};
    for (final part in parsed.parts) {
      if (part is String) {
        source.text.write(part);
      } else {
        final local = (part as SqlSlot).name;
        final name = names.putIfAbsent(local, () {
          final name = '_orm_${source.parameters.length}';
          source.parameters[name] = parameters[local];
          return name;
        });
        source.text.write(':$name');
      }
    }
  }
}

final class _PartsSql extends Sql {
  final List<Sql> parts;
  _PartsSql(Iterable<Object> parts)
    : parts = List.unmodifiable(
        parts.map(
          (part) => switch (part) {
            String text => Sql(text),
            Sql sql => sql,
            _ => throw ArgumentError('SQL parts must be trusted text or Sql.'),
          },
        ),
      ),
      super._();
  @override
  void _append(_SqlSource source) {
    for (final (index, part) in parts.indexed) {
      if (index != 0) source.text.writeln();
      part._append(source);
    }
  }
}

final class _IdentifierSql extends Sql {
  final String name;
  _IdentifierSql(this.name) : super._() {
    if (name.isEmpty || name.contains('\u0000')) {
      throw ArgumentError.value(name, 'name', 'Invalid SQL identifier');
    }
  }
  @override
  void _append(_SqlSource source) =>
      source.text.write(source.writer.quote(name));
}

final class _TableSql extends Sql {
  final TableSchema table;
  const _TableSql(this.table) : super._();
  @override
  void _append(_SqlSource source) =>
      source.text.write(source.writer.table(table));
}

final class _DialectSql extends Sql {
  final Map<SqlDialect, Sql> variants;
  _DialectSql(Map<SqlDialect, Sql> variants)
    : variants = Map.unmodifiable(variants),
      super._();
  @override
  void _append(_SqlSource source) {
    final variant = variants[source.writer.dialect];
    if (variant == null) {
      throw const OrmException(
        'QUERY.DIALECT',
        'No SQL was supplied for this database engine.',
      );
    }
    variant._append(source);
  }
}

/// A reusable SQL statement and typed result contract, independent of a database.
final class SqlQuery<R> {
  /// SQL text, parameter values and explicit dialect variants.
  final Sql sql;

  /// Required labels and the decoder for each actual result row.
  final ResultShape<R> result;

  /// Captures a result description without querying or binding a connection.
  const SqlQuery(this.sql, this.result);
}
