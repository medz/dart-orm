import 'package:orm/schema.dart';

typedef Entry = ({
  @Id.generated() int id,
  Decimal amount,
  Decimal? fee,
  @Default.sql("'0.10'") Decimal tax,
  String bucket,
});
typedef Rate = ({@Id() Decimal id, String label});
typedef Allocation = ({@Id.generated() int id, Decimal rateId});
final entries = entity<Entry>();
final rates = entity<Rate>();
final allocations = entity<Allocation>();
final rate = allocations
    .key((a) => a.rateId)
    .references(rates.key((r) => r.id), inverse: 'allocations');
