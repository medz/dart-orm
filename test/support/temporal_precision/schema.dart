import 'package:orm/schema.dart';

typedef Moment = ({
  @Id.generated() int id,
  @TemporalPrecision(3) LocalTime clock,
  @TemporalPrecision(3) LocalDateTime local,
  @TemporalPrecision(0) DateTime instant,
  @TemporalPrecision(2) LocalTime? optional,
  @Default.sql("'23:59:59.9995'") @TemporalPrecision(3) LocalTime defaulted,
  @Computed.sql('"clock"') @TemporalPrecision(0) LocalTime rounded,
});
typedef Slot = ({@Id() @TemporalPrecision(3) LocalTime time, String label});
typedef Booking = ({
  @Id.generated() int id,
  @TemporalPrecision(3) LocalTime time,
});
final moments = entity<Moment>();
final slots = entity<Slot>();
final bookings = entity<Booking>();
final slot = bookings
    .key((b) => b.time)
    .references(slots.key((s) => s.time), inverse: 'bookings');
