import 'dart:convert';
import 'dart:typed_data';

import 'decimal.dart';
import 'temporal.dart';

/// A non-SQL-null JSON document. Its value may itself be JSON null.
/// Drivers use this envelope for parsed JSON, including JSON string scalars.
final class SqlJson {
  /// The decoded JSON value, including JSON `null`.
  final Object? value;

  /// Wraps a JSON document without treating JSON `null` as SQL NULL.
  const SqlJson(this.value);
}

/// Explicit floating-point SQL input. JavaScript cannot distinguish an
/// integral double from int by runtime type; this preserves the SQL intention.
final class SqlReal {
  /// The value to bind as floating-point SQL input.
  final double value;

  /// Preserves floating-point intent even for an integral value on JavaScript.
  const SqlReal(this.value);
}

/// Converts a typed Dart value to database storage and decodes it on reads.
///
/// A codec defines a storage family and symmetric conversion functions. Use
/// [nullable] for SQL NULL and [map] for domain-specific Dart types.
final class Codec<T> {
  /// Logical storage family used when rendering and binding SQL.
  final String sqlType;
  // Nullable wrappers share a comparison identity, while remaining distinct
  // from a codec whose own decoder handles SQL NULL.
  final Object? _identity;

  /// Whether two codecs have the same storage and decoding identity.
  /// Nullable wrappers preserve identity; independently mapped codecs do not.
  bool sameStorageAs(Codec<Object?> other) =>
      (_identity ?? this) == (other._identity ?? other);
  final T Function(Object? value) _decode;
  final Object? Function(T value) _encode;

  /// Creates an explicit storage codec; conversion errors propagate to callers.
  const Codec(this.sqlType, this._decode, this._encode) : _identity = null;
  Codec._nullable(this.sqlType, this._decode, this._encode, this._identity);

  /// Stores a domain value as SQL text.
  const Codec.text(this._decode, String Function(T value) encode)
    : _identity = null,
      sqlType = 'text',
      _encode = encode;

  /// Stores a domain value as a SQL integer.
  const Codec.integer(this._decode, int Function(T value) encode)
    : _identity = null,
      sqlType = 'integer',
      _encode = encode;

  /// Converts a raw stored value into [T].
  T decode(Object? value) => _decode(value);

  /// Converts [value] into a value supported by the SQL driver.
  Object? encode(T value) => _encode(value);

  /// Whether [T] permits a null Dart result.
  bool get acceptsNull => null is T;

  /// Handles SQL NULL before delegating non-null values to this codec.
  ///
  /// Nullable wrappers share a comparison identity with each other, distinct
  /// from a decoder that handles SQL NULL itself.
  Codec<T?> nullable() => Codec._nullable(
    sqlType,
    (value) => value == null ? null : decode(value),
    (value) => value == null ? null : encode(value),
    _identity ?? (this, #nullable),
  );

  /// Adds domain conversions while preserving this codec's storage family.
  Codec<R> map<R>(R Function(T) from, T Function(R) to) => Codec(
    sqlType,
    (value) => from(decode(value)),
    (value) => encode(to(value)),
  );
}

/// Built-in conversions for SQL scalar values, JSON, and exact numeric types.
abstract final class Codecs {
  /// Calendar dates without timezones.
  static const date = Codec<LocalDate>('date', _decodeDate, _encodeDate);
  static LocalDate _decodeDate(Object? value) => switch (value) {
    LocalDate() => value,
    String() => LocalDate.parse(value),
    _ => throw const FormatException('Expected a local date or date text.'),
  };
  static String _encodeDate(LocalDate value) => value.toString();

  /// Wall-clock times with microsecond resolution, including 24:00.
  static const time = Codec<LocalTime>('time', _decodeTime, _encodeTime);
  static LocalTime _decodeTime(Object? value) => switch (value) {
    LocalTime() => value,
    String() => LocalTime.parse(value),
    _ => throw const FormatException('Expected a local time or time text.'),
  };
  static String _encodeTime(LocalTime value) => value.toString();

  /// Local calendar timestamps with no implied UTC instant.
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

  /// Exact finite decimals encoded as text without a floating-point conversion.
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

  /// Dart integers; textual database numerics must parse exactly as an integer.
  // PostgreSQL SUM(BIGINT) returns NUMERIC text. Parse exactly and reject
  // overflow instead of rounding through double.
  static final integer = Codec<int>(
    'integer',
    (v) => v is int ? v : int.parse(v as String),
    (v) => v,
  );

  /// Arbitrary-precision integers encoded as exact decimal text.
  static final bigint = Codec<BigInt>(
    'bigint',
    (v) => v is BigInt ? v : BigInt.parse(v.toString()),
    (v) => v.toString(),
  );

  /// Binary floating-point values with explicit SQL real intent on JavaScript.
  static final real = Codec<double>(
    'real',
    (v) => v is String ? double.parse(v) : (v as num).toDouble(),
    (v) =>
        const bool.fromEnvironment('dart.library.js_interop') ? SqlReal(v) : v,
  );

  /// SQL text without implicit string conversion.
  static final text = Codec<String>('text', (v) => v as String, (v) => v);

  /// Booleans decoded from true/false or integer 1/0; other inputs are rejected.
  static final boolean = Codec<bool>(
    'boolean',
    (v) => switch (v) {
      true || 1 => true,
      false || 0 => false,
      _ => throw FormatException('Invalid SQL boolean: $v'),
    },
    (v) => v,
  );

  /// UTC instants within the common finite PostgreSQL and Dart DateTime range.
  static const dateTime = Codec<DateTime>(
    'instant',
    decodeInstant,
    encodeInstant,
  );

  /// Binary data as [Uint8List].
  static final bytes = Codec<Uint8List>(
    'blob',
    (v) => v as Uint8List,
    (v) => v,
  );

  /// Parsed JSON values; JSON null and SQL NULL both decode to Dart null.
  static const json = Codec<Object?>('json', _decodeJson, jsonEncode);

  /// JSON documents wrapped in [SqlJson] to preserve JSON null.
  ///
  /// SQL NULL is rejected; use `.nullable()` when the column is nullable.
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

/// An ORM failure with a stable machine-readable code and optional cause.
final class OrmException implements Exception {
  /// Failure identifier, such as `QUERY.SCOPE` or `SESSION.CLOSED`.
  final String code;

  /// Human-readable context explaining the failure.
  final String message;

  /// Underlying driver or runtime failure, when one is available.
  final Object? cause;

  /// Creates a classified failure while retaining an optional original cause.
  const OrmException(this.code, this.message, {this.cause});
  @override
  String toString() => 'OrmException($code): $message';
}
