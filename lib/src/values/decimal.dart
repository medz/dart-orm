import 'dart:math' as math;

/// Rounding is explicit; [exact] rejects a non-zero discarded remainder.
enum DecimalRounding {
  /// Rejects any non-zero discarded remainder.
  exact,

  /// Discards remaining digits without increasing magnitude.
  towardZero,

  /// Rounds toward negative infinity.
  floor,

  /// Rounds toward positive infinity.
  ceiling,

  /// Rounds to the nearest value, moving exact ties away from zero.
  halfAwayFromZero,

  /// Rounds to the nearest value, choosing an even final digit for exact ties.
  halfEven,
}

/// A finite base-ten value, independent of binary floating point.
///
/// Equal values have identical normalized coefficients and scales. The range
/// matches finite unconstrained PostgreSQL NUMERIC: at most 131072 integer
/// digits and 16383 fractional digits. This does not retain display precision.
final class Decimal implements Comparable<Decimal> {
  /// Maximum count of digits to the left of the decimal point.
  static const maxIntegerDigits = 131072;

  /// Maximum count of digits to the right of the decimal point.
  static const maxFractionDigits = 16383;

  /// The canonical normalized zero.
  static final zero = Decimal._(BigInt.zero, 0);

  /// Normalized integer significand, without trailing decimal zeroes.
  final BigInt coefficient;

  /// Decimal exponent divisor: the value equals coefficient × 10^(-scale).
  final int scale;
  const Decimal._(this.coefficient, this.scale);

  /// Creates coefficient × 10^(-scale), normalizing trailing zeroes.
  factory Decimal.fromBigInt(BigInt coefficient, {int scale = 0}) {
    if (coefficient == BigInt.zero) return zero;
    return Decimal._digits(
      coefficient.abs().toString(),
      coefficient.isNegative,
      scale,
    );
  }

  /// Parses finite decimal text, including scientific notation.
  ///
  /// Invalid syntax throws [FormatException]; unsupported magnitude or scale
  /// throws [RangeError]. No intermediate floating-point value is used.
  factory Decimal.parse(String source) {
    // Bound parsing work before allocating a potentially enormous BigInt.
    if (source.length > maxIntegerDigits + maxFractionDigits + 32) {
      throw const FormatException('Decimal input is too long.');
    }
    final match = _syntax.firstMatch(source);
    if (match == null ||
        match.end != source.length ||
        (match[2]!.isEmpty && (match[3] ?? '').isEmpty)) {
      throw const FormatException('Expected a finite decimal string.');
    }
    final exponent = int.tryParse(match[4] ?? '0');
    if (exponent == null ||
        exponent < -maxIntegerDigits - maxFractionDigits ||
        exponent > maxIntegerDigits + maxFractionDigits) {
      throw const FormatException('Decimal exponent is out of range.');
    }
    final fraction = match[3] ?? '';
    return Decimal._digits(
      '${match[2]}$fraction',
      match[1] == '-',
      fraction.length - exponent,
    );
  }

  static final _syntax = RegExp(
    r'^([+-]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$',
  );

  /// Parses finite decimal text, returning null for invalid or out-of-range input.
  static Decimal? tryParse(String source) {
    try {
      return Decimal.parse(source);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  factory Decimal._digits(String digits, bool negative, int scale) {
    var start = 0, end = digits.length;
    while (start < end && digits.codeUnitAt(start) == 48) {
      start++;
    }
    if (start == end) return zero;
    if (scale < -maxIntegerDigits ||
        scale > maxFractionDigits + digits.length) {
      throw RangeError('Decimal scale is out of range.');
    }
    while (digits.codeUnitAt(end - 1) == 48) {
      end--;
      scale--;
    }
    if (scale > maxFractionDigits || end - start - scale > maxIntegerDigits) {
      throw RangeError('Decimal exceeds the supported finite NUMERIC range.');
    }
    final coefficient = BigInt.parse(
      '${negative ? '-' : ''}${digits.substring(start, end)}',
    );
    return Decimal._(coefficient, scale);
  }

  static BigInt _power(int n) => BigInt.from(10).pow(n);

  /// Returns the exact additive inverse.
  Decimal operator -() => Decimal._(-coefficient, scale);

  /// Adds two exact values and checks the supported result range.
  Decimal operator +(Decimal other) {
    final common = math.max(scale, other.scale);
    return Decimal.fromBigInt(
      coefficient * _power(common - scale) +
          other.coefficient * _power(common - other.scale),
      scale: common,
    );
  }

  /// Subtracts [other] without rounding.
  Decimal operator -(Decimal other) => this + -other;

  /// Multiplies exactly and checks the supported result range.
  Decimal operator *(Decimal other) => Decimal.fromBigInt(
    coefficient * other.coefficient,
    scale: scale + other.scale,
  );

  /// Divides to [scale] fractional digits (negative scales round integer digits).
  /// The default rejects a result requiring rounding, including repeating ratios.
  Decimal divide(
    Decimal other, {
    required int scale,
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    validateScale(scale);
    if (other.coefficient == BigInt.zero) {
      throw UnsupportedError('Division by zero');
    }
    final shift = other.scale - this.scale + scale;
    return _quotient(
      coefficient * (shift > 0 ? _power(shift) : BigInt.one),
      other.coefficient * (shift < 0 ? _power(-shift) : BigInt.one),
      scale,
      rounding,
    );
  }

  /// Converts an integer fraction to a finite decimal at an explicit scale.
  /// Only the rounded result must fit the finite Decimal range.
  factory Decimal.fromFraction(
    BigInt numerator,
    BigInt denominator, {
    required int scale,
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    validateScale(scale);
    if (denominator == BigInt.zero) throw UnsupportedError('Division by zero');
    return _quotient(
      numerator * (scale > 0 ? _power(scale) : BigInt.one),
      denominator * (scale < 0 ? _power(-scale) : BigInt.one),
      scale,
      rounding,
    );
  }

  /// Rounds to an explicit scale; the default rejects lost precision.
  Decimal rounded(
    int scale, {
    DecimalRounding rounding = DecimalRounding.exact,
  }) {
    validateScale(scale);
    if (scale >= this.scale) return this;
    return _quotient(coefficient, _power(this.scale - scale), scale, rounding);
  }

  /// Throws [RangeError] if a result scale exceeds the supported finite range.
  static void validateScale(int scale) {
    if (scale < -maxIntegerDigits || scale > maxFractionDigits) {
      throw RangeError.range(
        scale,
        -maxIntegerDigits,
        maxFractionDigits,
        'scale',
      );
    }
  }

  /// Whether the value already fits a NUMERIC column without rounding.
  bool fits(int precision, int scale) {
    validateDigits(precision, scale);
    return coefficient == BigInt.zero ||
        this.scale <= scale &&
            coefficient.abs().toString().length - this.scale <=
                precision - scale;
  }

  /// PostgreSQL-style column coercion: round ties away from zero, then check
  /// precision. Expression result codecs do not inherit column constraints.
  Decimal constrained(int precision, int scale) {
    validateDigits(precision, scale);
    final result = rounded(scale, rounding: DecimalRounding.halfAwayFromZero);
    if (!result.fits(precision, scale)) {
      throw RangeError('Decimal does not fit NUMERIC($precision, $scale).');
    }
    return result;
  }

  /// Validates PostgreSQL-style column precision and scale declarations.
  static void validateDigits(int precision, int scale) {
    if (precision < 1 || precision > 1000 || scale < -1000 || scale > 1000) {
      throw ArgumentError(
        'Decimal precision must be 1..1000 and scale -1000..1000.',
      );
    }
  }

  static Decimal _quotient(
    BigInt a,
    BigInt b,
    int scale,
    DecimalRounding rounding,
  ) {
    var q = a ~/ b;
    final remainder = a.remainder(b);
    if (remainder != BigInt.zero) {
      final sign = a.sign * b.sign;
      final half = (remainder.abs() * BigInt.two).compareTo(b.abs());
      final increment = switch (rounding) {
        DecimalRounding.exact => throw const FormatException(
          'Decimal result requires rounding.',
        ),
        DecimalRounding.towardZero => false,
        DecimalRounding.floor => sign < 0,
        DecimalRounding.ceiling => sign > 0,
        DecimalRounding.halfAwayFromZero => half >= 0,
        DecimalRounding.halfEven => half > 0 || (half == 0 && q.isOdd),
      };
      if (increment) q += BigInt.from(sign);
    }
    return Decimal.fromBigInt(q, scale: scale);
  }

  @override
  int compareTo(Decimal other) {
    if (coefficient.sign != other.coefficient.sign) {
      return coefficient.sign.compareTo(other.coefficient.sign);
    }
    if (coefficient == BigInt.zero) return 0;
    final size = coefficient.abs().toString().length - scale;
    final otherSize = other.coefficient.abs().toString().length - other.scale;
    if (size != otherSize) return size.compareTo(otherSize) * coefficient.sign;
    final common = math.max(scale, other.scale);
    return (coefficient * _power(common - scale)).compareTo(
      other.coefficient * _power(common - other.scale),
    );
  }

  /// Compares exact numeric values, independent of their stored scale.
  bool operator <(Decimal other) => compareTo(other) < 0;

  /// Whether this exact value is less than or equal to [other].
  bool operator <=(Decimal other) => compareTo(other) <= 0;

  /// Whether this exact value is greater than [other].
  bool operator >(Decimal other) => compareTo(other) > 0;

  /// Whether this exact value is greater than or equal to [other].
  bool operator >=(Decimal other) => compareTo(other) >= 0;
  @override
  bool operator ==(Object other) =>
      other is Decimal &&
      coefficient == other.coefficient &&
      scale == other.scale;
  @override
  int get hashCode => Object.hash(coefficient, scale);
  @override
  String toString() {
    final digits = coefficient.abs().toString(),
        sign = coefficient.isNegative ? '-' : '';
    if (scale <= 0) return '$sign$digits${'0' * -scale}';
    if (scale >= digits.length) {
      return '${sign}0.${'0' * (scale - digits.length)}$digits';
    }
    final split = digits.length - scale;
    return '$sign${digits.substring(0, split)}.${digits.substring(split)}';
  }
}
