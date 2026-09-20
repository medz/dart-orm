import 'dart:convert';
import 'dart:typed_data';

import 'package:mysql_client_plus/mysql_protocol.dart' as protocol;

import '../../values.dart';

final _mysqlMinInt = BigInt.from(-9223372036854775808);
final _mysqlMaxInt = BigInt.from(9223372036854775807);

int checkedMysqlInt(BigInt value) {
  if (value < _mysqlMinInt || value > _mysqlMaxInt) {
    throw const FormatException('MySQL integer exceeds Dart signed int64.');
  }
  return value.toInt();
}

Object? mysqlParameter(Object? value) => switch (value) {
  null || String() || int() || bool() || Uint8List() => value,
  double() => _finiteMysqlReal(value),
  SqlReal() => _finiteMysqlReal(value.value),
  BigInt() => value.toString(),
  Decimal() => value.toString(),
  SqlJson() => jsonEncode(value.value),
  DateTime() => _mysqlDateTime(value),
  LocalDate() => _mysqlDate(value),
  LocalTime() => value.toString(),
  LocalDateTime() => _mysqlLocalDateTime(value),
  _ => throw ArgumentError.value(
    value.runtimeType,
    'parameter',
    'Unsupported MySQL value type.',
  ),
};

double _finiteMysqlReal(double value) {
  if (!value.isFinite) {
    throw const FormatException('MySQL floating-point values must be finite.');
  }
  return value;
}

String _mysqlDate(LocalDate value) {
  if (value.year < 1000 || value.year > 9999) {
    throw const FormatException(
      'MySQL dates must be between years 1000 and 9999.',
    );
  }
  return value.toString();
}

String _mysqlLocalDateTime(LocalDateTime value) {
  _mysqlDate(value.date);
  return value.toString();
}

String _mysqlDateTime(DateTime value) {
  final utc = value.toUtc();
  final date = _mysqlDate(LocalDate(utc.year, utc.month, utc.day));
  final time = LocalTime(
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond * 1000 + utc.microsecond,
  );
  return '$date $time';
}

Object? mysqlValue(Object? value, int type, {required bool binary}) {
  if (value == null) return null;
  switch (type) {
    case protocol.mysqlColumnTypeString:
    case protocol.mysqlColumnTypeVarString:
    case protocol.mysqlColumnTypeVarChar:
      // The text protocol client treats binary collations as binary storage.
      // Supported CHAR/VARCHAR columns are UTF-8 even with utf8mb4_bin. Actual
      // BINARY/VARBINARY storage is intentionally outside this adapter's contract.
      return value is Uint8List ? utf8.decode(value) : value;
    case protocol.mysqlColumnTypeTiny:
    case protocol.mysqlColumnTypeShort:
    case protocol.mysqlColumnTypeLong:
    case protocol.mysqlColumnTypeLongLong:
    case protocol.mysqlColumnTypeInt24:
    case protocol.mysqlColumnTypeYear:
      return checkedMysqlInt(BigInt.parse(value as String));
    case protocol.mysqlColumnTypeFloat:
    case protocol.mysqlColumnTypeDouble:
      return double.parse(value as String);
    case protocol.mysqlColumnTypeDate:
      return (value as String).split(' ').first;
    case protocol.mysqlColumnTypeTime:
    case protocol.mysqlColumnTypeTime2:
    case protocol.mysqlColumnTypeTimestamp:
    case protocol.mysqlColumnTypeTimestamp2:
    case protocol.mysqlColumnTypeDateTime:
    case protocol.mysqlColumnTypeDateTime2:
      // mysql_client_plus formats the binary microsecond integer without
      // leading zeroes: 1 microsecond arrives as '.1', not '.000001'. The
      // binary protocol always encodes the full microsecond count.
      final text = value as String;
      final dot = text.lastIndexOf('.');
      return !binary || dot < 0
          ? text
          : '${text.substring(0, dot + 1)}${text.substring(dot + 1).padLeft(6, '0')}';
    case protocol.mysqlColumnTypeJson:
      return SqlJson(value);
    default:
      return value;
  }
}
