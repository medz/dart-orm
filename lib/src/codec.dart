part of '../orm.dart';

/// A non-SQL-null JSON document. Its value may itself be JSON null.
/// Drivers use this envelope for parsed JSON, including JSON string scalars.
final class SqlJson {
  final Object? value;
  const SqlJson(this.value);
}

/// Storage and Dart values meet only at this boundary.
final class Codec<T> {
  final String sqlType;
  // Nullable wrappers share a comparison identity, while remaining distinct
  // from a codec whose own decoder handles SQL NULL.
  final Object? _identity;
  Object get _storageIdentity => _identity ?? this;
  final T Function(Object? value) _decode;
  final Object? Function(T value) _encode;

  const Codec(this.sqlType, this._decode, this._encode) : _identity = null;
  Codec._nullable(this.sqlType, this._decode, this._encode, this._identity);
  const Codec.text(this._decode, String Function(T value) encode)
    : _identity = null,
      sqlType = 'text',
      _encode = encode;
  const Codec.integer(this._decode, int Function(T value) encode)
    : _identity = null,
      sqlType = 'integer',
      _encode = encode;
  T decode(Object? value) => _decode(value);
  Object? encode(T value) => _encode(value);
  bool get acceptsNull => null is T;

  Codec<T?> nullable() => Codec._nullable(
    sqlType,
    (value) => value == null ? null : decode(value),
    (value) => value == null ? null : encode(value),
    _identity ?? (this, #nullable),
  );

  Codec<R> map<R>(R Function(T) from, T Function(R) to) => Codec(
    sqlType,
    (value) => from(decode(value)),
    (value) => encode(to(value)),
  );
}

abstract final class Codecs {
  static const date = Codec<LocalDate>('date', _decodeDate, _encodeDate);
  static LocalDate _decodeDate(Object? value) => switch (value) {
    LocalDate() => value,
    String() => LocalDate.parse(value),
    _ => throw const FormatException('Expected a local date or date text.'),
  };
  static String _encodeDate(LocalDate value) => value.toString();
  static const time = Codec<LocalTime>('time', _decodeTime, _encodeTime);
  static LocalTime _decodeTime(Object? value) => switch (value) {
    LocalTime() => value,
    String() => LocalTime.parse(value),
    _ => throw const FormatException('Expected a local time or time text.'),
  };
  static String _encodeTime(LocalTime value) => value.toString();
  static const localDateTime = Codec<LocalDateTime>(
    'local_datetime',
    _decodeLocalDateTime,
    _encodeLocalDateTime,
  );
  static LocalDateTime _decodeLocalDateTime(Object? value) => switch (value) {
    LocalDateTime() => value,
    String() => LocalDateTime.parse(value),
    _ => throw const FormatException(
      'Expected a local timestamp or timestamp text.',
    ),
  };
  static String _encodeLocalDateTime(LocalDateTime value) => value.toString();
  static const decimal = Codec<Decimal>(
    'decimal',
    _decodeDecimal,
    _encodeDecimal,
  );
  static Decimal _decodeDecimal(Object? value) => switch (value) {
    String() => Decimal.parse(value),
    int() => Decimal.fromBigInt(BigInt.from(value)),
    BigInt() => Decimal.fromBigInt(value),
    _ => throw const FormatException(
      'Exact decimal storage requires text or an integer.',
    ),
  };
  static String _encodeDecimal(Decimal value) => value.toString();

  /// Enum storage labels are explicit and independent of declaration ordinals.
  static Codec<E> enumeration<E extends Enum>(Map<E, String> labels) {
    final encode = Map<E, String>.unmodifiable(labels);
    final decode = {for (final entry in encode.entries) entry.value: entry.key};
    if (encode.isEmpty || decode.length != encode.length) {
      throw ArgumentError('Enum mappings must contain unique storage labels.');
    }
    return Codec<E>(
      'text',
      (value) {
        if (decode[value] case final result?) return result;
        throw const OrmException('CODEC.ENUM', 'Unknown stored enum value.');
      },
      (value) {
        if (encode[value] case final result?) return result;
        throw const OrmException(
          'CODEC.ENUM',
          'Enum value has no storage label.',
        );
      },
    );
  }

  // PostgreSQL SUM(BIGINT) returns NUMERIC text. Parse exactly and reject
  // overflow instead of rounding through double.
  static final integer = Codec<int>(
    'integer',
    (v) => v is int ? v : int.parse(v as String),
    (v) => v,
  );
  static final bigint = Codec<BigInt>(
    'bigint',
    (v) => v is BigInt ? v : BigInt.parse(v.toString()),
    (v) => v.toString(),
  );
  static final real = Codec<double>(
    'real',
    (v) => v is String ? double.parse(v) : (v as num).toDouble(),
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
  static const dateTime = Codec<DateTime>(
    'instant',
    _decodeInstant,
    _encodeInstant,
  );
  static final bytes = Codec<Uint8List>(
    'blob',
    (v) => v as Uint8List,
    (v) => v,
  );
  static const json = Codec<Object?>('json', _decodeJson, jsonEncode);
  static const jsonDocument = Codec<SqlJson>(
    'json',
    _jsonDocument,
    _encodeDocument,
  );
  static Object? _decodeJson(Object? value) => switch (value) {
    SqlJson() => value.value,
    String() => jsonDecode(value),
    _ => value,
  };
  static SqlJson _jsonDocument(Object? value) => switch (value) {
    null => throw const FormatException('SQL NULL is not a JSON document.'),
    SqlJson() => value,
    _ => SqlJson(_decodeJson(value)),
  };
  static String _encodeDocument(SqlJson value) => jsonEncode(value.value);
}

final class OrmException implements Exception {
  final String code;
  final String message;
  final Object? cause;
  const OrmException(this.code, this.message, {this.cause});
  @override
  String toString() => 'OrmException($code): $message';
}
