import 'package:orm/values.dart';
import 'package:orm/schema.dart';

@Model(table: "appointments")
final class Appointment({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "day") required final LocalDate day,
  @Column(name: "time")
  @DatabaseDefault.sql("'12:30'")
  required final LocalTime time,
  @Column(name: "starts") required final LocalDateTime? starts,
});

@Model(table: "holidays")
@Relation(
  target: Visit,
  name: "visits",
  fields: ["day"],
  keys: ["day"],
  constraint: false,
)
final class Holiday({
  @Id(generated: false) @Column(name: "day") required final LocalDate day,
  @Column(name: "label") required final String label,
});

@Model(table: "visits")
@Relation(
  target: Holiday,
  name: "holiday",
  fields: ["day"],
  keys: ["day"],
  onDelete: .restrict,
)
final class Visit({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "day") required final LocalDate day,
});
