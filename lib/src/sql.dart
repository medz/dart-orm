part of '../sql.dart';

sealed class _Node {
  const _Node();
  String write(_Writer w) => w.project?.call(this) ?? writeSql(w);
  String writeSql(_Writer w);
}

_Node _unwrapStorage(_Node node) => switch (node) {
  _DecimalNode(:final child) || _TemporalNode(:final child) => child,
  _ => node,
};

final class _ColumnNode(final TableRef table, final String name) extends _Node {
  @override
  String writeSql(_Writer w) {
    final alias = w.aliases[table];
    if (alias == null) {
      throw const OrmException(
        'QUERY.SCOPE',
        'Column belongs to another query.',
      );
    }
    if (w.mysql && alias == 'excluded') return 'VALUES(${w.quote(name)})';
    return w.unqualified || w.unqualifiedTable == table
        ? w.quote(name)
        : '${w.quote(alias)}.${w.quote(name)}';
  }
}

final class _Parameter(
  final Object? value, {
  final String? sqlType,
  final String? storageType,
}) extends _Node {
  @override
  String writeSql(_Writer w) {
    final parameter = w.parameter(value, storageType: storageType ?? sqlType);
    if (w.mysql && (storageType ?? sqlType) == 'json') {
      return w.dialect == SqlDialect.mysql
          ? 'CAST($parameter AS JSON)'
          : "JSON_EXTRACT($parameter, '\$')";
    }
    if (w.mysql &&
        {'decimal', 'bigint'}.contains(storageType ?? sqlType) &&
        value != null) {
      final decimal = Decimal.parse(value as String);
      final text = decimal.toString();
      final digits = text.replaceAll('-', '').split('.');
      final scale = digits.length == 2 ? digits[1].length : 0;
      final precision = digits[0].length + scale;
      if (precision > 65 || scale > 30) {
        throw const OrmException(
          'CAPABILITY.DECIMAL',
          'MySQL/MariaDB SQL decimals require at most 65 digits and scale 30.',
        );
      }
      return 'CAST($parameter AS DECIMAL(65,$scale))';
    }
    // A standalone SELECT parameter has no column context in PostgreSQL and
    // otherwise resolves to text, including inside a UNION operand.
    if (sqlType == null || w.dialect != SqlDialect.postgres) return parameter;
    final type = switch (sqlType) {
      'integer' => 'BIGINT',
      'bigint' || 'decimal' => 'NUMERIC',
      'text' => 'TEXT',
      'real' => 'DOUBLE PRECISION',
      'boolean' => 'BOOLEAN',
      'timestamp' || 'instant' => 'TIMESTAMPTZ',
      'date' => 'DATE',
      'time' => 'TIME WITHOUT TIME ZONE',
      'local_datetime' => 'TIMESTAMP WITHOUT TIME ZONE',
      'json' => 'JSONB',
      'blob' => 'BYTEA',
      _ => throw OrmException(
        'QUERY.PARAMETER_TYPE',
        'No PostgreSQL parameter type for $sqlType.',
      ),
    };
    return 'CAST($parameter AS $type)';
  }
}

final class _Binary(final _Node left, final String op, final _Node right)
    extends _Node {
  @override
  String writeSql(_Writer w) => '(${left.write(w)} $op ${right.write(w)})';
}

final class _Unary(
  final String op,
  final _Node child, {
  final bool postfix = false,
}) extends _Node {
  @override
  String writeSql(_Writer w) =>
      postfix ? '(${child.write(w)} $op)' : '($op ${child.write(w)})';
}

final class _Function(
  final String name,
  final List<_Node> arguments, {
  final bool distinct = false,
  final bool decimal = false,
}) extends _Node {
  @override
  String writeSql(_Writer w) {
    if (decimal && w.mysql && name == 'SUM') {
      throw const OrmException(
        'CAPABILITY.DECIMAL_PRECISION',
        'MySQL/MariaDB decimal sums can silently saturate in subqueries; use explicit native SQL when its precision is acceptable.',
      );
    }
    return '${decimal && w.dialect == SqlDialect.sqlite ? 'orm_decimal_${name.toLowerCase()}_v1' : name}(${distinct ? 'DISTINCT ' : ''}'
        '${arguments.map((e) => e.write(w)).join(', ')})';
  }
}

final class _In(final _Node expression, final List<_Node> values)
    extends _Node {
  @override
  String writeSql(_Writer w) => values.isEmpty
      ? 'FALSE'
      : '(${expression.write(w)} IN (${values.map((v) => v.write(w)).join(', ')}))';
}

/// Trusted SQL fragments still bind embedded expressions as parameters or ASTs.
final class _Raw(final List<String> parts, final List<_Node> values)
    extends _Node {
  @override
  String writeSql(_Writer w) {
    if (w.reads?.includeRaw == true) w.reads!.opaque = true;
    final result = StringBuffer(parts.first);
    for (var i = 0; i < values.length; i++) {
      result
        ..write(values[i].write(w))
        ..write(parts[i + 1]);
    }
    return result.toString();
  }
}

final class _Writer {
  final SqlDialect dialect;
  final QueryContext? database;
  final Map<TableRef, String> aliases;
  final List<Object?> parameters = [];
  final Set<TableRef> leftJoins = {};
  final _ReadTables? reads;
  final bool exactDecimal;
  final bool temporal;
  bool unqualified = false;
  TableRef? unqualifiedTable;
  String? Function(_Node)? project;
  _AverageInputs? averageInputs;
  _Writer(
    this.dialect,
    this.aliases, {
    this.database,
    this.reads,
    this.exactDecimal = false,
    this.temporal = false,
  });
  bool get mysql =>
      dialect == SqlDialect.mysql || dialect == SqlDialect.mariadb;
  String quote(String name) {
    _checkSqlText(name);
    return mysql
        ? '`${name.replaceAll('`', '``')}`'
        : '"${name.replaceAll('"', '""')}"';
  }

  String parameter(Object? value, {String? storageType}) {
    // Codec storage, not string pattern guessing, determines temporal binding.
    if (mysql && value is String && storageType == 'instant') {
      final instant = Codecs.dateTime.decode(value).toUtc();
      if (instant.year < 1000 || instant.year > 9999) {
        throw const OrmException(
          'CAPABILITY.TEMPORAL',
          'MySQL timestamps require years 1000 through 9999.',
        );
      }
      value = value.substring(0, value.length - 3);
    }
    parameters.add(switch ((dialect, value)) {
      (SqlDialect.sqlite, bool v) => v ? 1 : 0,
      (SqlDialect.sqlite, DateTime v) => v.toUtc().toIso8601String(),
      _ => value,
    });
    return dialect == SqlDialect.postgres
        ? '\$${parameters.length}'
        : mysql
        ? '\u0001${parameters.length}\u0002'
        : '?${parameters.length}';
  }

  SqlCommand finish(String sql) {
    SqlCommand checked(String text, List<Object?> values) {
      if (database != null &&
          values.length > database!.capabilities.maxParameters) {
        throw const OrmException(
          'QUERY.PARAMETERS',
          'SQL exceeds the parameter limit.',
        );
      }
      return SqlCommand(text, values);
    }

    if (!mysql) return checked(sql, parameters);
    // Construction may render ORDER BY before WHERE, and window staging may
    // reuse a fragment. Positional protocols bind in final SQL occurrence order.
    final ordered = <Object?>[];
    final text = sql.replaceAllMapped(RegExp('\u0001([0-9]+)\u0002'), (match) {
      ordered.add(parameters[int.parse(match[1]!) - 1]);
      return '?';
    });
    return checked(text, ordered);
  }
}

class Expr<T> extends Selection<T> {
  final _Node _node;
  final Codec<T> codec;
  Expr._(_Node node, this.codec)
    : _node = switch (codec.sqlType) {
        'decimal' when node is! _DecimalNode => _DecimalNode(node),
        'date' || 'time' || 'local_datetime' || 'instant'
            when node is! _TemporalNode =>
          _TemporalNode(node, codec.sqlType),
        _ => node,
      };

  Expr<bool?> eq(T value) => value == null
      ? Expr._(
          _Unary('IS NULL', _node, postfix: true),
          Codecs.boolean.nullable(),
        )
      : _compare(
          '=',
          _Parameter(codec.encode(value), storageType: codec.sqlType),
        );
  Expr<bool?> ne(T value) => value == null
      ? Expr._(
          _Unary('IS NOT NULL', _node, postfix: true),
          Codecs.boolean.nullable(),
        )
      : _compare(
          '<>',
          _Parameter(codec.encode(value), storageType: codec.sqlType),
        );
  Expr<bool?> equals(Expr<T> other) => _compare('=', other._node);
  Expr<bool?> gt(T value) => _compare(
    '>',
    _Parameter(codec.encode(value), storageType: codec.sqlType),
  );
  Expr<bool?> gte(T value) => _compare(
    '>=',
    _Parameter(codec.encode(value), storageType: codec.sqlType),
  );
  Expr<bool?> lt(T value) => _compare(
    '<',
    _Parameter(codec.encode(value), storageType: codec.sqlType),
  );
  Expr<bool?> lte(T value) => _compare(
    '<=',
    _Parameter(codec.encode(value), storageType: codec.sqlType),
  );
  Expr<bool?> _compare(String op, _Node right) =>
      Expr._(_Binary(_node, op, right), Codecs.boolean.nullable());
  Expr<bool> isNull() =>
      Expr._(_Unary('IS NULL', _node, postfix: true), Codecs.boolean);
  Expr<bool> isNotNull() =>
      Expr._(_Unary('IS NOT NULL', _node, postfix: true), Codecs.boolean);
  Expr<bool?> isIn(Iterable<T> values) => Expr._(
    _In(_node, [
      for (final value in values)
        _Parameter(codec.encode(value), storageType: codec.sqlType),
    ]),
    Codecs.boolean.nullable(),
  );
  Expr<bool?> isInQuery<F extends Fields>(Query<T, F> query) {
    if (query._selection is! Expr<T>) {
      throw const OrmException(
        'QUERY.SCALAR',
        'IN subqueries select one SQL expression.',
      );
    }
    return Expr._(
      _Binary(_node, 'IN', _Subquery(query)),
      Codecs.boolean.nullable(),
    );
  }

  Expr<T> over({
    List<Expr<Object?>> partitionBy = const [],
    List<OrderTerm> orderBy = const [],
    WindowFrame? frame,
  }) {
    final function = _unwrapStorage(_node);
    if ((function is! _Function && function is! _DecimalAverage) ||
        !_aggregate(function)) {
      throw const OrmException(
        'QUERY.WINDOW',
        'over() applies to an aggregate expression.',
      );
    }
    if ([
      ...partitionBy.map((e) => e._node),
      ...orderBy.map((o) => o.expression._node),
    ].any(_window)) {
      throw const OrmException(
        'QUERY.WINDOW',
        'Window partition/order expressions cannot contain another window.',
      );
    }
    return Expr._(
      _WindowNode(
        function,
        List.unmodifiable(partitionBy),
        List.unmodifiable(orderBy),
        frame,
      ),
      codec,
    );
  }

  OrderTerm asc({NullOrder? nulls}) => OrderTerm._(this, false, nulls);
  OrderTerm desc({NullOrder? nulls}) => OrderTerm._(this, true, nulls);
  CursorTerm cursor(T value, {bool descending = false, NullOrder? nulls}) =>
      CursorTerm._(OrderTerm._(this, descending, nulls), codec.encode(value));
  Expr<int> count({bool distinct = false}) =>
      Expr._(_Function('COUNT', [_node], distinct: distinct), Codecs.integer);
  Expr<T?> min() => Expr._(_Function('MIN', [_node]), codec.nullable());
  Expr<T?> max() => Expr._(_Function('MAX', [_node]), codec.nullable());
  @override
  _Decoder<T> _bind(_SelectionPlan plan) {
    plan.require(this);
    final index = plan.column(this);
    return (row) => codec.decode(row[index]);
  }
}

Expr<T> value<T>(T value, Codec<T> codec) =>
    Expr._(_Parameter(codec.encode(value), sqlType: codec.sqlType), codec);

/// [parts] are trusted SQL, [values] are expressions. Never put user input in parts.
Expr<T> sql<T>(List<String> parts, List<Expr<Object?>> values, Codec<T> codec) {
  if (parts.length != values.length + 1) {
    throw ArgumentError('SQL needs one more text part than expression.');
  }
  for (final part in parts) {
    _checkSqlText(part);
  }
  return Expr._(_Raw(List.of(parts), [for (final v in values) v._node]), codec);
}

void _checkSqlText(String text) {
  if (text.contains('\u0001') || text.contains('\u0002')) {
    throw const OrmException(
      'SQL.TEXT',
      'SQL text contains a reserved control character.',
    );
  }
}

extension Predicate on Expr<bool?> {
  Expr<bool?> and(Expr<bool?> other) =>
      Expr._(_Binary(_node, 'AND', other._node), Codecs.boolean.nullable());
  Expr<bool?> or(Expr<bool?> other) =>
      Expr._(_Binary(_node, 'OR', other._node), Codecs.boolean.nullable());
  Expr<bool?> not() => Expr._(_Unary('NOT', _node), Codecs.boolean.nullable());
}

extension TextExpression on Expr<String> {
  Expr<bool?> like(String pattern) => _compare('LIKE', _Parameter(pattern));
  Expr<String> lower() => Expr._(_Function('LOWER', [_node]), Codecs.text);
  Expr<String> upper() => Expr._(_Function('UPPER', [_node]), Codecs.text);
}

extension NumericExpression<T extends num> on Expr<T> {
  Expr<T> plus(T n) => Expr._(
    _Binary(
      _node,
      '+',
      _Parameter(codec.encode(n), storageType: codec.sqlType),
    ),
    codec,
  );
  Expr<T> minus(T n) => Expr._(
    _Binary(
      _node,
      '-',
      _Parameter(codec.encode(n), storageType: codec.sqlType),
    ),
    codec,
  );
  Expr<T> times(T n) => Expr._(
    _Binary(
      _node,
      '*',
      _Parameter(codec.encode(n), storageType: codec.sqlType),
    ),
    codec,
  );
  Expr<T?> sum() => Expr._(_Function('SUM', [_node]), codec.nullable());
  Expr<double?> average() =>
      Expr._(_Function('AVG', [_node]), Codecs.real.nullable());
}

final class OrderTerm {
  final Expr<Object?> expression;
  final bool descending;
  final NullOrder? nulls;
  const OrderTerm._(this.expression, this.descending, [this.nulls]);
  String _write(_Writer writer) {
    final text = expression._node.write(writer);
    if (writer.mysql && nulls != null) {
      return '($text IS NULL) ${nulls == NullOrder.first ? 'DESC' : 'ASC'}, '
          '${expression._node.write(writer)} ${descending ? 'DESC' : 'ASC'}';
    }
    return '$text$_suffix';
  }

  String get _suffix =>
      ' ${descending ? 'DESC' : 'ASC'}'
      '${nulls == null ? '' : ' NULLS ${nulls!.name.toUpperCase()}'}';
}

String _projection(Expr<Object?> expression, _Writer writer) {
  final text = expression._node.write(writer);
  // Preserve JSON null separately from SQL NULL through native driver decoders.
  return writer.mysql && expression.codec.sqlType == 'json'
      ? 'CAST($text AS CHAR CHARACTER SET utf8mb4)'
      : text;
}
