import 'package:orm/schema.dart';

final Model event = model("events", (
  id: integer().identity(),
  at: dateTime(),
  created: dateTime(defaultSql: "CURRENT_TIMESTAMP"),
  optional: dateTime().nullable(),
));

final Model moment = model(
  "moments",
  (at: dateTime(), label: text(defaultSql: "'pending'")),
  primaryKey: (r) => r.at,
  relations: (r) => (links: referencedBy(() => link, on: (at: r.at))),
);

final Model link = model(
  "links",
  (id: integer().identity(), at: dateTime()),
  relations: (r) =>
      (moment: references((at: r.at), () => moment, onDelete: .restrict)),
);
