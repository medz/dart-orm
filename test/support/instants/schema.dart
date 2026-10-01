import 'package:orm/schema.dart';

@Model(table: "events")
final class Event({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "at") required final DateTime at,
  @Column(name: "created")
  @DatabaseDefault.sql("CURRENT_TIMESTAMP")
  required final DateTime created,
  @Column(name: "optional") required final DateTime? optional,
});

@Model(table: "moments")
@Relation(
  target: Link,
  name: "links",
  fields: ["at"],
  keys: ["at"],
  constraint: false,
)
final class Moment({
  @Id(generated: false) @Column(name: "at") required final DateTime at,
  @Column(name: "label")
  @DatabaseDefault.sql("'pending'")
  required final String label,
});

@Model(table: "links")
@Relation(
  target: Moment,
  name: "moment",
  fields: ["at"],
  keys: ["at"],
  onDelete: .restrict,
)
final class Link({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "at") required final DateTime at,
});
