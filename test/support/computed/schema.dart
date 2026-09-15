import 'package:orm/schema.dart';

typedef Line = ({
  @Id.generated() int id,
  int price,
  int quantity,
  String label,
  String? note,
  @Computed.sql('price * quantity') int total,
  @Computed.sql(
    'length(label)',
    postgres: 'char_length(label)',
    storage: ComputedStorage.virtual,
  )
  int labelSize,
  @Computed.sql('upper(note)') String? normalizedNote,
});

final lines = entity<Line>();
final byTotal = lines.index((r) => r.total);
final nonnegative = lines.check('price >= 0 AND quantity >= 0');

typedef Band = ({@Id() int id, String name});
final bands = entity<Band>();
final band = lines
    .key((r) => r.total)
    .relatesTo(bands.key((b) => b.id), inverse: 'lines');
