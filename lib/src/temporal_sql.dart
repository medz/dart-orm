part of '../sql.dart';

final class _TemporalNode(final _Node child, final String kind) extends _Node {
  @override
  String writeSql(_Writer w) {
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

void _checkTemporalPrecision(int digits) {
  if (digits < 0 || digits > 6) throw RangeError.range(digits, 0, 6, 'digits');
}

final class _TemporalCast(
  final _Node child,
  final String kind,
  final int digits, {
  final bool columnAssignment = false,
}) extends _Node {
  @override
  String writeSql(_Writer w) {
    _checkTemporalPrecision(digits);
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

extension TimeExpression<T extends LocalTime?> on Expr<T> {
  Expr<T> withPrecision(int digits) {
    _checkTemporalPrecision(digits);
    return Expr._(_TemporalCast(_node, 'time', digits), codec);
  }
}

extension LocalDateTimeExpression<T extends LocalDateTime?> on Expr<T> {
  Expr<T> withPrecision(int digits) {
    _checkTemporalPrecision(digits);
    return Expr._(_TemporalCast(_node, 'local_datetime', digits), codec);
  }
}

extension InstantExpression<T extends DateTime?> on Expr<T> {
  Expr<T> withPrecision(int digits) {
    _checkTemporalPrecision(digits);
    return Expr._(_TemporalCast(_node, 'instant', digits), codec);
  }
}
