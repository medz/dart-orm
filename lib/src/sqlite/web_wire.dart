import 'dart:js_interop';
import 'dart:typed_data';

import '../../driver.dart';

/// Structured clone transports blobs as typed arrays and large integers as
/// tagged decimal text. It never sends Dart class instances to another worker.
JSAny? sqliteWebValue(Object? value, {bool parameter = false}) =>
    switch (value) {
      null => null,
      bool() => value.toJS,
      int()
          when parameter &&
              (value < -9007199254740991 || value > 9007199254740991) =>
        throw const OrmException(
          'CODEC.INTEGER',
          'Browser int transport requires a safe integer; use BigInt for wider integers or SqlReal for floating values.',
        ),
      SqlReal() => ['real'.toJS, value.value.toJS].toJS,
      num() => value.toJS,
      String() => value.toJS,
      Uint8List() => value.toJS,
      BigInt() => ['bigint'.toJS, value.toString().toJS].toJS,
      _ => throw const OrmException(
        'CODEC.PARAMETER',
        'Unsupported SQLite wire value.',
      ),
    };

Object? sqliteWebDartValue(JSAny? value) {
  if (value == null) return null;
  if (value.isA<JSString>()) return (value as JSString).toDart;
  if (value.isA<JSBoolean>()) return (value as JSBoolean).toDart;
  if (value.isA<JSNumber>()) {
    final number = (value as JSNumber).toDartDouble;
    return number.isFinite &&
            number.abs() <= 9007199254740991 &&
            number == number.truncateToDouble()
        ? number.toInt()
        : number;
  }
  if (value.isA<JSUint8Array>()) return (value as JSUint8Array).toDart;
  if (value.isA<JSArray>()) {
    final parts = value as JSArray<JSAny?>;
    if (parts.length == 2 && (parts[0]! as JSString).toDart == 'bigint') {
      return BigInt.parse((parts[1]! as JSString).toDart);
    }
    if (parts.length == 2 && (parts[0]! as JSString).toDart == 'real') {
      return SqlReal((parts[1]! as JSNumber).toDartDouble);
    }
  }
  throw const OrmException('DRIVER.PROTOCOL', 'Invalid SQLite worker value.');
}

JSArray<JSAny?> sqliteWebCommand(SqlCommand command) => [
  command.sql.toJS,
  command.parameters
      .map((v) => sqliteWebValue(v, parameter: true))
      .toList()
      .toJS,
].toJS;

SqlCommand sqliteWebDartCommand(JSAny? payload) {
  final parts = payload! as JSArray<JSAny?>;
  return SqlCommand(
    (parts[0]! as JSString).toDart,
    (parts[1]! as JSArray<JSAny?>).toDart.map(sqliteWebDartValue).toList(),
  );
}

JSArray<JSAny?> sqliteWebResult(SqlResult result) => [
  result.columns.map((c) => c.toJS).toList().toJS,
  result.rows.map((row) => row.map(sqliteWebValue).toList().toJS).toList().toJS,
  result.affectedRows.toJS,
].toJS;

SqlResult sqliteWebDartResult(JSAny? payload) {
  final parts = payload! as JSArray<JSAny?>;
  return SqlResult(
    [
      for (final row in (parts[1]! as JSArray<JSArray<JSAny?>>).toDart)
        row.toDart.map(sqliteWebDartValue).toList(),
    ],
    columns: [
      for (final c in (parts[0]! as JSArray<JSString>).toDart) c.toDart,
    ],
    affectedRows: (parts[2]! as JSNumber).toDartInt,
  );
}
