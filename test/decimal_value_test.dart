@Tags(['core'])
library;

import 'package:orm/orm.dart';
import 'package:test/test.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  test('normalization, scientific notation, equality and hash are exact', () {
    for (final source in ['1', '+1.', '.1e1', '010.000e-1', '1.000']) {
      expect(d(source), d('1'));
      expect(d(source).toString(), '1');
      expect(d(source).hashCode, d('1').hashCode);
    }
    expect(d('-0.000'), Decimal.zero);
    expect(d('1000').coefficient, BigInt.one);
    expect(d('1000').scale, -3);
    expect(d('-.00100').toString(), '-0.001');
    expect(
      d('12345678901234567890.1234567890123456789').toString(),
      '12345678901234567890.1234567890123456789',
    );
  });
  test('invalid and approximate inputs fail instead of silently rounding', () {
    for (final s in [
      '',
      '.',
      '+',
      ' 1',
      '1 ',
      '1\n',
      'NaN',
      'Infinity',
      '-Infinity',
      '0x10',
      '1_000',
      '1e',
      '1e9999999999999999999999',
      '1e-9223372036854775808',
    ]) {
      expect(Decimal.tryParse(s), null, reason: s);
      expect(() => d(s), throwsFormatException, reason: s);
    }
    for (final v in [1.0, double.nan, double.infinity, null, true]) {
      expect(() => Codecs.decimal.decode(v), throwsFormatException);
    }
    expect(
      Codecs.decimal.decode(BigInt.parse('9007199254740993')),
      d('9007199254740993'),
    );
    expect(Codecs.decimal.nullable().decode(null), null);
  });
  test('range boundaries are checked without binary numeric conversions', () {
    expect(d('1e131071').toString().length, 131072);
    expect(d('1e-16383').scale, 16383);
    expect(() => d('1e131072'), throwsRangeError);
    expect(
      () => Decimal.fromBigInt(BigInt.from(10), scale: -9223372036854775808),
      throwsRangeError,
    );
    expect(
      () => Decimal.fromBigInt(BigInt.one, scale: 9223372036854775807),
      throwsRangeError,
    );
    expect(() => d('1e-16384'), throwsRangeError);
    expect(() => d('1e131071') * d('10'), throwsRangeError);
    expect(() => d('1e-16383') * d('.1'), throwsRangeError);
  });
  test(
    'addition, subtraction, multiplication and ordering keep every digit',
    () {
      expect(d('0.1') + d('0.2'), d('0.3'));
      expect(
        d('9007199254740993.123456789') - d('.123456788'),
        d('9007199254740993.000000001'),
      );
      expect(
        d('123456789.123456789') * d('1000000001'),
        d('123456789246913578.123456789'),
      );
      final sorted = [
        '10',
        '2',
        '-1000',
        '-2.001',
        '-2',
        '0',
        '0.00001',
      ].map(d).toList()..sort();
      expect(sorted.map((v) => v.toString()), [
        '-1000',
        '-2.001',
        '-2',
        '0',
        '0.00001',
        '2',
        '10',
      ]);
    },
  );
  test('division requires an explicit scale and rejects implicit rounding', () {
    expect(d('1').divide(d('8'), scale: 3), d('.125'));
    expect(d('10').divide(d('0.2'), scale: 0), d('50'));
    expect(d('.001').divide(d('10'), scale: 4), d('.0001'));
    expect(() => d('1').divide(d('3'), scale: 8), throwsFormatException);
    expect(() => d('1').divide(Decimal.zero, scale: 2), throwsUnsupportedError);
    expect(() => d('1').rounded(16384), throwsRangeError);
  });
  test('rounding modes handle negative values, ties and negative scales', () {
    for (final negative in [false, true]) {
      final v = d(negative ? '-2.5' : '2.5');
      expect(v.rounded(0, rounding: .towardZero), d(negative ? '-2' : '2'));
      expect(v.rounded(0, rounding: .floor), d(negative ? '-3' : '2'));
      expect(v.rounded(0, rounding: .ceiling), d(negative ? '-2' : '3'));
      expect(v.rounded(0, rounding: .halfEven), d(negative ? '-2' : '2'));
      expect(
        v.rounded(0, rounding: .halfAwayFromZero),
        d(negative ? '-3' : '3'),
      );
      expect(
        d(negative ? '-3.5' : '3.5').rounded(0, rounding: .halfEven),
        d(negative ? '-4' : '4'),
      );
      expect(
        v.divide(d('-1'), scale: 0, rounding: .floor),
        d(negative ? '2' : '-3'),
      );
    }
    expect(d('1250').rounded(-2, rounding: .halfEven), d('1200'));
    expect(d('1350').rounded(-2, rounding: .halfEven), d('1400'));
    expect(d('2.5001').rounded(0, rounding: .halfEven), d('3'));
    expect(d('2.4999').rounded(0, rounding: .halfAwayFromZero), d('2'));
  });
  test(
    'small fixed-scale arithmetic agrees with independent integer arithmetic',
    () {
      for (var a = -31; a <= 31; a++) {
        for (var b = -7; b <= 7; b++) {
          final da = Decimal.fromBigInt(BigInt.from(a), scale: 2),
              db = Decimal.fromBigInt(BigInt.from(b), scale: 1);
          expect(
            da + db,
            Decimal.fromBigInt(BigInt.from(a + b * 10), scale: 2),
          );
          expect(da * db, Decimal.fromBigInt(BigInt.from(a * b), scale: 3));
          expect(da.compareTo(db).sign, a.compareTo(b * 10).sign);
        }
      }
    },
  );
}
