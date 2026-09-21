import 'package:orm/schema.dart';

enum MembershipRole { owner, member }

final Model user = model(
  'users',
  (id: integer(), name: text()),
  primaryKey: (u) => u.id,
  relations: (u) => (memberships: referencedBy(() => membership)),
);

final Model team = model(
  'teams',
  (id: integer(), name: text()),
  primaryKey: (t) => t.id,
  relations: (t) => (memberships: referencedBy(() => membership)),
);

final membership = model(
  'memberships',
  (
    teamId: integer(),
    userId: integer(),
    role: enumeration(
      MembershipRole.values,
      defaultValue: MembershipRole.member,
    ),
    joinedAt: dateTime(),
  ),
  primaryKey: (m) => (m.teamId, m.userId),
  indexes: (m) => [
    index((m.userId, m.joinedAt, m.teamId), name: 'user_memberships'),
  ],
  relations: (m) => (
    team: references(m.teamId, () => team, onDelete: .cascade),
    user: references(m.userId, () => user, onDelete: .cascade),
  ),
);
