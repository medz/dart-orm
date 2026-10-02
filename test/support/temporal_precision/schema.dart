import 'package:orm/values.dart';
import 'package:orm/schema.dart';

@Model(table: "moments")
final class Moment({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "clock", precision: 3) required final LocalTime clock,
  @Column(name: "local", precision: 3) required final LocalDateTime local,
  @Column(name: "instant", precision: 0) required final DateTime instant,
  @Column(name: "optional", precision: 2) required final LocalTime? optional,
  @Column(name: "defaulted", precision: 3)
  @DatabaseDefault.sql("'23:59:59.9995'")
  required final LocalTime defaulted,
  @Column(name: "rounded", precision: 0)
  @Computed(
    "\"clock\"",
    postgres: "\"clock\"",
    mysql: "\"clock\"",
    mariadb: "\"clock\"",
    storage: .stored,
  )
  required final LocalTime rounded,
});

@Model(table: "slots")
@Relation(
  target: Booking,
  name: "bookings",
  fields: ["time"],
  keys: ["time"],
  constraint: false,
)
final class Slot({
  @Id(generated: false)
  @Column(name: "time", precision: 3)
  required final LocalTime time,
  @Column(name: "label") required final String label,
});

@Model(table: "bookings")
@Relation(
  target: Slot,
  name: "slot",
  fields: ["time"],
  keys: ["time"],
  onDelete: .restrict,
)
final class Booking({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "time", precision: 3) required final LocalTime time,
});
