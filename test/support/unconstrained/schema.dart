import 'package:orm/schema.dart';

@Model(table: "accounts")
@Relation(
  target: Entry,
  name: "entries",
  fields: ["tenant", "id"],
  keys: ["tenant", "owner"],
  constraint: false,
)
@Relation(
  target: Entry,
  name: "matches",
  fields: ["tenant", "label"],
  keys: ["tenant", "label"],
  constraint: false,
)
@Relation(
  target: Account,
  name: "manager",
  fields: ["tenant", "managerId"],
  keys: ["tenant", "id"],
  constraint: false,
)
@Relation(
  target: Account,
  name: "reports",
  fields: ["tenant", "id"],
  keys: ["tenant", "managerId"],
  constraint: false,
)
final class Account({
  @Id(generated: false) @Column(name: "tenant") required final int tenant,
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "display_label") required final String? label,
  @Column(name: "manager_id") required final int? managerId,
});

@Model(table: "entries")
@Relation(
  target: Account,
  name: "ownerAccount",
  fields: ["tenant", "owner"],
  keys: ["tenant", "id"],
  constraint: false,
)
@Relation(
  target: Account,
  name: "matchingAccounts",
  fields: ["tenant", "label"],
  keys: ["tenant", "label"],
  constraint: false,
)
final class Entry({
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "tenant") required final int? tenant,
  @Column(name: "owner") required final int? owner,
  @Column(name: "lookup_label") required final String? label,
});

@Model(table: "readings")
@Relation(
  target: Reading,
  name: "peers",
  fields: ["value"],
  keys: ["value"],
  constraint: false,
)
final class Reading({
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "value") required final double value,
});
