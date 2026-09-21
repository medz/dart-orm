import 'package:orm/schema.dart';

final Model entry = model("entries", (
  id: integer().identity(),
  amount: decimal(),
  fee: decimal().nullable(),
  tax: decimal(defaultSql: "'0.10'"),
  bucket: text(),
));

final Model rate = model(
  "rates",
  (id: decimal(), label: text()),
  primaryKey: (r) => r.id,
  relations: (r) =>
      (allocations: referencedBy(() => allocation, on: (rateId: r.id))),
);

final Model allocation = model(
  "allocations",
  (id: integer().identity(), rateId: decimal()),
  relations: (r) =>
      (rate: references((id: r.rateId), () => rate, onDelete: .restrict)),
);
