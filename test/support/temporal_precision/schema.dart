import 'package:orm/schema.dart';

final Model moment = model("moments", (
  id: integer().identity(),
  clock: time(precision: 3),
  local: localDateTime(precision: 3),
  instant: dateTime(precision: 0),
  optional: time(precision: 2).nullable(),
  defaulted: time(defaultSql: "'23:59:59.9995'", precision: 3),
  rounded: time(precision: 0).computed(
    "\"clock\"",
    postgres: "\"clock\"",
    mysql: "\"clock\"",
    mariadb: "\"clock\"",
    storage: .stored,
  ),
));

final Model slot = model(
  "slots",
  (time: time(precision: 3), label: text()),
  primaryKey: (r) => r.time,
  relations: (r) => (bookings: referencedBy(() => booking, on: (time: r.time))),
);

final Model booking = model(
  "bookings",
  (id: integer().identity(), time: time(precision: 3)),
  relations: (r) =>
      (slot: references((time: r.time), () => slot, onDelete: .restrict)),
);
