part of '../orm.dart';

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
  static const minJulianDay = 0;
  static const maxJulianDay = 2147483493;
  final int year, month, day;
  final int julianDay;
  const LocalDate._(this.year, this.month, this.day, this.julianDay);
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
  LocalDate addDays(int days) {
    if (days < minJulianDay - julianDay || days > maxJulianDay - julianDay) {
      throw RangeError('Date addition exceeds the supported range.');
    }
    return LocalDate.fromJulianDay(julianDay + days);
  }

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
  final int microseconds;
  const LocalTime._(this.microseconds);
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
  factory LocalTime.fromMicroseconds(int value) {
    if (value < 0 || value > _microsecondsPerDay) {
      throw RangeError.range(value, 0, _microsecondsPerDay, 'microseconds');
    }
    return LocalTime._(value);
  }
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
  static LocalTime? tryParse(String text) {
    try {
      return LocalTime.parse(text);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

  int get hour => microseconds ~/ 3600000000;
  int get minute => microseconds ~/ 60000000 % 60;
  int get second => microseconds ~/ 1000000 % 60;
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
  static const maxJulianDay = 109203527;
  final LocalDate date;
  final LocalTime time;
  const LocalDateTime._(this.date, this.time);
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
  static LocalDateTime? tryParse(String text) {
    try {
      return LocalDateTime.parse(text);
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
  }

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
