// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/orm.dart';

import "schema.dart" as models;
export "schema.dart" show User, Team, Membership;

final _usersId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _usersName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final usersSchema = TableSchema(
  "users",
  columns: [_usersId, _usersName],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class UsersFields extends Fields {
  UsersFields(super.table);
  late final id = column(_usersId);
  late final name = column(_usersName);
  Relation<models.Membership, MembershipsFields> get memberships =>
      Relation(membershipsTable, parent: [id], child: (row) => [row.userId]);
}

final usersTable = Table<models.User, UsersFields>(
  usersSchema,
  UsersFields.new,
  (row) => (row.id, row.name).map((id, name) => (id: id, name: name)),
);

final class UsersTableSet extends TableSet<models.User, UsersFields> {
  UsersTableSet(Database<Backend> db) : super(db, usersTable) {
    db.registerSchema(appSchema);
  }
  Future<models.User> create({required int id, required String name}) =>
      createRow((row) => [row.id.set(id), row.name.set(name)]);
  Query<models.User, UsersFields> byId(int id) => where((row) => row.id.eq(id));
}

extension UsersUpdates on Query<models.User, UsersFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<String> name = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.name.change(name)])
          .execute();
}

final _teamsId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _teamsName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final teamsSchema = TableSchema(
  "teams",
  columns: [_teamsId, _teamsName],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class TeamsFields extends Fields {
  TeamsFields(super.table);
  late final id = column(_teamsId);
  late final name = column(_teamsName);
  Relation<models.Membership, MembershipsFields> get memberships =>
      Relation(membershipsTable, parent: [id], child: (row) => [row.teamId]);
}

final teamsTable = Table<models.Team, TeamsFields>(
  teamsSchema,
  TeamsFields.new,
  (row) => (row.id, row.name).map((id, name) => (id: id, name: name)),
);

final class TeamsTableSet extends TableSet<models.Team, TeamsFields> {
  TeamsTableSet(Database<Backend> db) : super(db, teamsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Team> create({required int id, required String name}) =>
      createRow((row) => [row.id.set(id), row.name.set(name)]);
  Query<models.Team, TeamsFields> byId(int id) => where((row) => row.id.eq(id));
}

extension TeamsUpdates on Query<models.Team, TeamsFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<String> name = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.name.change(name)])
          .execute();
}

final _membershipsTeamId = Column<int>(
  "team_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _membershipsUserId = Column<int>(
  "user_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _membershipsRole = Column<models.MembershipRole>(
  "role",
  Codecs.enumeration<models.MembershipRole>({
    models.MembershipRole.owner: "owner",
    models.MembershipRole.member: "member",
  }),
  nullable: false,
  generated: false,
  defaultSql: "'member'",
);
final _membershipsJoinedAt = Column<DateTime>(
  "joined_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
);
final membershipsSchema = TableSchema(
  "memberships",
  columns: [
    _membershipsTeamId,
    _membershipsUserId,
    _membershipsRole,
    _membershipsJoinedAt,
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

final class MembershipsFields extends Fields {
  MembershipsFields(super.table);
  late final teamId = column(_membershipsTeamId);
  late final userId = column(_membershipsUserId);
  late final role = column(_membershipsRole);
  late final joinedAt = column(_membershipsJoinedAt);
  Relation<models.Team, TeamsFields> get team =>
      Relation(teamsTable, parent: [teamId], child: (row) => [row.id]);
  Relation<models.User, UsersFields> get user =>
      Relation(usersTable, parent: [userId], child: (row) => [row.id]);
}

final membershipsTable = Table<models.Membership, MembershipsFields>(
  membershipsSchema,
  MembershipsFields.new,
  (row) => (row.teamId, row.userId, row.role, row.joinedAt).map(
    (teamId, userId, role, joinedAt) =>
        (teamId: teamId, userId: userId, role: role, joinedAt: joinedAt),
  ),
);

final class MembershipsTableSet
    extends TableSet<models.Membership, MembershipsFields> {
  MembershipsTableSet(Database<Backend> db) : super(db, membershipsTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Membership> create({
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
  Query<models.Membership, MembershipsFields> byId({
    required int teamId,
    required int userId,
  }) => where((row) => row.teamId.eq(teamId).and(row.userId.eq(userId)));
}

extension MembershipsUpdates on Query<models.Membership, MembershipsFields> {
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
  usersSchema,
  teamsSchema,
  membershipsSchema,
]);

extension AppTables<B extends Backend> on Database<B> {
  UsersTableSet get users => UsersTableSet(this);
  TeamsTableSet get teams => TeamsTableSet(this);
  MembershipsTableSet get memberships => MembershipsTableSet(this);
}
