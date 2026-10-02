import 'package:orm/schema.dart';

import 'roles.dart';

@Projection()
final class UserCard({required final int id, required final String name}) {
  String get label => '$id: $name';
}

@Projection()
final class MemberCard({
  required final UserCard user,
  required final Role role,
});
@Projection()
final class TeamView({
  required final int id,
  required final String name,
  required final UserCard? owner,
  required final List<MemberCard> members,
});
