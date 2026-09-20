import 'dart:typed_data';

import 'package:postgres/postgres.dart' as pg;

import '../../values.dart';

/// Native calendar values and UTC instants, without integer overflow.
/// Local calendar types cover PostgreSQL's full finite range; UTC instants
/// additionally respect Dart DateTime's range.
/// Pass this registry to PoolSettings before borrowing a pool with
/// PostgresDriver.borrow(temporal: true).
pg.TypeRegistry postgresTypeRegistry() => pg.TypeRegistry(
  codecs: {
    pg.Type.date.oid!: _TemporalCodec('date'),
    pg.Type.time.oid!: _TemporalCodec('time'),
    pg.Type.timestampWithoutTimezone.oid!: _TemporalCodec('local_datetime'),
    pg.Type.timestampWithTimezone.oid!: _TemporalCodec('instant'),
  },
);

final class _TemporalCodec(final String kind) implements pg.Codec {
  @override
  pg.EncodedValue? encode(pg.TypedValue input, pg.CodecContext context) {
    final value = input.value;
    if (value == null) return pg.EncodedValue.null$();
    if (kind == 'instant' && value is DateTime) {
      return pg.EncodedValue.text(
        Uint8List.fromList(
          context.encoding.encode(Codecs.dateTime.encode(value) as String),
        ),
      );
    }
    if (value is! String &&
        value is! LocalDate &&
        value is! LocalTime &&
        value is! LocalDateTime) {
      return null;
    }
    return pg.EncodedValue.text(
      Uint8List.fromList(context.encoding.encode(value.toString())),
    );
  }

  @override
  Object? decode(pg.EncodedValue input, pg.CodecContext context) {
    final bytes = input.bytes;
    if (bytes == null) return null;
    if (input.isText) {
      final text = context.encoding.decode(bytes);
      if (text == 'infinity' || text == '-infinity') return text;
      if (kind == 'instant') return text;
      return switch (kind) {
        'date' => LocalDate.parse(text),
        'time' => LocalTime.parse(text),
        _ => LocalDateTime.parse(text),
      };
    }
    final data = ByteData.sublistView(bytes);
    if (kind == 'date') {
      final days = data.getInt32(0);
      if (days == 2147483647) return 'infinity';
      if (days == -2147483648) return '-infinity';
      return LocalDate.fromJulianDay(2451545 + days);
    }
    final ticks = data.getInt64(0);
    if (kind == 'time') return LocalTime.fromMicroseconds(ticks);
    if (ticks == 9223372036854775807) return 'infinity';
    if (ticks == -9223372036854775808) return '-infinity';
    if (ticks < -211813488000000000 || ticks >= 9223371331200000000) {
      throw const FormatException('Non-finite or unsupported local timestamp.');
    }
    if (kind == 'instant' && ticks <= 8639053315200000000) {
      // Check before adding the epoch offset: PostgreSQL's maximum is beyond
      // DateTime's range and would otherwise overflow a native int64.
      return DateTime.fromMicrosecondsSinceEpoch(
        ticks + 946684800000000,
        isUtc: true,
      );
    }
    const day = 86400000000;
    final days = ticks ~/ day - (ticks < 0 && ticks % day != 0 ? 1 : 0);
    final local = LocalDateTime(
      LocalDate.fromJulianDay(2451545 + days),
      LocalTime.fromMicroseconds(ticks % day),
    );
    // Preserve out-of-DateTime finite values in raw results. Typed instant
    // decoding rejects them, without overflowing or interrupting protocol reads.
    return kind == 'instant' ? '$local+00' : local;
  }
}
