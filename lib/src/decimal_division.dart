part of '../orm.dart';

/// A null divisor denotes rounding one value. Operands are evaluated once.
final class _DecimalRatio(
  final _Node numerator,
  final _Node? divisor,
  final int scale,
  final DecimalRounding rounding,
) extends _Node {
  @override
  String writeSql(_Writer w) {
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
