import 'package:orm/schema.dart';

typedef Appointment = ({
  @Id.generated() int id,
  LocalDate day,
  @Default.sql("'12:30'") LocalTime time,
  LocalDateTime? starts,
});
typedef Holiday = ({@Id() LocalDate day, String label});
typedef Visit = ({@Id.generated() int id, LocalDate day});
final appointments = entity<Appointment>();
final holidays = entity<Holiday>();
final visits = entity<Visit>();
final holiday = visits
    .key((v) => v.day)
    .references(holidays.key((h) => h.day), inverse: 'visits');
