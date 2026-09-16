import 'package:orm/migrate.dart';
import 'package:orm/sqlite.dart';

import '../temporal_precision/schema.orm.dart';

Future<void> checkTemporalPrecision() async {
  final db = await sqlite(const SqliteOptions.memory());
  void expect(bool value, String message) {
    if (!value) throw StateError(message);
  }

  try {
    await Migrator(db).apply([
      Migration.create('0001_precision', appSchema, dialect: db.dialect),
    ]);
    final moment = await db.moments.create(
      clock: LocalTime.parse('23:59:59.9995'),
      local: LocalDateTime.parse('0001-01-01 00:00:00.0005 BC'),
      instant: Codecs.dateTime.decode('1999-12-31 23:59:59.5Z'),
    );
    expect(
      moment.clock == LocalTime(24) &&
          moment.defaulted == LocalTime(24) &&
          moment.rounded == LocalTime(24),
      'Time precision, defaults or computed value changed',
    );
    expect(
      moment.local == LocalDateTime.parse('0001-01-01 00:00:00 BC'),
      'BC timestamp tie changed',
    );
    expect(
      moment.instant == DateTime.utc(1999, 12, 31, 23, 59, 59),
      'Instant epoch tie changed',
    );
    for (final text in [
      '294276-12-31 23:59:59.999499',
      '0001-01-01 00:00:00.0005 BC',
    ]) {
      final valueToRound = LocalDateTime.parse(text);
      final actual = await db.moments
          .select(
            (_) => value(valueToRound, Codecs.localDateTime).withPrecision(3),
          )
          .single();
      expect(
        actual == valueToRound.withPrecision(3),
        'Extended timestamp lost precision across worker',
      );
    }
    final upper = Codecs.dateTime.decode('275760-09-12 23:59:59.999999+00');
    final rounded = await db.moments
        .select((_) => value(upper, Codecs.dateTime).withPrecision(0))
        .single();
    expect(
      rounded == DateTime.utc(275760, 9, 13) &&
          upper.withPrecision(0) == rounded,
      'Upper instant rounding lost a day or precision',
    );
    await db.slots.create(time: LocalTime.parse('01:00:00.1235'), label: 'key');
    final booking = await db.bookings.create(
      time: LocalTime.parse('01:00:00.1239'),
    );
    final label = await db.bookings
        .byId(booking.id)
        .select((b) => b.slot.select((s) => s.label).one())
        .single();
    expect(label == 'key', 'Rounded relationship key failed');
    expect(
      (await verifySchema(db, SchemaSnapshot(appSchema))).matches,
      'Precision catalog differs',
    );
  } finally {
    await db.close();
  }
}
