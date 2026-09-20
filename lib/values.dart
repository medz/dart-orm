/// Exact numeric values, calendar values, and explicit storage codecs.
///
/// Use [Codecs] for built-in conversions, or [Codec.map] to store an application
/// value through an existing codec. No database connection is required.
///
/// {@category Values}
/// {@canonicalFor codec.SqlJson}
/// {@canonicalFor codec.SqlReal}
/// {@canonicalFor codec.Codec}
/// {@canonicalFor codec.Codecs}
/// {@canonicalFor codec.OrmException}
/// {@canonicalFor decimal.Decimal}
/// {@canonicalFor decimal.DecimalRounding}
/// {@canonicalFor temporal.LocalDate}
/// {@canonicalFor temporal.LocalTime}
/// {@canonicalFor temporal.LocalDateTime}
/// {@canonicalFor temporal.InstantPrecision}
library;

export 'src/values/codec.dart'
    show SqlJson, SqlReal, Codec, Codecs, OrmException;
export 'src/values/decimal.dart' show Decimal, DecimalRounding;
export 'src/values/temporal.dart'
    show LocalDate, LocalTime, LocalDateTime, InstantPrecision;
