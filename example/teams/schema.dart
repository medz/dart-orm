import 'package:orm/schema.dart';

enum MembershipRole { owner, member }

@Model(table: "users")
@Relation(
  target: Membership,
  name: "memberships",
  fields: ["id"],
  keys: ["userId"],
  constraint: false,
)
final class User({
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "name") required final String name,
});

@Model(table: "teams")
@Relation(
  target: Membership,
  name: "memberships",
  fields: ["id"],
  keys: ["teamId"],
  constraint: false,
)
final class Team({
  @Id(generated: false) @Column(name: "id") required final int id,
  @Column(name: "name") required final String name,
});

@Model(table: "memberships")
@Index(
  ["userId", "joinedAt", "teamId"],
  name: "user_memberships",
  unique: false,
)
@Relation(
  target: Team,
  name: "team",
  fields: ["teamId"],
  keys: ["id"],
  onDelete: .cascade,
)
@Relation(
  target: User,
  name: "user",
  fields: ["userId"],
  keys: ["id"],
  onDelete: .cascade,
)
final class Membership({
  @Id(generated: false) @Column(name: "team_id") required final int teamId,
  @Id(generated: false) @Column(name: "user_id") required final int userId,
  @Column(
    name: "role",
    labels: {MembershipRole.owner: "owner", MembershipRole.member: "member"},
  )
  @DatabaseDefault.sql("'member'")
  required final MembershipRole role,
  @Column(name: "joined_at") required final DateTime joinedAt,
});
