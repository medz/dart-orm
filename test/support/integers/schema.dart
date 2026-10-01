import 'package:orm/schema.dart';

@Model(table: "samples")
@Relation(
  target: Owner,
  name: "owners",
  fields: ["id"],
  keys: ["sampleId"],
  constraint: false,
)
final class Sample({
  @Id(generated: true) @Column(name: "id", bits: 32) required final int id,
  @Column(name: "small", bits: 16) required final int small,
  @Column(name: "medium", bits: 32) required final int medium,
  @Column(name: "large") required final int large,
  @Column(name: "optional", bits: 16) required final int? optional,
});

@Model(table: "owners")
@Relation(
  target: Sample,
  name: "sample",
  fields: ["sampleId"],
  keys: ["id"],
  onDelete: .restrict,
)
final class Owner({
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "sample_id", bits: 32) required final int sampleId,
});
