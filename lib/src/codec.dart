part of '../orm.dart';

/// Storage and Dart values meet only at this boundary.
final class Codec<T> {
  final String sqlType;
  final T Function(Object? value) decode;
  final Object? Function(T value) encode;

  const Codec(this.sqlType, this.decode, this.encode);

  Codec<T?> nullable() => Codec(
    sqlType,
    (value) => value == null ? null : decode(value),
    (value) => value == null ? null : encode(value),
  );

  Codec<R> map<R>(R Function(T) from, T Function(R) to) => Codec(
    sqlType,
    (value) => from(decode(value)),
    (value) => encode(to(value)),
  );
}

abstract final class Codecs {
  static final integer = Codec<int>('integer', (v) => v as int, (v) => v);
  static final bigint = Codec<BigInt>(
    'bigint',
    (v) => v is BigInt ? v : BigInt.parse(v.toString()),
    (v) => v.toString(),
  );
  static final real = Codec<double>(
    'real',
    (v) => (v as num).toDouble(),
    (v) => v,
  );
  static final text = Codec<String>('text', (v) => v as String, (v) => v);
  static final boolean = Codec<bool>(
    'boolean',
    (v) => switch (v) {
      true || 1 => true,
      false || 0 => false,
      _ => throw FormatException('Invalid SQL boolean: $v'),
    },
    (v) => v,
  );
  static final dateTime = Codec<DateTime>(
    'timestamp',
    (v) => (v is DateTime ? v : DateTime.parse(v as String)).toUtc(),
    (v) => v.toUtc(),
  );
  static final bytes = Codec<Uint8List>(
    'blob',
    (v) => v as Uint8List,
    (v) => v,
  );
  static final json = Codec<Object?>(
    'json',
    (v) => v is String ? jsonDecode(v) : v,
    jsonEncode,
  );
}

final class OrmException implements Exception {
  final String code;
  final String message;
  final Object? cause;
  const OrmException(this.code, this.message, {this.cause});
  @override
  String toString() => 'OrmException($code): $message';
}
