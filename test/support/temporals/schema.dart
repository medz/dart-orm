import 'package:orm/schema.dart';

final Model appointment = model("appointments", (
  id: integer().identity(),
  day: date(),
  time: time(defaultSql: "'12:30'"),
  starts: localDateTime().nullable(),
));

final Model holiday = model(
  "holidays",
  (day: date(), label: text()),
  primaryKey: (r) => r.day,
  relations: (r) => (visits: referencedBy(() => visit, on: (day: r.day))),
);

final Model visit = model(
  "visits",
  (id: integer().identity(), day: date()),
  relations: (r) =>
      (holiday: references((day: r.day), () => holiday, onDelete: .restrict)),
);
