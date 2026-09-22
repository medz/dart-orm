// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "schema.dart" as models;
export "schema.dart" show MembershipRole;

/// A complete immutable row from "users".
final class User({required final int id, required final String name});
final _userId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _userName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final userSchema = TableSchema(
  "users",
  columns: [_userId, _userName],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class UserFields extends Fields {
  UserFields(super.table);
  late final id = column(_userId);
  late final name = column(_userName);
  Relation<Membership, MembershipFields> get memberships =>
      Relation(membershipTable, parent: [id], child: (row) => [row.userId]);
}

final userTable = Table<User, UserFields>(
  userSchema,
  UserFields.new,
  (row) => (row.id, row.name).map((v0, v1) => User(id: v0, name: v1)),
);

final class UserTableSet extends TableSet<User, UserFields> {
  UserTableSet(QueryContext db) : super(db, userTable) {
    db.registerSchema(appSchema);
  }
  Future<User> create({required int id, required String name}) =>
      createRow((row) => [row.id.set(id), row.name.set(name)]);
  Query<User, UserFields> byId(int id) => where((row) => row.id.eq(id));
}

extension UserUpdates on Query<User, UserFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<String> name = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.name.change(name)])
          .execute();
}

/// A complete immutable row from "teams".
final class Team({required final int id, required final String name});
final _teamId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _teamName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final teamSchema = TableSchema(
  "teams",
  columns: [_teamId, _teamName],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class TeamFields extends Fields {
  TeamFields(super.table);
  late final id = column(_teamId);
  late final name = column(_teamName);
  Relation<Membership, MembershipFields> get memberships =>
      Relation(membershipTable, parent: [id], child: (row) => [row.teamId]);
}

final teamTable = Table<Team, TeamFields>(
  teamSchema,
  TeamFields.new,
  (row) => (row.id, row.name).map((v0, v1) => Team(id: v0, name: v1)),
);

final class TeamTableSet extends TableSet<Team, TeamFields> {
  TeamTableSet(QueryContext db) : super(db, teamTable) {
    db.registerSchema(appSchema);
  }
  Future<Team> create({required int id, required String name}) =>
      createRow((row) => [row.id.set(id), row.name.set(name)]);
  Query<Team, TeamFields> byId(int id) => where((row) => row.id.eq(id));
}

extension TeamUpdates on Query<Team, TeamFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<String> name = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.name.change(name)])
          .execute();
}

/// A complete immutable row from "memberships".
final class Membership({
  required final int teamId,
  required final int userId,
  required final models.MembershipRole role,
  required final DateTime joinedAt,
});
final _membershipTeamId = Column<int>(
  "team_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _membershipUserId = Column<int>(
  "user_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _membershipRole = Column<models.MembershipRole>(
  "role",
  Codecs.enumeration<models.MembershipRole>({
    models.MembershipRole.owner: "owner",
    models.MembershipRole.member: "member",
  }),
  nullable: false,
  generated: false,
  defaultSql: "'member'",
);
final _membershipJoinedAt = Column<DateTime>(
  "joined_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final membershipSchema = TableSchema(
  "memberships",
  columns: [
    _membershipTeamId,
    _membershipUserId,
    _membershipRole,
    _membershipJoinedAt,
  ],
  primaryKey: ["team_id", "user_id"],
  uniqueKeys: [],
  indexes: [
    IndexSchema("user_memberships", [
      "user_id",
      "joined_at",
      "team_id",
    ], unique: false),
  ],
  foreignKeys: [
    ForeignKey(["team_id"], "teams", ["id"], onDelete: "CASCADE"),
    ForeignKey(["user_id"], "users", ["id"], onDelete: "CASCADE"),
  ],
);

final class MembershipFields extends Fields {
  MembershipFields(super.table);
  late final teamId = column(_membershipTeamId);
  late final userId = column(_membershipUserId);
  late final role = column(_membershipRole);
  late final joinedAt = column(_membershipJoinedAt);
  Relation<Team, TeamFields> get team =>
      Relation(teamTable, parent: [teamId], child: (row) => [row.id]);
  Relation<User, UserFields> get user =>
      Relation(userTable, parent: [userId], child: (row) => [row.id]);
}

final membershipTable = Table<Membership, MembershipFields>(
  membershipSchema,
  MembershipFields.new,
  (row) => (row.teamId, row.userId, row.role, row.joinedAt).map(
    (v0, v1, v2, v3) =>
        Membership(teamId: v0, userId: v1, role: v2, joinedAt: v3),
  ),
);

final class MembershipTableSet extends TableSet<Membership, MembershipFields> {
  MembershipTableSet(QueryContext db) : super(db, membershipTable) {
    db.registerSchema(appSchema);
  }
  Future<Membership> create({
    required int teamId,
    required int userId,
    Change<models.MembershipRole> role = const Change.keep(),
    required DateTime joinedAt,
  }) => createRow(
    (row) => [
      row.teamId.set(teamId),
      row.userId.set(userId),
      ...row.role.change(role),
      row.joinedAt.set(joinedAt),
    ],
  );
  Query<Membership, MembershipFields> byId({
    required int teamId,
    required int userId,
  }) =>
      where((row) => orm.allOf([row.teamId.eq(teamId), row.userId.eq(userId)]));
}

extension MembershipUpdates on Query<Membership, MembershipFields> {
  Future<int> patch({
    Change<int> teamId = const Change.keep(),
    Change<int> userId = const Change.keep(),
    Change<models.MembershipRole> role = const Change.keep(),
    Change<DateTime> joinedAt = const Change.keep(),
  }) => update(
    (row) => [
      ...row.teamId.change(teamId),
      ...row.userId.change(userId),
      ...row.role.change(role),
      ...row.joinedAt.change(joinedAt),
    ],
  ).execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  userSchema,
  teamSchema,
  membershipSchema,
]);

extension AppTables on QueryContext {
  UserTableSet get user => UserTableSet(this);
  TeamTableSet get team => TeamTableSet(this);
  MembershipTableSet get membership => MembershipTableSet(this);
}
