import 'package:orm/driver.dart';
import 'package:orm/orm.dart';
import 'package:orm/sql.dart';

import 'models.orm.dart';

Selection<UserCard> person(UserFields u) => userCard(id: u.id, name: u.name);

// Scenario 1: filtered teams, stable outer and per-team member pagination,
// partial user DTOs, nullable owners, observable batched relation loading.
Query<TeamView, TeamFields> membershipPage(
  Database<Backend> db, {
  required String search,
  required int page,
  required int membersOffset,
}) => db.team
    .where(
      (t) => t.members
          .where((m) => m.user.where((u) => u.name.contains(search)).any())
          .any(),
    )
    .orderBy((t) => [t.id.asc()])
    .skip(page * 10)
    .take(10)
    .select(
      (t) => teamView(
        id: t.id,
        name: t.name,
        owner: t.owner.select(person).one(),
        members: t.members
            .where((m) => m.user.where((u) => u.name.contains(search)).any())
            .orderBy((m) => [m.userId.asc()])
            .skip(membersOffset)
            .take(2)
            .select(
              (m) => memberCard(
                user: m.user.select(person).required(),
                role: m.role,
              ),
            )
            .many(),
      ),
    );

// Scenario 2: an HTTP-style partial profile plus a policy patch, applied with
// membership changes and an audit record in one explicit transaction.
UserPatch profilePatch(Map<String, Object?> input) {
  var patch = userPatch();
  if (input.containsKey('name')) {
    patch = userPatch.overlay([
      patch,
      userPatch(name: input['name'] as String),
    ]);
  }
  if (input.containsKey('nickname')) {
    patch = userPatch.overlay([
      patch,
      userPatch(nickname: input['nickname'] as String?),
    ]);
  }
  return patch;
}

Future<UserCard> changeMembership(
  Database<Backend> db, {
  required int userId,
  required int teamId,
  required Map<String, Object?> profile,
  required UserPatch policy,
  required UserPatch sessionPolicy,
  ExecutionOptions options = const ExecutionOptions(),
}) => db.transaction((tx) async {
  final patch = userPatch.overlay([
    profilePatch(profile),
    policy,
    sessionPolicy,
  ]);
  if (!userPatch.isEmpty(patch)) {
    await tx.user.byId(userId).update(patch, options: options);
  }
  await tx.membership
      .byId(teamId: teamId, userId: userId)
      .update(membershipPatch(role: Role.owner), options: options);
  await tx.sql.raw(
    Sql(
      'INSERT INTO audit (user_id, action) VALUES (:id, :action)',
      parameters: {'id': userId, 'action': 'membership changed'},
    ),
    options: options,
  );
  return tx.user.byId(userId).select(person).single(options: options);
});
