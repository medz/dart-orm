import 'package:orm/schema.dart';

typedef Wallet = ({
  @Id.generated() int id,
  @DecimalDigits(5, 2) Decimal amount,
  @DecimalDigits(3, -2) Decimal hundreds,
  @DecimalDigits(3, 5) Decimal fraction,
  @DecimalDigits(5, 2) @Default.sql("'1.235'") Decimal defaulted,
  @DecimalDigits(5, 2) Decimal? optional,
});
typedef Price = ({@Id() @DecimalDigits(4, 2) Decimal id, String label});
typedef Receipt = ({
  @Id.generated() int id,
  @DecimalDigits(4, 2) Decimal priceId,
});
final wallets = entity<Wallet>();
final prices = entity<Price>();
final receipts = entity<Receipt>();
final price = receipts
    .key((r) => r.priceId)
    .references(prices.key((p) => p.id), inverse: 'receipts');
