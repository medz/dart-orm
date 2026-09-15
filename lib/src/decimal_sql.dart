part of '../orm.dart';

// Attach collation to every decimal expression, including computed projections,
// CTE references and UNION outputs. Native PostgreSQL NUMERIC needs no wrapper.
final class _DecimalNode(final _Node child) extends _Node {
  @override
  String writeSql(_Writer w) {
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

final class _DecimalCast(
  final _Node child,
  final int precision,
  final int scale,
) extends _Node {
  @override
  String writeSql(_Writer w) {
    Decimal._checkDigits(precision, scale);
    if (!w.exactDecimal) {
      throw const OrmException(
        'CAPABILITY.DECIMAL',
        'This driver does not provide exact decimal SQL.',
      );
    }
    final expression = child.write(w);
    return w.dialect == SqlDialect.postgres
        ? 'CAST($expression AS NUMERIC($precision,$scale))'
        : 'orm_decimal_cast_v1($expression, $precision, $scale)';
  }
}

final class _DecimalArithmetic(
  final _Node left,
  final String op,
  final _Node right,
) extends _Node {
  @override
  String writeSql(_Writer w) {
    final a = left.write(w), b = right.write(w);
    if (w.dialect == SqlDialect.postgres) return '($a $op $b)';
    final name = switch (op) {
      '+' => 'add',
      '-' => 'sub',
      '*' => 'mul',
      _ => throw StateError('Invalid decimal operation'),
    };
    return 'orm_decimal_${name}_v1($a, $b)';
  }
}

extension DecimalExpression<T extends Decimal?> on Expr<T> {
  /// Averages non-null inputs, rounding once at the requested result scale.
  /// Empty/all-null input returns null; the default rejects lost digits.
  Expr<Decimal?> average({
    required int scale,
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    Decimal._checkScale(scale);
    if (_window(_node)) {
      throw const OrmException(
        'QUERY.WINDOW',
        'Project a window result through a CTE before averaging it.',
      );
    }
    return Expr._(
      _DecimalAverage(_node, scale, rounding),
      Codecs.decimal.nullable(),
    );
  }

  /// Rounds in SQL; [DecimalRounding.exact] rejects any lost nonzero digits.
  Expr<T> rounded(
    int scale, {
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    Decimal._checkScale(scale);
    return Expr._(_DecimalRatio(_node, null, scale, rounding), codec);
  }

  /// Divides in SQL to an explicit scale without a floating-point intermediate.
  Expr<T> divide(
    Decimal divisor, {
    required int scale,
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    Decimal._checkScale(scale);
    return Expr._(
      _DecimalRatio(
        _node,
        value(divisor, Codecs.decimal)._node,
        scale,
        rounding,
      ),
      codec,
    );
  }

  /// Divides two SQL expressions. A null operand produces null.
  Expr<Decimal?> divideExpression(
    Expr<Decimal?> divisor, {
    required int scale,
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    Decimal._checkScale(scale);
    return Expr._(
      _DecimalRatio(_node, divisor._node, scale, rounding),
      Codecs.decimal.nullable(),
    );
  }

  Expr<T> constrained(int precision, int scale) {
    Decimal._checkDigits(precision, scale);
    return Expr._(_DecimalCast(_node, precision, scale), codec);
  }

  Expr<T> plus(Decimal n) => _arithmetic('+', value(n, Codecs.decimal));
  Expr<T> minus(Decimal n) => _arithmetic('-', value(n, Codecs.decimal));
  Expr<T> times(Decimal n) => _arithmetic('*', value(n, Codecs.decimal));
  Expr<Decimal?> plusExpression(Expr<Decimal?> other) => _binary('+', other);
  Expr<Decimal?> minusExpression(Expr<Decimal?> other) => _binary('-', other);
  Expr<Decimal?> timesExpression(Expr<Decimal?> other) => _binary('*', other);
  Expr<T> _arithmetic(String op, Expr<Decimal> other) =>
      Expr._(_DecimalArithmetic(_node, op, other._node), codec);
  Expr<Decimal?> _binary(String op, Expr<Decimal?> other) => Expr._(
    _DecimalArithmetic(_node, op, other._node),
    Codecs.decimal.nullable(),
  );
  Expr<Decimal?> sum({bool distinct = false}) => Expr._(
    _Function('SUM', [_node], decimal: true, distinct: distinct),
    Codecs.decimal.nullable(),
  );
}
