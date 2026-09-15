part of '../orm.dart';

// Intersection of PostgreSQL's finite lower bound and Dart DateTime's range.
const _minInstantMicros = -210866803200000000;
const _maxInstantMicros = 8640000000000000000;
const _unixEpochJulian = 2440588;
const _maxInstantJulian = 102440588;

DateTime _decodeInstant(Object? value) => switch (value) {
  DateTime() => _checkedInstant(value),
  String() => _parseInstant(value),
  _ => throw const FormatException('Expected a UTC instant or timestamp text.'),
};

DateTime _checkedInstant(DateTime value) {
  final utc = value.toUtc(), ticks = value.microsecondsSinceEpoch;
  if (ticks < _minInstantMicros || ticks > _maxInstantMicros) {
    throw const FormatException(
      'Instant exceeds the common DateTime/PostgreSQL range.',
    );
  }
  return utc;
}

String _encodeInstant(DateTime value) {
  final utc = _checkedInstant(value);
  final date = LocalDate(utc.year, utc.month, utc.day);
  final time = LocalTime(
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond * 1000 + utc.microsecond,
  );
  return '${date._civil} $time+00${date.year <= 0 ? ' BC' : ''}';
}

final _instantSyntax = RegExp(
  r'^(-?\d{4,7})-(\d{2})-(\d{2})[ T](\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?)(Z|[+-]\d{2}(?::?\d{2})?(?::?\d{2})?)?( BC)?$',
  caseSensitive: false,
);

DateTime _parseInstant(String text) {
  final match = _instantSyntax.firstMatch(text);
  if (match == null || match.end != text.length) {
    throw const FormatException(
      'Expected a timestamp with at most six fractional digits.',
    );
  }
  try {
    var year = int.parse(match[1]!);
    if (match[6] != null) {
      if (year <= 0) {
        throw const FormatException('BC requires a positive era year.');
      }
      year = 1 - year;
    }
    final month = int.parse(match[2]!), day = int.parse(match[3]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > LocalDate._monthDays(year, month)) {
      throw const FormatException('Invalid calendar date in instant.');
    }
    final zone = match[5];
    var offset = 0;
    if (zone != null && zone.toUpperCase() != 'Z') {
      final digits = zone.substring(1).replaceAll(':', '');
      final hours = int.parse(digits.substring(0, 2));
      final minutes = digits.length >= 4
          ? int.parse(digits.substring(2, 4))
          : 0;
      final seconds = digits.length == 6
          ? int.parse(digits.substring(4, 6))
          : 0;
      if (hours > 15 || minutes > 59 || seconds > 59) {
        throw const FormatException('Invalid UTC offset.');
      }
      offset =
          ((hours * 60 + minutes) * 60 + seconds) *
          1000000 *
          (zone[0] == '-' ? -1 : 1);
    }
    // Zone-less database storage is explicitly UTC (SQLite CURRENT_TIMESTAMP),
    // independent of the process's local timezone. Validate before multiplying
    // days into int64 microseconds, including offset crossings at either bound.
    final time = LocalTime.parse(match[4]!).microseconds - offset;
    final ordinal =
        _gregorianJulianDay(year, month, day) +
        _floorDiv(time, _microsecondsPerDay);
    final within = time % _microsecondsPerDay;
    if (ordinal < 0 ||
        ordinal > _maxInstantJulian ||
        ordinal == _maxInstantJulian && within != 0) {
      throw const FormatException(
        'Instant exceeds the common DateTime/PostgreSQL range.',
      );
    }
    return DateTime.fromMicrosecondsSinceEpoch(
      (ordinal - _unixEpochJulian) * _microsecondsPerDay + within,
      isUtc: true,
    );
  } on RangeError {
    throw const FormatException('Invalid timestamp components.');
  }
}
