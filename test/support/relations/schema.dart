import 'package:orm/schema.dart';

@Model(table: "accounts")
@Relation(
  target: Account,
  name: "manager",
  fields: ["tenant", "managerId"],
  keys: ["tenant", "id"],
  onDelete: .restrict,
)
@Relation(
  target: Account,
  name: "reports",
  fields: ["tenant", "id"],
  keys: ["tenant", "managerId"],
  constraint: false,
)
@Relation(
  target: Event,
  name: "events",
  fields: ["tenant", "id"],
  keys: ["tenant", "owner"],
  constraint: false,
)
@Relation(
  target: Event,
  name: "reviews",
  fields: ["tenant", "id"],
  keys: ["tenant", "reviewer"],
  constraint: false,
)
final class Account({
  @Id(generated: false) @Column(name: "tenant") required final int tenant,
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "label") required final String? label,
  @Column(name: "note") required final String? note,
  @Column(name: "manager_id") required final int? managerId,
  @Column(name: "_ORM_PRESENT") required final String? marker,
});

@Model(table: "events")
@Relation(
  target: Account,
  name: "author",
  fields: ["tenant", "owner"],
  keys: ["tenant", "id"],
  onDelete: .restrict,
)
@Relation(
  target: Account,
  name: "reviewerAccount",
  fields: ["tenant", "reviewer"],
  keys: ["tenant", "id"],
  onDelete: .restrict,
)
final class Event({
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "tenant") required final int? tenant,
  @Column(name: "owner") required final int? owner,
  @Column(name: "reviewer") required final int? reviewer,
  @Column(name: "title") required final String title,
  @Column(name: "score") required final int score,
});
