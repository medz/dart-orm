import 'package:orm/schema.dart';

typedef Sample = ({
  @Id.generated() @IntegerBits(32) int id,
  @IntegerBits(16) int small,
  @IntegerBits(32) int medium,
  int large,
  @IntegerBits(16) int? optional,
});

typedef Owner = ({@Id() int id, @IntegerBits(32) int sampleId});

final samples = entity<Sample>();
final owners = entity<Owner>();
final sample = owners
    .key((o) => o.sampleId)
    .references(samples.key((s) => s.id), inverse: 'owners');
