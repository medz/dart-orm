import 'package:orm/schema.dart';

final Model wallet = model("wallets", (
  id: integer().identity(),
  amount: decimal(precision: 5, scale: 2),
  hundreds: decimal(precision: 3, scale: -2),
  fraction: decimal(precision: 3, scale: 5),
  defaulted: decimal(defaultSql: "'1.235'", precision: 5, scale: 2),
  optional: decimal(precision: 5, scale: 2).nullable(),
));

final Model price = model(
  "prices",
  (id: decimal(precision: 4, scale: 2), label: text()),
  primaryKey: (r) => r.id,
  relations: (r) =>
      (receipts: referencedBy(() => receipt, on: (priceId: r.id))),
);

final Model receipt = model(
  "receipts",
  (id: integer().identity(), priceId: decimal(precision: 4, scale: 2)),
  relations: (r) =>
      (price: references((id: r.priceId), () => price, onDelete: .restrict)),
);
