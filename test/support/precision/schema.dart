import 'package:orm/values.dart';
import 'package:orm/schema.dart';

@Model(table: "wallets")
final class Wallet({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "amount", precision: 5, scale: 2) required final Decimal amount,
  @Column(name: "hundreds", precision: 3, scale: -2)
  required final Decimal hundreds,
  @Column(name: "fraction", precision: 3, scale: 5)
  required final Decimal fraction,
  @Column(name: "defaulted", precision: 5, scale: 2)
  @DatabaseDefault.sql("'1.235'")
  required final Decimal defaulted,
  @Column(name: "optional", precision: 5, scale: 2)
  required final Decimal? optional,
});

@Model(table: "prices")
@Relation(
  target: Receipt,
  name: "receipts",
  fields: ["id"],
  keys: ["priceId"],
  constraint: false,
)
final class Price({
  @Id(generated: false)
  @Column(name: "id", precision: 4, scale: 2)
  required final Decimal id,
  @Column(name: "label") required final String label,
});

@Model(table: "receipts")
@Relation(
  target: Price,
  name: "price",
  fields: ["priceId"],
  keys: ["id"],
  onDelete: .restrict,
)
final class Receipt({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "price_id", precision: 4, scale: 2)
  required final Decimal priceId,
});
