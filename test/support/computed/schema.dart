import 'package:orm/schema.dart';

final Model line = model(
  "lines",
  (
    id: integer().identity(),
    price: integer(),
    quantity: integer(),
    label: text(),
    note: text().nullable(),
    total: integer().computed(
      "price * quantity",
      postgres: "price * quantity",
      mysql: "price * quantity",
      mariadb: "price * quantity",
      storage: .stored,
    ),
    labelSize: integer().computed(
      "length(label)",
      postgres: "char_length(label)",
      mysql: "length(label)",
      mariadb: "length(label)",
      storage: .virtual,
    ),
    normalizedNote: text().nullable().computed(
      "upper(note)",
      postgres: "upper(note)",
      mysql: "upper(note)",
      mariadb: "upper(note)",
      storage: .stored,
    ),
  ),
  indexes: (r) => [index(r.total, name: "by_total", unique: false)],
  checks: [
    check(
      "price >= 0 AND quantity >= 0",
      name: "nonnegative",
      postgres: "price >= 0 AND quantity >= 0",
      mysql: "price >= 0 AND quantity >= 0",
      mariadb: "price >= 0 AND quantity >= 0",
    ),
  ],
  relations: (r) =>
      (band: references((id: r.total), () => band, constraint: false)),
);

final Model band = model(
  "bands",
  (id: integer(), name: text()),
  primaryKey: (r) => r.id,
  relations: (r) => (lines: referencedBy(() => line, on: (total: r.id))),
);
