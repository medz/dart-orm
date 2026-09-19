part of '../sql.dart';

final class _DecimalAverage(
  final _Node child,
  final int scale,
  final DecimalRounding rounding,
) extends _Node {
  @override
  String writeSql(_Writer w) => writeAverage(w);

  String writeAverage(_Writer w, {_WindowNode? window}) {
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
      final function = _Function('orm_decimal_avg_v1', [
        child,
        _Parameter(scale),
        _Parameter(rounding.index),
      ]);
      return (window == null
              ? function
              : _WindowNode(
                  function,
                  window.partition,
                  window.order,
                  window.frame,
                ))
          .writeSql(w);
    }
    final input = _AverageInput(child);
    final partition = [
      for (final e in window?.partition ?? <Expr<Object?>>[])
        Expr._(_AverageInput(e._node), e.codec),
    ];
    final order = [
      for (final o in window?.order ?? <OrderTerm>[])
        OrderTerm._(
          Expr._(_AverageInput(o.expression._node), o.expression.codec),
          o.descending,
          o.nulls,
        ),
    ];
    String aggregate(String name, _Node argument) {
      final function = _Function(name, [argument]);
      return (window == null
              ? function
              : _WindowNode(function, partition, order, window.frame))
          .write(w);
    }

    // B exceeds every possible COUNT (signed int64). Each SUM stays finite:
    // high has 20 fewer integer digits; low is bounded by COUNT*B. Native SUM
    // preserves its exact accumulator without holding an array of input rows.
    const base = "NUMERIC '1e20'";
    final high = aggregate('SUM', _Raw(['div(', ', $base)'], [input]));
    final low = aggregate('SUM', _Raw(['mod(', ', $base)'], [input]));
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
final class _AverageInput(final _Node child) extends _Node {
  @override
  String writeSql(_Writer w) => w.averageInputs!.capture(this);
}

final class _AverageInputs(final _Writer writer, final String anchor) {
  final List<String> joins = [];
  final Map<_AverageInput, String> _references = {};
  String capture(_AverageInput input) => _references.putIfAbsent(input, () {
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
