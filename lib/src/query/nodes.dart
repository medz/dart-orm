import 'package:meta/meta.dart';

import '../../driver.dart';
import '../../schema_model.dart' show TableSchema;
import 'context.dart';
import 'expression.dart';
import 'joins.dart';
import 'query.dart';
import 'reads.dart';
import 'relation.dart';
import 'table.dart';

/// @nodoc
@internal
sealed class SqlNode {
  const SqlNode();
  String write(SqlWriter w) => w.project?.call(this) ?? writeSql(w);
  String writeSql(SqlWriter w);
}

/// @nodoc
@internal
SqlNode unwrapStorage(SqlNode node) => switch (node) {
  DecimalNode(:final child) || TemporalNode(:final child) => child,
  _ => node,
};

/// @nodoc
@internal
final class ColumnNode(final TableRef table, final String name)
    extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
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

/// @nodoc
@internal
final class ParameterNode(
  final Object? value, {
  final String? sqlType,
  final String? storageType,
}) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
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

/// @nodoc
@internal
final class BinaryNode(final SqlNode left, final String op, final SqlNode right)
    extends SqlNode {
  @override
  String writeSql(SqlWriter w) => '(${left.write(w)} $op ${right.write(w)})';
}

/// @nodoc
@internal
final class UnaryNode(
  final String op,
  final SqlNode child, {
  final bool postfix = false,
}) extends SqlNode {
  @override
  String writeSql(SqlWriter w) =>
      postfix ? '(${child.write(w)} $op)' : '($op ${child.write(w)})';
}

/// @nodoc
@internal
final class FunctionNode(
  final String name,
  final List<SqlNode> arguments, {
  final bool distinct = false,
  final bool decimal = false,
}) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
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

/// @nodoc
@internal
final class InNode(final SqlNode expression, final List<SqlNode> values)
    extends SqlNode {
  @override
  String writeSql(SqlWriter w) => values.isEmpty
      ? 'FALSE'
      : '(${expression.write(w)} IN (${values.map((v) => v.write(w)).join(', ')}))';
}

/// @nodoc
@internal
/// Trusted SQL fragments still bind embedded expressions as parameters or ASTs.
final class RawNode(final List<String> parts, final List<SqlNode> values)
    extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
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

/// @nodoc
@internal
final class SqlWriter {
  final SqlDialect dialect;
  final QueryContext? database;
  final Map<TableRef, String> aliases;
  final List<Object?> parameters = [];
  final Set<TableRef> leftJoins = {};
  final Set<TableRef> relationSubqueries = {};
  final ReadTables? reads;
  final bool exactDecimal;
  final bool temporal;
  bool unqualified = false;
  TableRef? unqualifiedTable;
  String? Function(SqlNode)? project;
  AverageInputs? averageInputs;
  SqlWriter(
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
    checkSqlText(name);
    return mysql
        ? '`${name.replaceAll('`', '``')}`'
        : '"${name.replaceAll('"', '""')}"';
  }

  String table(TableSchema table) {
    final namespace = table.namespace;
    if (namespace == null) return quote(table.name);
    if (dialect != SqlDialect.postgres) {
      throw const OrmException(
        'SCHEMA.NAMESPACE',
        'Database schemas require PostgreSQL.',
      );
    }
    return '${quote(namespace)}.${quote(table.name)}';
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

/// @nodoc
@internal
void checkSqlText(String text) {
  if (text.contains('\u0001') || text.contains('\u0002')) {
    throw const OrmException(
      'SQL.TEXT',
      'SQL text contains a reserved control character.',
    );
  }
}

/// @nodoc
@internal
final class RelationSubqueryNode(
  final Relation<Object?, Fields> relation,
  final bool count,
) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    if (relation.queryState.limit != null ||
        relation.queryState.offset != null) {
      throw const OrmException(
        'RELATION.AGGREGATE',
        'Apply relation count/any/none/every before pagination.',
      );
    }
    if (relation.queryState.predicate case final predicate?) {
      if (aggregate(predicate.expressionNode) ||
          window(predicate.expressionNode)) {
        throw const OrmException(
          'QUERY.AGGREGATE',
          'Relationship predicates cannot contain aggregate or window functions. Use a subquery.',
        );
      }
    }
    final source = relation.queryState.source;
    if (!w.relationSubqueries.add(source)) {
      throw const OrmException(
        'QUERY.ALIAS',
        'A nested relationship needs a fresh source occurrence.',
      );
    }
    w.reads?.tables.add(source.schema);
    final previous = w.aliases[source];
    final alias = 't${w.aliases.length}';
    w.aliases[source] = alias;
    try {
      final predicates = [
        for (var i = 0; i < relation.childFields.length; i++)
          BinaryNode(
            relation.childFields[i].expressionNode,
            '=',
            relation.parentFields[i].expressionNode,
          ).write(w),
        if (relation.queryState.predicate case final p?)
          p.expressionNode.write(w),
      ];
      final query =
          'SELECT ${count ? 'COUNT(*)' : '1'} FROM ${w.table(source.schema)} AS ${w.quote(alias)} WHERE ${predicates.join(' AND ')}';
      return count ? '($query)' : 'EXISTS ($query)';
    } finally {
      w.relationSubqueries.remove(source);
      if (previous == null) {
        w.aliases.remove(source);
      } else {
        w.aliases[source] = previous;
      }
    }
  }
}

// Row-value IN avoids a deep OR tree for large composite-key batches.
/// @nodoc
@internal
final class RelationKeys(
  final List<ReadField<Object?>> columns,
  final List<RelationKey> keys,
) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    // Keys stay comparable storage values while grouping. Restore floating SQL
    // intent only when binding them (JS cannot identify an integral double).
    Object? parameter(int index, Object? value) =>
        value != null && columns[index].codec.sqlType == 'real'
        ? Codecs.real.encode(Codecs.real.decode(value))
        : value;
    if (columns.length == 1) {
      return InNode(columns.single.expressionNode, [
        for (final key in keys)
          ParameterNode(
            parameter(0, key.values.single),
            storageType: columns.single.codec.sqlType,
          ),
      ]).write(w);
    }
    return '(${columns.map((c) => c.expressionNode.write(w)).join(', ')}) IN (${w.dialect == SqlDialect.sqlite ? 'VALUES ' : ''}'
        '${keys.map((key) => '(${[for (var i = 0; i < key.values.length; i++) ParameterNode(parameter(i, key.values[i]), storageType: columns[i].codec.sqlType).write(w)].join(', ')})').join(', ')})';
  }
}

/// @nodoc
@internal
final class PresenceNode(final TableAlias<Object?, Fields> alias)
    extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    if (!w.leftJoins.contains(alias.fields.table)) {
      throw const OrmException(
        'QUERY.OUTER_JOIN',
        'Optional projections require this alias to be left joined.',
      );
    }
    return '${w.quote(w.aliases[alias.fields.table]!)}.${w.quote(alias.presenceMarker)}';
  }
}

/// @nodoc
@internal
final class SubqueryNode(
  final Query<Object?, Fields> query, {
  final bool exists = false,
}) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    final (plan, _) = query.planQuery();
    if (plan.relations.isNotEmpty) {
      throw const OrmException(
        'QUERY.SUBQUERY',
        'SQL subqueries cannot include batch-loaded relations.',
      );
    }
    if (w.dialect != query.database.dialect) {
      throw const OrmException(
        'QUERY.DIALECT',
        'Subqueries must use the enclosing SQL dialect.',
      );
    }
    return '${exists ? 'EXISTS ' : ''}(${query.writeQuery(w, plan)})';
  }
}

/// @nodoc
@internal
final class WindowNode(
  final SqlNode function,
  final List<Expr<Object?>> partition,
  final List<OrderTerm> order,
  final WindowFrame? frame,
) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    if (function case final DecimalAverage average) {
      return average.writeAverage(w, window: this);
    }
    final clauses = <String>[];
    if (partition.isNotEmpty) {
      clauses.add(
        'PARTITION BY ${partition.map((e) => e.expressionNode.write(w)).join(', ')}',
      );
    }
    if (order.isNotEmpty) {
      clauses.add('ORDER BY ${order.map((o) => o.writeQuery(w)).join(', ')}');
    }
    if (frame != null) {
      clauses.add(switch (frame!) {
        WindowFrame.rowsToCurrent =>
          'ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW',
        WindowFrame.rowsAll =>
          'ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING',
        WindowFrame.rangeToCurrent =>
          'RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW',
      });
    }
    return '${function.writeSql(w)} OVER (${clauses.join(' ')})';
  }
}

/// @nodoc
@internal
final class TemporalNode(final SqlNode child, final String kind)
    extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    if (!w.temporal) {
      throw const OrmException(
        'CAPABILITY.TEMPORAL',
        'This driver does not provide temporal values.',
      );
    }
    final text = child.write(w);
    return w.dialect == SqlDialect.sqlite
        ? '($text COLLATE "orm_${kind}_v1")'
        : text;
  }
}

/// @nodoc
@internal
final class TemporalCast(
  final SqlNode child,
  final String kind,
  final int digits, {
  final bool columnAssignment = false,
}) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    checkTemporalPrecision(digits);
    if (!w.temporal) {
      throw const OrmException(
        'CAPABILITY.TEMPORAL',
        'This driver does not provide temporal values.',
      );
    }
    final type = switch (kind) {
      'time' => 'TIME($digits) WITHOUT TIME ZONE',
      'local_datetime' => 'TIMESTAMP($digits) WITHOUT TIME ZONE',
      'instant' => 'TIMESTAMPTZ($digits)',
      _ => throw ArgumentError('Temporal precision requires temporal storage.'),
    };
    final sql = child.write(w);
    if (w.mysql) {
      // Storage coercion follows the declared database column. Expression
      // rounding has a stronger cross-engine contract and stays explicit.
      if (columnAssignment) return sql;
      throw const OrmException(
        'CAPABILITY.TEMPORAL_PRECISION',
        'MySQL/MariaDB temporal rounding differs; declare column precision or use explicit SQL.',
      );
    }
    return w.dialect == SqlDialect.postgres
        ? 'CAST($sql AS $type)'
        : "orm_temporal_cast_v1($sql, '$kind', $digits)";
  }
}

// Attach collation to every decimal expression, including computed projections,
// CTE references and UNION outputs. Native PostgreSQL NUMERIC needs no wrapper.
/// @nodoc
@internal
final class DecimalNode(final SqlNode child) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    if (!w.exactDecimal) {
      throw const OrmException(
        'CAPABILITY.DECIMAL',
        'This driver does not provide exact decimal SQL.',
      );
    }
    final sql = child.write(w);
    return w.dialect == SqlDialect.sqlite
        ? '($sql COLLATE "orm_decimal_v1")'
        : sql;
  }
}

/// @nodoc
@internal
final class DecimalCast(
  final SqlNode child,
  final int precision,
  final int scale, {
  final bool columnAssignment = false,
}) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    Decimal.validateDigits(precision, scale);
    if (!w.exactDecimal) {
      throw const OrmException(
        'CAPABILITY.DECIMAL',
        'This driver does not provide exact decimal SQL.',
      );
    }
    final expression = child.write(w);
    if (w.mysql) {
      if (precision > 65 || scale < 0 || scale > 30 || scale > precision) {
        throw const OrmException(
          'CAPABILITY.DECIMAL',
          'MySQL/MariaDB decimals require precision 1–65 and scale 0–min(precision, 30).',
        );
      }
      if (columnAssignment) return expression;
      throw const OrmException(
        'CAPABILITY.DECIMAL_PRECISION',
        'MySQL/MariaDB decimal casts may clamp overflow; use explicit native SQL when its precision is acceptable.',
      );
    }
    return w.dialect == SqlDialect.postgres
        ? 'CAST($expression AS NUMERIC($precision,$scale))'
        : 'orm_decimal_cast_v1($expression, $precision, $scale)';
  }
}

/// @nodoc
@internal
final class DecimalArithmetic(
  final SqlNode left,
  final String op,
  final SqlNode right,
) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    if (w.mysql) {
      throw const OrmException(
        'CAPABILITY.DECIMAL_PRECISION',
        'MySQL/MariaDB arithmetic may silently truncate decimal digits; use explicit native SQL when its precision is acceptable.',
      );
    }
    final a = left.write(w), b = right.write(w);
    if (w.dialect != SqlDialect.sqlite) return '($a $op $b)';
    final name = switch (op) {
      '+' => 'add',
      '-' => 'sub',
      '*' => 'mul',
      _ => throw StateError('Invalid decimal operation'),
    };
    return 'orm_decimal_${name}_v1($a, $b)';
  }
}

/// @nodoc
@internal
/// A null divisor denotes rounding one value. Operands are evaluated once.
final class DecimalRatio(
  final SqlNode numerator,
  final SqlNode? divisor,
  final int scale,
  final DecimalRounding rounding,
) extends SqlNode {
  @override
  String writeSql(SqlWriter w) {
    if (w.mysql) {
      throw const OrmException(
        'CAPABILITY.DECIMAL_ROUNDING',
        'Exact SQL division and rounding are not implemented for MySQL/MariaDB; use an explicit DECIMAL expression.',
      );
    }
    final a = numerator.write(w), b = divisor?.write(w);
    if (w.dialect == SqlDialect.sqlite) {
      return b == null
          ? 'orm_decimal_round_v1($a, $scale, ${rounding.index})'
          : 'orm_decimal_div_v1($a, $b, $scale, ${rounding.index})';
    }
    // MATERIALIZED keeps volatile expressions and correlated operands from
    // being reevaluated by the quotient, remainder and rounding calculations.
    final prefix =
        '''
WITH orm_decimal_args(a, b) AS MATERIALIZED (
  VALUES (CAST($a AS NUMERIC), CAST(${b ?? '1'} AS NUMERIC))
), orm_decimal_parts AS MATERIALIZED (
  SELECT abs(a) AS a, abs(b) AS b, sign(a) * sign(b) AS sgn,
         a IS NULL OR b IS NULL AS nil,
         div(abs(a), NULLIF(abs(b), 0)) AS q
  FROM orm_decimal_args
), orm_decimal_remainder AS MATERIALIZED (
  SELECT *, a - q * b AS r FROM orm_decimal_parts
)''';
    return _DecimalRoundSql(scale, rounding).write(prefix);
  }
}

// The input CTE exposes a nonnegative integer quotient q, remainder r < b,
// positive denominator b, result sign sgn and empty/null marker nil.
final class _DecimalRoundSql(final int scale, final DecimalRounding rounding) {
  String write(String prefix) =>
      scale >= 0 ? _positive(prefix) : _negative(prefix);

  String _positive(String prefix) {
    final factor = "NUMERIC '1e$scale'";
    final unit = "NUMERIC '1e-$scale'";
    final text = scale == 0
        ? 'q::text'
        : "q::text || '.' || lpad(f::text, $scale, '0')";
    final increment = _increment(
      nonzero: 'r <> 0',
      above: 'r > b - r',
      tie: 'r = b - r',
      odd: 'mod(${scale == 0 ? 'q' : 'f'}, 2) <> 0',
    );
    // Usually r*factor fits NUMERIC. For a huge remainder, split b=d*factor+e
    // instead. Then c=div(r,d) overestimates div(r*factor,b) by at most one:
    // the fallback implies d >= 10^(131072-2*scale) > factor^2. All products
    // below stay within the original denominator's magnitude or factor^2.
    return '''($prefix,
orm_decimal_scaled AS MATERIALIZED (
  SELECT *, length(trunc(r)::text) + $scale <= ${Decimal.maxIntegerDigits} AS simple
  FROM orm_decimal_remainder
), orm_decimal_split AS MATERIALIZED (
  SELECT *, CASE WHEN simple THEN r * $factor ELSE r END AS n,
         CASE WHEN simple THEN b ELSE div(b, $factor) END AS d,
         CASE WHEN simple THEN 0 ELSE mod(b, $factor) END AS e
  FROM orm_decimal_scaled
), orm_decimal_estimate AS MATERIALIZED (
  SELECT *, div(n, NULLIF(d, 0)) AS c FROM orm_decimal_split
), orm_decimal_correction AS MATERIALIZED (
  SELECT *, CASE WHEN simple THEN n - c * d
                 ELSE (n - c * d) * $factor - c * e END AS tail
  FROM orm_decimal_estimate
), orm_decimal_final AS (
  SELECT q, b, sgn, nil,
         CASE WHEN tail < 0 THEN c - 1 ELSE c END AS f,
         CASE WHEN tail < 0 THEN tail + b ELSE tail END AS r
  FROM orm_decimal_correction
)
SELECT CASE WHEN nil THEN NULL WHEN b = 0 THEN 1 / b
  ${_inexact('r <> 0')}
  ELSE sgn * (CAST($text AS NUMERIC) + CASE WHEN $increment THEN $unit ELSE 0 END)
END FROM orm_decimal_final)''';
  }

  String _negative(String prefix) {
    final places = -scale, half = "NUMERIC '5e${-scale - 1}'";
    final increment = _increment(
      nonzero: 'lost <> 0 OR r <> 0',
      above: 'lost > $half OR (lost = $half AND r <> 0)',
      tie: 'lost = $half AND r = 0',
      odd: 'mod(kept, 2) <> 0',
    );
    // Construct integer digits as text so even the outermost supported scale
    // (-131072) can return zero without first constructing an overflowing unit.
    return '''($prefix,
orm_decimal_integer AS MATERIALIZED (
  SELECT *, CAST(COALESCE(NULLIF(left(q::text, greatest(length(q::text) - $places, 0)), ''), '0') AS NUMERIC) AS kept
  FROM orm_decimal_remainder
), orm_decimal_truncated AS MATERIALIZED (
  SELECT *, CAST(kept::text || repeat('0', $places) AS NUMERIC) AS truncated
  FROM orm_decimal_integer
), orm_decimal_final AS (
  SELECT *, q - truncated AS lost FROM orm_decimal_truncated
)
SELECT CASE WHEN nil THEN NULL WHEN b = 0 THEN 1 / b
  ${_inexact('lost <> 0 OR r <> 0')}
  ELSE sgn * CAST((kept + CASE WHEN $increment THEN 1 ELSE 0 END)::text || repeat('0', $places) AS NUMERIC)
END FROM orm_decimal_final)''';
  }

  String _inexact(String nonzero) => rounding == DecimalRounding.exact
      ? "WHEN $nonzero THEN CAST(q::text || '_decimal_rounding_required' AS NUMERIC)"
      : '';

  String _increment({
    required String nonzero,
    required String above,
    required String tie,
    required String odd,
  }) => switch (rounding) {
    DecimalRounding.exact || DecimalRounding.towardZero => 'FALSE',
    DecimalRounding.floor => 'sgn < 0 AND ($nonzero)',
    DecimalRounding.ceiling => 'sgn > 0 AND ($nonzero)',
    DecimalRounding.halfAwayFromZero => '($above) OR ($tie)',
    DecimalRounding.halfEven => '($above) OR (($tie) AND ($odd))',
  };
}

/// @nodoc
@internal
final class DecimalAverage(
  final SqlNode child,
  final int scale,
  final DecimalRounding rounding,
) extends SqlNode {
  @override
  String writeSql(SqlWriter w) => writeAverage(w);

  String writeAverage(SqlWriter w, {WindowNode? window}) {
    if (w.mysql) {
      throw const OrmException(
        'CAPABILITY.DECIMAL_ROUNDING',
        'Exact decimal averages are not supported on MySQL/MariaDB.',
      );
    }
    if (w.averageInputs == null) {
      throw const OrmException(
        'QUERY.AGGREGATE',
        'An average requires a SELECT query; use a scalar subquery in assignments.',
      );
    }
    if (w.dialect == SqlDialect.sqlite) {
      final function = FunctionNode('orm_decimal_avg_v1', [
        child,
        ParameterNode(scale),
        ParameterNode(rounding.index),
      ]);
      return (window == null
              ? function
              : WindowNode(
                  function,
                  window.partition,
                  window.order,
                  window.frame,
                ))
          .writeSql(w);
    }
    final input = AverageInput(child);
    final partition = [
      for (final e in window?.partition ?? <Expr<Object?>>[])
        Expr.internal(AverageInput(e.expressionNode), e.codec),
    ];
    final order = [
      for (final o in window?.order ?? <OrderTerm>[])
        OrderTerm.internal(
          Expr.internal(
            AverageInput(o.expression.expressionNode),
            o.expression.codec,
          ),
          o.descending,
          o.nulls,
        ),
    ];
    String aggregate(String name, SqlNode argument) {
      final function = FunctionNode(name, [argument]);
      return (window == null
              ? function
              : WindowNode(function, partition, order, window.frame))
          .write(w);
    }

    // B exceeds every possible COUNT (signed int64). Each SUM stays finite:
    // high has 20 fewer integer digits; low is bounded by COUNT*B. Native SUM
    // preserves its exact accumulator without holding an array of input rows.
    const base = "NUMERIC '1e20'";
    final high = aggregate('SUM', RawNode(['div(', ', $base)'], [input]));
    final low = aggregate('SUM', RawNode(['mod(', ', $base)'], [input]));
    final count = aggregate('COUNT', input);
    final prefix =
        '''
WITH orm_mean_args(h, l, n) AS MATERIALIZED (
  VALUES ($high, $low, CAST($count AS NUMERIC))
), orm_mean_high AS MATERIALIZED (
  SELECT *, div(h, NULLIF(n, 0)) AS qh, mod(h, NULLIF(n, 0)) AS rh
  FROM orm_mean_args
), orm_mean_tail AS MATERIALIZED (
  SELECT *, rh * $base + l AS t FROM orm_mean_high
), orm_mean_parts AS MATERIALIZED (
  SELECT n, qh * $base + div(t, NULLIF(n, 0)) AS q,
         mod(t, NULLIF(n, 0)) AS r FROM orm_mean_tail
), orm_mean_normal AS MATERIALIZED (
  SELECT n,
    CASE WHEN q > 0 AND r < 0 THEN q - 1 WHEN q < 0 AND r > 0 THEN q + 1 ELSE q END AS q,
    CASE WHEN q > 0 AND r < 0 THEN r + n WHEN q < 0 AND r > 0 THEN r - n ELSE r END AS r
  FROM orm_mean_parts
), orm_decimal_remainder AS MATERIALIZED (
  SELECT abs(q) AS q, abs(r) AS r, n AS b, n = 0 AS nil,
         CASE WHEN q = 0 THEN sign(r) ELSE sign(q) END AS sgn
  FROM orm_mean_normal
)''';
    return _DecimalRoundSql(scale, rounding).write(prefix);
  }
}

// Shared by the high/low/count aggregates (and by a window's frame expressions).
// Projection staging handles windows; ordinary aggregation uses a row lateral.
/// @nodoc
@internal
final class AverageInput(final SqlNode child) extends SqlNode {
  @override
  String writeSql(SqlWriter w) => w.averageInputs!.capture(this);
}

/// @nodoc
@internal
final class AverageInputs(final SqlWriter writer, final String anchor) {
  final List<String> joins = [];
  final Map<AverageInput, String> _references = {};
  String capture(AverageInput input) => _references.putIfAbsent(input, () {
    final name = writer.quote(
      '_orm_avg_${writer.aliases.length}_${joins.length}',
    );
    final saved = writer.project;
    writer.project = null;
    late String value;
    try {
      value = input.child.write(writer);
    } finally {
      writer.project = saved;
    }
    // The zero term keeps even a volatile, otherwise uncorrelated input tied
    // to each source row. OFFSET prevents flattening/repeated evaluation.
    joins.add(
      ' CROSS JOIN LATERAL (SELECT ($value) + CAST($anchor IS NULL AS INT) * NUMERIC \'0\' AS v OFFSET 0) AS $name',
    );
    return '$name.v';
  });
}
