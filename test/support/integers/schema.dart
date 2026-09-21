import 'package:orm/schema.dart';

final Model sample = model("samples", (
  id: integer(bits: 32).identity(),
  small: integer(bits: 16),
  medium: integer(bits: 32),
  large: integer(),
  optional: integer(bits: 16).nullable(),
), relations: (r) => (owners: referencedBy(() => owner, on: (sampleId: r.id))));

final Model owner = model(
  "owners",
  (id: integer(), sampleId: integer(bits: 32)),
  primaryKey: (r) => r.id,
  relations: (r) =>
      (sample: references((id: r.sampleId), () => sample, onDelete: .restrict)),
);
