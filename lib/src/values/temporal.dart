const _microsecondsPerDay = 86400000000;
int _floorDiv(int a, int b) => a ~/ b - (a < 0 && a % b != 0 ? 1 : 0);
String _pad(int value, int length) => value.toString().padLeft(length, '0');

int _gregorianJulianDay(int year, int month, int day) {
  final y = year - (month <= 2 ? 1 : 0);
  final cycle = _floorDiv(y, 400);
  final within = y - cycle * 400, m = month + (month > 2 ? -3 : 9);
  return cycle * 146097 +
      within * 365 +
      within ~/ 4 -
      within ~/ 100 +
      (153 * m + 2) ~/ 5 +
      day -
      1 +
      1721120;
}

/// A Gregorian calendar date, without a time or timezone.
/// Year 0 is 1 BC; negative years use astronomical numbering.
final class LocalDate implements Comparable<LocalDate> {
  /// First supported Julian day, matching the finite PostgreSQL DATE range.
  static const minJulianDay = 0;

  /// Last supported Julian day for a finite calendar date.
  static const maxJulianDay = 2147483493;

  /// Astronomical year; year zero corresponds to 1 BC.
  final int year;

  /// Gregorian month in the range 1 through 12.
  final int month;

  /// Day of the month, validated against the month and leap-year rules.
  final int day;

  /// Integer calendar-day ordinal used for exact comparison and date arithmetic.
  final int julianDay;
  const LocalDate._(this.year, this.month, this.day, this.julianDay);

  /// Creates a valid Gregorian date or throws [RangeError].
  factory LocalDate(int year, int month, int day) {
    if (year < -4713 ||
        year > 5874897 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > _monthDays(year, month)) {
      throw RangeError('Invalid Gregorian date.');
    }
    final ordinal = _gregorianJulianDay(year, month, day);
    if (ordinal < minJulianDay || ordinal > maxJulianDay) {
      throw RangeError('Date exceeds the finite PostgreSQL DATE range.');
    }
    return LocalDate._(year, month, day, ordinal);
  }

  /// Converts a supported Julian day ordinal to its Gregorian date.
  factory LocalDate.fromJulianDay(int value) {
    if (value < minJulianDay || value > maxJulianDay) {
      throw RangeError.range(value, minJulianDay, maxJulianDay, 'julianDay');
    }
    // March-based Gregorian cycles (400 years = 146097 days).
    final shifted = value - 1721120, cycle = _floorDiv(shifted, 146097);
    final days = shifted - cycle * 146097;
    final y = (days - days ~/ 1460 + days ~/ 36524 - days ~/ 146096) ~/ 365;
    final dayOfYear = days - (365 * y + y ~/ 4 - y ~/ 100);
    final marchMonth = (5 * dayOfYear + 2) ~/ 153;
    final day = dayOfYear - (153 * marchMonth + 2) ~/ 5 + 1;
    final month = marchMonth + (marchMonth < 10 ? 3 : -9);
    return LocalDate._(
      y + cycle * 400 + (month <= 2 ? 1 : 0),
      month,
      day,
      value,
    );
  }

  /// Parses `YYYY-MM-DD`, optionally followed by ` BC`.
  factory LocalDate.parse(String text) {
    final match = _syntax.firstMatch(text);
    if (match == null || match.end != text.length) {
      throw const FormatException(
        'Expected a Gregorian date without a timezone.',
      );
    }
    var year = int.parse(match[1]!);
    if (match[4] != null) {
      if (year <= 0) {
        throw const FormatException('BC dates require a positive era year.');
      }
      year = 1 - year;
    }
    return LocalDate(year, int.parse(match[2]!), int.parse(match[3]!));
  }
  static final _syntax = RegExp(
    r'^(-?\d{4,7})-(\d{2})-(\d{2})( BC)?$',
    caseSensitive: false,
  );

  /// Returns null when [text] is invalid or outside the supported range.
  static LocalDate? tryParse(String text) {
    try {
      return LocalDate.parse(text);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  static int _monthDays(int year, int month) => switch (month) {
    2 => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28,
    4 || 6 || 9 || 11 => 30,
    _ => 31,
  };

  /// Adds whole calendar days, rejecting results outside the supported range.
  LocalDate addDays(int days) {
    if (days < minJulianDay - julianDay || days > maxJulianDay - julianDay) {
      throw RangeError('Date addition exceeds the supported range.');
    }
    return LocalDate.fromJulianDay(julianDay + days);
  }

  /// Signed number of calendar days from this date to [other].
  int daysUntil(LocalDate other) => other.julianDay - julianDay;
  String get _civil =>
      '${_pad(year <= 0 ? 1 - year : year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';
  @override
  String toString() => '$_civil${year <= 0 ? ' BC' : ''}';
  @override
  int compareTo(LocalDate other) => julianDay.compareTo(other.julianDay);
  @override
  bool operator ==(Object other) =>
      other is LocalDate && julianDay == other.julianDay;
  @override
  int get hashCode => julianDay.hashCode;
}

/// A wall-clock time at microsecond resolution, including the endpoint 24:00.
/// The fourth constructor argument is the full fractional second (0..999999).
final class LocalTime implements Comparable<LocalTime> {
  /// Microseconds since midnight, including the endpoint 86400000000.
  final int microseconds;
  const LocalTime._(this.microseconds);

  /// Creates a valid wall-clock time or throws [RangeError].
  factory LocalTime(
    int hour, [
    int minute = 0,
    int second = 0,
    int microsecond = 0,
  ]) {
    if (hour < 0 ||
        hour > 24 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59 ||
        microsecond < 0 ||
        microsecond > 999999 ||
        hour == 24 && (minute != 0 || second != 0 || microsecond != 0)) {
      throw RangeError('Invalid time of day.');
    }
    return LocalTime._(
      ((hour * 60 + minute) * 60 + second) * 1000000 + microsecond,
    );
  }

  /// Creates a time from microseconds since midnight, including 24:00.
  factory LocalTime.fromMicroseconds(int value) {
    if (value < 0 || value > _microsecondsPerDay) {
      throw RangeError.range(value, 0, _microsecondsPerDay, 'microseconds');
    }
    return LocalTime._(value);
  }

  /// Parses `HH:mm[:ss[.ffffff]]` without a timezone.
  factory LocalTime.parse(String text) {
    final match = _syntax.firstMatch(text);
    if (match == null || match.end != text.length) {
      throw const FormatException(
        'Expected a time without a timezone, with at most six fractional digits.',
      );
    }
    return LocalTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3] ?? '0'),
      int.parse((match[4] ?? '').padRight(6, '0')),
    );
  }
  static final _syntax = RegExp(
    r'^(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?$',
  );

  /// Returns null when [text] is not a supported wall-clock time.
  static LocalTime? tryParse(String text) {
    try {
      return LocalTime.parse(text);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  /// Round fractional seconds, with exact halves toward the next second.
  LocalTime withPrecision(int digits) => LocalTime.fromMicroseconds(
    microseconds + _temporalRoundDelta(microseconds, digits),
  );

  /// Hour from 0 through 24; 24 is allowed only at the end-of-day endpoint.
  int get hour => microseconds ~/ 3600000000;

  /// Minute within the hour, from 0 through 59.
  int get minute => microseconds ~/ 60000000 % 60;

  /// Second within the minute, from 0 through 59.
  int get second => microseconds ~/ 1000000 % 60;

  /// Full fractional second, from 0 through 999999.
  int get microsecond => microseconds % 1000000;
  @override
  String toString() =>
      '${_pad(hour, 2)}:${_pad(minute, 2)}:${_pad(second, 2)}.${_pad(microsecond, 6)}';
  @override
  int compareTo(LocalTime other) => microseconds.compareTo(other.microseconds);
  @override
  bool operator ==(Object other) =>
      other is LocalTime && microseconds == other.microseconds;
  @override
  int get hashCode => microseconds.hashCode;
}

/// Calendar date and wall-clock time, with no timezone or implied UTC instant.
final class LocalDateTime implements Comparable<LocalDateTime> {
  /// Last supported Julian day for a finite PostgreSQL local timestamp.
  static const maxJulianDay = 109203527;

  /// Calendar date after normalizing a 24:00 input to the next day.
  final LocalDate date;

  /// Wall-clock time, always earlier than 24:00 after normalization.
  final LocalTime time;
  const LocalDateTime._(this.date, this.time);

  /// Combines a date and time, normalizing 24:00 to the next midnight.
  factory LocalDateTime(LocalDate date, LocalTime time) {
    if (time.hour == 24) {
      date = date.addDays(1);
      time = LocalTime(0);
    }
    if (date.julianDay > maxJulianDay) {
      throw RangeError(
        'Local timestamp exceeds the finite PostgreSQL TIMESTAMP range.',
      );
    }
    return LocalDateTime._(date, time);
  }

  /// Parses a date and time separated by a space or `T`, without a timezone.
  factory LocalDateTime.parse(String text) {
    final match = _syntax.firstMatch(text);
    if (match == null || match.end != text.length) {
      throw const FormatException(
        'Expected a local date and time without a timezone.',
      );
    }
    return LocalDateTime(
      LocalDate.parse('${match[1]}${match[3] ?? ''}'),
      LocalTime.parse(match[2]!),
    );
  }
  static final _syntax = RegExp(
    r'^(-?\d{4,7}-\d{2}-\d{2})[ T](\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?)( BC)?$',
    caseSensitive: false,
  );

  /// Returns null for invalid or out-of-range local timestamps.
  static LocalDateTime? tryParse(String text) {
    try {
      return LocalDateTime.parse(text);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  /// Match PostgreSQL TIMESTAMP(p): exact halves round away from 2000-01-01.
  LocalDateTime withPrecision(int digits) => add(
    Duration(
      microseconds: _temporalRoundDelta(
        time.microseconds,
        digits,
        beforeEpoch: date.julianDay < 2451545,
      ),
    ),
  );

  /// Adds elapsed calendar microseconds without applying timezone rules.
  LocalDateTime add(Duration duration) {
    final days = _floorDiv(duration.inMicroseconds, _microsecondsPerDay);
    final ticks =
        time.microseconds + duration.inMicroseconds % _microsecondsPerDay;
    return LocalDateTime(
      date.addDays(days + ticks ~/ _microsecondsPerDay),
      LocalTime.fromMicroseconds(ticks % _microsecondsPerDay),
    );
  }

  @override
  String toString() => '${date._civil} $time${date.year <= 0 ? ' BC' : ''}';
  @override
  int compareTo(LocalDateTime other) {
    final day = date.compareTo(other.date);
    return day == 0 ? time.compareTo(other.time) : day;
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDateTime && date == other.date && time == other.time;
  @override
  int get hashCode => Object.hash(date, time);
}

void _checkTemporalPrecision(int digits) {
  if (digits < 0 || digits > 6) throw RangeError.range(digits, 0, 6, 'digits');
}

// Use day-local microseconds so the full timestamp range stays exact on JS.
int _temporalRoundDelta(int ticks, int digits, {bool beforeEpoch = false}) {
  _checkTemporalPrecision(digits);
  final unit = const [1000000, 100000, 10000, 1000, 100, 10, 1][digits];
  final remainder = ticks % unit;
  return remainder * 2 > unit || remainder * 2 == unit && !beforeEpoch
      ? unit - remainder
      : -remainder;
}

/// Explicit precision conversion for resolved UTC instants.
extension InstantPrecision on DateTime {
  /// Round a resolved UTC instant using PostgreSQL TIMESTAMPTZ(p) rules.
  DateTime withPrecision(int digits) {
    final utc = _checkedInstant(this);
    final rounded = LocalDateTime(
      LocalDate(utc.year, utc.month, utc.day),
      LocalTime(
        utc.hour,
        utc.minute,
        utc.second,
        utc.millisecond * 1000 + utc.microsecond,
      ),
    ).withPrecision(digits);
    final date = rounded.date, time = rounded.time;
    return _checkedInstant(
      DateTime.utc(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
        time.second,
        time.microsecond ~/ 1000,
        time.microsecond % 1000,
      ),
    );
  }
}

// Intersection of PostgreSQL's finite lower bound and Dart DateTime's range.
const _minInstantMicros = -210866803200000000;
const _maxInstantMicros = 8640000000000000000;
const _unixEpochJulian = 2440588;
const _maxInstantJulian = 102440588;

DateTime decodeInstant(Object? value) => switch (value) {
  DateTime() => _checkedInstant(value),
  String() => _parseInstant(value),
  _ => throw const FormatException('Expected a UTC instant or timestamp text.'),
};

DateTime _checkedInstant(DateTime value) {
  final utc = value.toUtc(), millis = value.millisecondsSinceEpoch;
  // Epoch milliseconds fit JavaScript's exact integer range; total microseconds
  // do not. DateTime stores the remaining microsecond component separately.
  if (millis < _minInstantMicros ~/ 1000 ||
      millis > _maxInstantMicros ~/ 1000 ||
      millis == _maxInstantMicros ~/ 1000 && utc.microsecond != 0) {
    throw const FormatException(
      'Instant exceeds the common DateTime/PostgreSQL range.',
    );
  }
  return utc;
}

String encodeInstant(DateTime value) {
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
    if (const bool.fromEnvironment('dart.library.js_interop')) {
      final date = LocalDate.fromJulianDay(ordinal);
      final clock = LocalTime.fromMicroseconds(within);
      return DateTime.utc(
        date.year,
        date.month,
        date.day,
        clock.hour,
        clock.minute,
        clock.second,
        clock.microsecond ~/ 1000,
        clock.microsecond % 1000,
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
