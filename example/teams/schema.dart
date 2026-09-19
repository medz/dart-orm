import 'package:orm/schema.dart';

typedef User = ({@Id() int id, String name});
typedef Team = ({@Id() int id, String name});

enum MembershipRole { owner, member }

typedef Membership = ({
  int teamId,
  int userId,
  @Default.sql("'member'") MembershipRole role,
  DateTime joinedAt,
});

final users = entity<User>();
final teams = entity<Team>();
final memberships = entity<Membership>();
final membershipKey = memberships.primaryKey((m) => (m.teamId, m.userId));
final team = memberships
    .key((m) => m.teamId)
    .references(
      teams.key((t) => t.id),
      inverse: 'memberships',
      onDelete: .cascade,
    );
final user = memberships
    .key((m) => m.userId)
    .references(
      users.key((u) => u.id),
      inverse: 'memberships',
      onDelete: .cascade,
    );
final userMemberships = memberships.index(
  (m) => (m.userId, m.joinedAt, m.teamId),
);
