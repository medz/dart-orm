import 'package:orm/schema.dart';

import 'roles.dart' as roles;
export 'roles.dart';
export 'cards.dart';

int samples = 0;
int nextStamp() => ++samples;

@Model(table: 'users')
final class User({
  @Id(generated: true) required final int id,
  required final String email,
  required final String name,
  required final String? nickname,
  @ClientDefault(nextStamp) required final int stamp,
});

@Model(table: 'teams')
final class Team({
  @Id(generated: true) required final int id,
  required final String name,
  @Relation(target: User, name: 'owner', onDelete: .setNull)
  required final int? ownerId,
});

@Model(table: 'memberships')
final class Membership({
  @Id()
  @Relation(target: Team, name: 'team', inverse: 'members')
  required final int teamId,
  @Id()
  @Relation(target: User, name: 'user', inverse: 'memberships')
  required final int userId,
  @DatabaseDefault(roles.Role.member) required final roles.Role role,
});
