// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "schema.dart" as models;
export "schema.dart" show User, Team, MembershipRole, Membership;

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
  Relation<models.Team, TeamFields> get team =>
      Relation(teamTable, parent: [teamId], child: (row) => [row.id]);
  Relation<models.User, UserFields> get user =>
      Relation(userTable, parent: [userId], child: (row) => [row.id]);
}

final membershipTable = Table<models.Membership, MembershipFields>(
  membershipSchema,
  MembershipFields.new,
  (row) => (row.teamId, row.userId, row.role, row.joinedAt).map(
    (v0, v1, v2, v3) =>
        models.Membership(teamId: v0, userId: v1, role: v2, joinedAt: v3),
  ),
);

final class MembershipTableSet
    extends TableSet<models.Membership, MembershipFields> {
  MembershipTableSet(QueryContext db) : super(db, membershipTable) {
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
  Query<models.Membership, MembershipFields> byId({
    required int teamId,
    required int userId,
  }) => where(
    (row) => orm.allOf([
      row.teamId.eq(.value(teamId)),
      row.userId.eq(.value(userId)),
    ]),
  );
}

extension MembershipUpdates on Query<models.Membership, MembershipFields> {
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

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Membership, MembershipFields> get memberships =>
      Relation(membershipTable, parent: [id], child: (row) => [row.teamId]);
}

final teamTable = Table<models.Team, TeamFields>(
  teamSchema,
  TeamFields.new,
  (row) => (row.id, row.name).map((v0, v1) => models.Team(id: v0, name: v1)),
);

final class TeamTableSet extends TableSet<models.Team, TeamFields> {
  TeamTableSet(QueryContext db) : super(db, teamTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Team> create({required int id, required String name}) =>
      createRow((row) => [row.id.set(id), row.name.set(name)]);
  Query<models.Team, TeamFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension TeamUpdates on Query<models.Team, TeamFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<String> name = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.name.change(name)])
          .execute();
}

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

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Membership, MembershipFields> get memberships =>
      Relation(membershipTable, parent: [id], child: (row) => [row.userId]);
}

final userTable = Table<models.User, UserFields>(
  userSchema,
  UserFields.new,
  (row) => (row.id, row.name).map((v0, v1) => models.User(id: v0, name: v1)),
);

final class UserTableSet extends TableSet<models.User, UserFields> {
  UserTableSet(QueryContext db) : super(db, userTable) {
    db.registerSchema(appSchema);
  }
  Future<models.User> create({required int id, required String name}) =>
      createRow((row) => [row.id.set(id), row.name.set(name)]);
  Query<models.User, UserFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension UserUpdates on Query<models.User, UserFields> {
  Future<int> patch({
    Change<int> id = const Change.keep(),
    Change<String> name = const Change.keep(),
  }) =>
      update((row) => [...row.id.change(id), ...row.name.change(name)])
          .execute();
}

final appSchema = List<TableSchema>.unmodifiable([
  membershipSchema,
  teamSchema,
  userSchema,
]);

extension AppTables on QueryContext {
  MembershipTableSet get membership => MembershipTableSet(this);
  TeamTableSet get team => TeamTableSet(this);
  UserTableSet get user => UserTableSet(this);
}
