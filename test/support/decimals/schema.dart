import 'package:orm/schema.dart';

@Model(table: "entries")
final class Entry({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "amount") required final Decimal amount,
  @Column(name: "fee") required final Decimal? fee,
  @Column(name: "tax")
  @DatabaseDefault.sql("'0.10'")
  required final Decimal tax,
  @Column(name: "bucket") required final String bucket,
});

@Model(table: "rates")
@Relation(
  target: Allocation,
  name: "allocations",
  fields: ["id"],
  keys: ["rateId"],
  constraint: false,
)
final class Rate({
  @Id(generated: false) @Column(name: "id") required final Decimal id,
  @Column(name: "label") required final String label,
});

@Model(table: "allocations")
@Relation(
  target: Rate,
  name: "rate",
  fields: ["rateId"],
  keys: ["id"],
  onDelete: .restrict,
)
final class Allocation({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "rate_id") required final Decimal rateId,
});
