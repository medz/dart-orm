// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/sql.dart'
    as orm_projection
    show Slot, ProjectionType, ProjectionOutput, ProjectionFields, Projection;
import 'package:orm/values.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "models.dart" as models;
export "models.dart" show User, Team, Membership;
export "roles.dart" show Role;
export "cards.dart" show UserCard, MemberCard, TeamView;
import "roles.dart" as types0;
import "cards.dart" as types1;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

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
final _membershipRole = Column<types0.Role>(
  "role",
  Codecs.enumeration<types0.Role>({
    types0.Role.owner: "owner",
    types0.Role.member: "member",
  }),
  nullable: false,
  generated: false,
  defaultSql: "'member'",
);
final membershipSchema = TableSchema(
  "memberships",
  columns: [_membershipTeamId, _membershipUserId, _membershipRole],
  primaryKey: ["team_id", "user_id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["team_id"], "teams", ["id"], onDelete: "RESTRICT"),
    ForeignKey(["user_id"], "users", ["id"], onDelete: "RESTRICT"),
  ],
);

final class MembershipFields extends Fields {
  MembershipFields(super.table);
  late final teamId = column(_membershipTeamId);
  late final userId = column(_membershipUserId);
  late final role = column(_membershipRole);
  Relation<models.Team, TeamFields> get team =>
      Relation(teamTable, parent: [teamId], child: (row) => [row.id]);
  Relation<models.User, UserFields> get user =>
      Relation(userTable, parent: [userId], child: (row) => [row.id]);
}

final membershipTable = Table<models.Membership, MembershipFields>(
  membershipSchema,
  MembershipFields.new,
  (row) => (
    row.teamId,
    row.userId,
    row.role,
  ).map((v0, v1, v2) => models.Membership(teamId: v0, userId: v1, role: v2)),
);

/// Immutable input data; composition belongs to [membershipPatch], not field names.
final class MembershipPatch {
  final WriteValue<int, MembershipFields> teamId;
  final WriteValue<int, MembershipFields> userId;
  final WriteValue<types0.Role, MembershipFields> role;
  MembershipPatch._({
    required this.teamId,
    required this.userId,
    required this.role,
  });

  List<Assignment> _assignments(MembershipFields fields) => [
    ...fields.teamId.write(teamId, fields),
    ...fields.userId.write(userId, fields),
    ...fields.role.write(role, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class MembershipPatchFactory {
  MembershipPatch call({int teamId, int userId, types0.Role role});
  MembershipPatch values({
    WriteValue<int, MembershipFields> teamId = const .keep(),
    WriteValue<int, MembershipFields> userId = const .keep(),
    WriteValue<types0.Role, MembershipFields> role = const .keep(),
  });
  MembershipPatch overlay(Iterable<MembershipPatch> layers);
  bool isEmpty(MembershipPatch input);
}

const MembershipPatchFactory membershipPatch = _MembershipPatchFactory();

final class _MembershipPatchFactory implements MembershipPatchFactory {
  const _MembershipPatchFactory();
  @override
  MembershipPatch call({
    Object? teamId = _writeAbsent,
    Object? userId = _writeAbsent,
    Object? role = _writeAbsent,
  }) => MembershipPatch._(
    teamId: _writeLiteral<int, MembershipFields>(teamId),
    userId: _writeLiteral<int, MembershipFields>(userId),
    role: _writeLiteral<types0.Role, MembershipFields>(role),
  );
  @override
  MembershipPatch values({
    WriteValue<int, MembershipFields> teamId = const .keep(),
    WriteValue<int, MembershipFields> userId = const .keep(),
    WriteValue<types0.Role, MembershipFields> role = const .keep(),
  }) => MembershipPatch._(teamId: teamId, userId: userId, role: role);
  @override
  MembershipPatch overlay(Iterable<MembershipPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = MembershipPatch._(
        teamId: WriteValue.overlay(earlier.teamId, later.teamId),
        userId: WriteValue.overlay(earlier.userId, later.userId),
        role: WriteValue.overlay(earlier.role, later.role),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(MembershipPatch input) =>
      input.teamId.isMissing && input.userId.isMissing && input.role.isMissing;
}

/// Immutable input data; composition belongs to [membershipInsert], not field names.
final class MembershipInsert {
  final WriteValue<int, MembershipFields> teamId;
  final WriteValue<int, MembershipFields> userId;
  final WriteValue<types0.Role, MembershipFields> role;
  MembershipInsert._({
    required this.teamId,
    required this.userId,
    required this.role,
  }) {
    if (teamId.isMissing) {
      throw ArgumentError.value(teamId, 'teamId', 'Must be supplied.');
    }
    if (userId.isMissing) {
      throw ArgumentError.value(userId, 'userId', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(MembershipFields fields) => [
    ...fields.teamId.write(teamId, fields),
    ...fields.userId.write(userId, fields),
    ...fields.role.write(role, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class MembershipInsertFactory {
  MembershipInsert call({
    required int teamId,
    required int userId,
    types0.Role role,
  });
  MembershipInsert values({
    required WriteValue<int, MembershipFields> teamId,
    required WriteValue<int, MembershipFields> userId,
    WriteValue<types0.Role, MembershipFields> role = const .keep(),
  });
  MembershipInsert overlay(
    MembershipInsert earlier,
    Iterable<MembershipPatch> layers,
  );
}

const MembershipInsertFactory membershipInsert = _MembershipInsertFactory();

final class _MembershipInsertFactory implements MembershipInsertFactory {
  const _MembershipInsertFactory();
  @override
  MembershipInsert call({
    required int teamId,
    required int userId,
    Object? role = _writeAbsent,
  }) => MembershipInsert._(
    teamId: .set(teamId),
    userId: .set(userId),
    role: _writeLiteral<types0.Role, MembershipFields>(role),
  );
  @override
  MembershipInsert values({
    required WriteValue<int, MembershipFields> teamId,
    required WriteValue<int, MembershipFields> userId,
    WriteValue<types0.Role, MembershipFields> role = const .keep(),
  }) => MembershipInsert._(teamId: teamId, userId: userId, role: role);
  @override
  MembershipInsert overlay(
    MembershipInsert earlier,
    Iterable<MembershipPatch> layers,
  ) {
    for (final later in layers) {
      earlier = MembershipInsert._(
        teamId: WriteValue.overlay(earlier.teamId, later.teamId),
        userId: WriteValue.overlay(earlier.userId, later.userId),
        role: WriteValue.overlay(earlier.role, later.role),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Membership from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class MembershipCreator {
  Future<models.Membership> call({
    required int teamId,
    required int userId,
    types0.Role role,
  });
}

final class _MembershipCreator implements MembershipCreator {
  final MembershipTableSet _table;
  const _MembershipCreator(this._table);
  @override
  Future<models.Membership> call({
    required int teamId,
    required int userId,
    Object? role = _writeAbsent,
  }) async => _table.plan
      .insert(
        MembershipInsert._(
          teamId: .set(teamId),
          userId: .set(userId),
          role: _writeLiteral<types0.Role, MembershipFields>(role),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class MembershipPatcher {
  Future<int> call({int teamId, int userId, types0.Role role});
}

final class _MembershipPatcher implements MembershipPatcher {
  final orm_model.ModelQuery<
    models.Membership,
    MembershipFields,
    MembershipPatch
  >
  _query;
  const _MembershipPatcher(this._query);
  @override
  Future<int> call({
    Object? teamId = _writeAbsent,
    Object? userId = _writeAbsent,
    Object? role = _writeAbsent,
  }) => _query.update(
    MembershipPatch._(
      teamId: _writeLiteral<int, MembershipFields>(teamId),
      userId: _writeLiteral<int, MembershipFields>(userId),
      role: _writeLiteral<types0.Role, MembershipFields>(role),
    ),
  );
}

/// Named literal updates on a complete models.Membership query.
extension MembershipWrites
    on
        orm_model.ModelQuery<
          models.Membership,
          MembershipFields,
          MembershipPatch
        > {
  /// Executes one update; omitted fields remain unchanged.
  MembershipPatcher get patch => _MembershipPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class MembershipTableSet
    extends
        orm_model.ModelTable<
          models.Membership,
          MembershipFields,
          MembershipInsert,
          MembershipPatch
        > {
  MembershipTableSet(QueryContext db)
    : super(
        db,
        membershipTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final MembershipCreator create = _MembershipCreator(this);

  orm_model.ModelQuery<models.Membership, MembershipFields, MembershipPatch>
  byId({required int teamId, required int userId}) => where(
    (row) => orm.allOf([
      row.teamId.eq(.value(teamId)),
      row.userId.eq(.value(userId)),
    ]),
  );
}

final _teamId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _teamName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _teamOwnerId = Column<int?>(
  "owner_id",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final teamSchema = TableSchema(
  "teams",
  columns: [_teamId, _teamName, _teamOwnerId],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [
    ForeignKey(["owner_id"], "users", ["id"], onDelete: "SET NULL"),
  ],
);

final class TeamFields extends Fields {
  TeamFields(super.table);
  late final id = column(_teamId);
  late final name = column(_teamName);
  late final ownerId = column(_teamOwnerId);
  Relation<models.User, UserFields> get owner =>
      Relation(userTable, parent: [ownerId], child: (row) => [row.id]);
  Relation<models.Membership, MembershipFields> get members =>
      Relation(membershipTable, parent: [id], child: (row) => [row.teamId]);
}

final teamTable = Table<models.Team, TeamFields>(
  teamSchema,
  TeamFields.new,
  (row) => (
    row.id,
    row.name,
    row.ownerId,
  ).map((v0, v1, v2) => models.Team(id: v0, name: v1, ownerId: v2)),
);

/// Immutable input data; composition belongs to [teamPatch], not field names.
final class TeamPatch {
  final WriteValue<String, TeamFields> name;
  final WriteValue<int?, TeamFields> ownerId;
  TeamPatch._({required this.name, required this.ownerId});

  List<Assignment> _assignments(TeamFields fields) => [
    ...fields.name.write(name, fields),
    ...fields.ownerId.write(ownerId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class TeamPatchFactory {
  TeamPatch call({String name, int? ownerId});
  TeamPatch values({
    WriteValue<String, TeamFields> name = const .keep(),
    WriteValue<int?, TeamFields> ownerId = const .keep(),
  });
  TeamPatch overlay(Iterable<TeamPatch> layers);
  bool isEmpty(TeamPatch input);
}

const TeamPatchFactory teamPatch = _TeamPatchFactory();

final class _TeamPatchFactory implements TeamPatchFactory {
  const _TeamPatchFactory();
  @override
  TeamPatch call({
    Object? name = _writeAbsent,
    Object? ownerId = _writeAbsent,
  }) => TeamPatch._(
    name: _writeLiteral<String, TeamFields>(name),
    ownerId: _writeLiteral<int?, TeamFields>(ownerId),
  );
  @override
  TeamPatch values({
    WriteValue<String, TeamFields> name = const .keep(),
    WriteValue<int?, TeamFields> ownerId = const .keep(),
  }) => TeamPatch._(name: name, ownerId: ownerId);
  @override
  TeamPatch overlay(Iterable<TeamPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = TeamPatch._(
        name: WriteValue.overlay(earlier.name, later.name),
        ownerId: WriteValue.overlay(earlier.ownerId, later.ownerId),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(TeamPatch input) =>
      input.name.isMissing && input.ownerId.isMissing;
}

/// Immutable input data; composition belongs to [teamInsert], not field names.
final class TeamInsert {
  final WriteValue<int, TeamFields> id;
  final WriteValue<String, TeamFields> name;
  final WriteValue<int?, TeamFields> ownerId;
  TeamInsert._({required this.id, required this.name, required this.ownerId}) {
    if (name.isMissing) {
      throw ArgumentError.value(name, 'name', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(TeamFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
    ...fields.ownerId.write(ownerId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class TeamInsertFactory {
  TeamInsert call({int id, required String name, int? ownerId});
  TeamInsert values({
    WriteValue<int, TeamFields> id = const .keep(),
    required WriteValue<String, TeamFields> name,
    WriteValue<int?, TeamFields> ownerId = const .keep(),
  });
  TeamInsert overlay(TeamInsert earlier, Iterable<TeamPatch> layers);
}

const TeamInsertFactory teamInsert = _TeamInsertFactory();

final class _TeamInsertFactory implements TeamInsertFactory {
  const _TeamInsertFactory();
  @override
  TeamInsert call({
    Object? id = _writeAbsent,
    required String name,
    Object? ownerId = _writeAbsent,
  }) => TeamInsert._(
    id: _writeLiteral<int, TeamFields>(id),
    name: .set(name),
    ownerId: _writeLiteral<int?, TeamFields>(ownerId),
  );
  @override
  TeamInsert values({
    WriteValue<int, TeamFields> id = const .keep(),
    required WriteValue<String, TeamFields> name,
    WriteValue<int?, TeamFields> ownerId = const .keep(),
  }) => TeamInsert._(id: id, name: name, ownerId: ownerId);
  @override
  TeamInsert overlay(TeamInsert earlier, Iterable<TeamPatch> layers) {
    for (final later in layers) {
      earlier = TeamInsert._(
        id: earlier.id,
        name: WriteValue.overlay(earlier.name, later.name),
        ownerId: WriteValue.overlay(earlier.ownerId, later.ownerId),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Team from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class TeamCreator {
  Future<models.Team> call({int id, required String name, int? ownerId});
}

final class _TeamCreator implements TeamCreator {
  final TeamTableSet _table;
  const _TeamCreator(this._table);
  @override
  Future<models.Team> call({
    Object? id = _writeAbsent,
    required String name,
    Object? ownerId = _writeAbsent,
  }) async => _table.plan
      .insert(
        TeamInsert._(
          id: _writeLiteral<int, TeamFields>(id),
          name: .set(name),
          ownerId: _writeLiteral<int?, TeamFields>(ownerId),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class TeamPatcher {
  Future<int> call({String name, int? ownerId});
}

final class _TeamPatcher implements TeamPatcher {
  final orm_model.ModelQuery<models.Team, TeamFields, TeamPatch> _query;
  const _TeamPatcher(this._query);
  @override
  Future<int> call({
    Object? name = _writeAbsent,
    Object? ownerId = _writeAbsent,
  }) => _query.update(
    TeamPatch._(
      name: _writeLiteral<String, TeamFields>(name),
      ownerId: _writeLiteral<int?, TeamFields>(ownerId),
    ),
  );
}

/// Named literal updates on a complete models.Team query.
extension TeamWrites
    on orm_model.ModelQuery<models.Team, TeamFields, TeamPatch> {
  /// Executes one update; omitted fields remain unchanged.
  TeamPatcher get patch => _TeamPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class TeamTableSet
    extends
        orm_model.ModelTable<models.Team, TeamFields, TeamInsert, TeamPatch> {
  TeamTableSet(QueryContext db)
    : super(
        db,
        teamTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final TeamCreator create = _TeamCreator(this);

  orm_model.ModelQuery<models.Team, TeamFields, TeamPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final _userId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _userEmail = Column<String>(
  "email",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _userName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _userNickname = Column<String?>(
  "nickname",
  Codecs.text.nullable(),
  nullable: true,
  generated: false,
);
final _userStamp = Column<int>(
  "stamp",
  Codecs.integer,
  nullable: false,
  generated: false,
  clientDefault: models.nextStamp,
);
final userSchema = TableSchema(
  "users",
  columns: [_userId, _userEmail, _userName, _userNickname, _userStamp],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [],
  foreignKeys: [],
);

final class UserFields extends Fields {
  UserFields(super.table);
  late final id = column(_userId);
  late final email = column(_userEmail);
  late final name = column(_userName);
  late final nickname = column(_userNickname);
  late final stamp = column(_userStamp);
  Relation<models.Membership, MembershipFields> get memberships =>
      Relation(membershipTable, parent: [id], child: (row) => [row.userId]);
}

final userTable = Table<models.User, UserFields>(
  userSchema,
  UserFields.new,
  (row) => (row.id, row.email, row.name, row.nickname, row.stamp).map(
    (v0, v1, v2, v3, v4) =>
        models.User(id: v0, email: v1, name: v2, nickname: v3, stamp: v4),
  ),
);

/// Immutable input data; composition belongs to [userPatch], not field names.
final class UserPatch {
  final WriteValue<String, UserFields> email;
  final WriteValue<String, UserFields> name;
  final WriteValue<String?, UserFields> nickname;
  final WriteValue<int, UserFields> stamp;
  UserPatch._({
    required this.email,
    required this.name,
    required this.nickname,
    required this.stamp,
  });

  List<Assignment> _assignments(UserFields fields) => [
    ...fields.email.write(email, fields),
    ...fields.name.write(name, fields),
    ...fields.nickname.write(nickname, fields),
    ...fields.stamp.write(stamp, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserPatchFactory {
  UserPatch call({String email, String name, String? nickname, int stamp});
  UserPatch values({
    WriteValue<String, UserFields> email = const .keep(),
    WriteValue<String, UserFields> name = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<int, UserFields> stamp = const .keep(),
  });
  UserPatch overlay(Iterable<UserPatch> layers);
  bool isEmpty(UserPatch input);
}

const UserPatchFactory userPatch = _UserPatchFactory();

final class _UserPatchFactory implements UserPatchFactory {
  const _UserPatchFactory();
  @override
  UserPatch call({
    Object? email = _writeAbsent,
    Object? name = _writeAbsent,
    Object? nickname = _writeAbsent,
    Object? stamp = _writeAbsent,
  }) => UserPatch._(
    email: _writeLiteral<String, UserFields>(email),
    name: _writeLiteral<String, UserFields>(name),
    nickname: _writeLiteral<String?, UserFields>(nickname),
    stamp: _writeLiteral<int, UserFields>(stamp),
  );
  @override
  UserPatch values({
    WriteValue<String, UserFields> email = const .keep(),
    WriteValue<String, UserFields> name = const .keep(),
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<int, UserFields> stamp = const .keep(),
  }) => UserPatch._(email: email, name: name, nickname: nickname, stamp: stamp);
  @override
  UserPatch overlay(Iterable<UserPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = UserPatch._(
        email: WriteValue.overlay(earlier.email, later.email),
        name: WriteValue.overlay(earlier.name, later.name),
        nickname: WriteValue.overlay(earlier.nickname, later.nickname),
        stamp: WriteValue.overlay(earlier.stamp, later.stamp),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(UserPatch input) =>
      input.email.isMissing &&
      input.name.isMissing &&
      input.nickname.isMissing &&
      input.stamp.isMissing;
}

/// Immutable input data; composition belongs to [userInsert], not field names.
final class UserInsert {
  final WriteValue<int, UserFields> id;
  final WriteValue<String, UserFields> email;
  final WriteValue<String, UserFields> name;
  final WriteValue<String?, UserFields> nickname;
  final WriteValue<int, UserFields> stamp;
  UserInsert._({
    required this.id,
    required this.email,
    required this.name,
    required this.nickname,
    required this.stamp,
  }) {
    if (email.isMissing) {
      throw ArgumentError.value(email, 'email', 'Must be supplied.');
    }
    if (name.isMissing) {
      throw ArgumentError.value(name, 'name', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(UserFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.email.write(email, fields),
    ...fields.name.write(name, fields),
    ...fields.nickname.write(nickname, fields),
    ...fields.stamp.write(stamp, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserInsertFactory {
  UserInsert call({
    int id,
    required String email,
    required String name,
    String? nickname,
    int stamp,
  });
  UserInsert values({
    WriteValue<int, UserFields> id = const .keep(),
    required WriteValue<String, UserFields> email,
    required WriteValue<String, UserFields> name,
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<int, UserFields> stamp = const .keep(),
  });
  UserInsert overlay(UserInsert earlier, Iterable<UserPatch> layers);
}

const UserInsertFactory userInsert = _UserInsertFactory();

final class _UserInsertFactory implements UserInsertFactory {
  const _UserInsertFactory();
  @override
  UserInsert call({
    Object? id = _writeAbsent,
    required String email,
    required String name,
    Object? nickname = _writeAbsent,
    Object? stamp = _writeAbsent,
  }) => UserInsert._(
    id: _writeLiteral<int, UserFields>(id),
    email: .set(email),
    name: .set(name),
    nickname: _writeLiteral<String?, UserFields>(nickname),
    stamp: _writeLiteral<int, UserFields>(stamp),
  );
  @override
  UserInsert values({
    WriteValue<int, UserFields> id = const .keep(),
    required WriteValue<String, UserFields> email,
    required WriteValue<String, UserFields> name,
    WriteValue<String?, UserFields> nickname = const .keep(),
    WriteValue<int, UserFields> stamp = const .keep(),
  }) => UserInsert._(
    id: id,
    email: email,
    name: name,
    nickname: nickname,
    stamp: stamp,
  );
  @override
  UserInsert overlay(UserInsert earlier, Iterable<UserPatch> layers) {
    for (final later in layers) {
      earlier = UserInsert._(
        id: earlier.id,
        email: WriteValue.overlay(earlier.email, later.email),
        name: WriteValue.overlay(earlier.name, later.name),
        nickname: WriteValue.overlay(earlier.nickname, later.nickname),
        stamp: WriteValue.overlay(earlier.stamp, later.stamp),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.User from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class UserCreator {
  Future<models.User> call({
    int id,
    required String email,
    required String name,
    String? nickname,
    int stamp,
  });
}

final class _UserCreator implements UserCreator {
  final UserTableSet _table;
  const _UserCreator(this._table);
  @override
  Future<models.User> call({
    Object? id = _writeAbsent,
    required String email,
    required String name,
    Object? nickname = _writeAbsent,
    Object? stamp = _writeAbsent,
  }) async => _table.plan
      .insert(
        UserInsert._(
          id: _writeLiteral<int, UserFields>(id),
          email: .set(email),
          name: .set(name),
          nickname: _writeLiteral<String?, UserFields>(nickname),
          stamp: _writeLiteral<int, UserFields>(stamp),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class UserPatcher {
  Future<int> call({String email, String name, String? nickname, int stamp});
}

final class _UserPatcher implements UserPatcher {
  final orm_model.ModelQuery<models.User, UserFields, UserPatch> _query;
  const _UserPatcher(this._query);
  @override
  Future<int> call({
    Object? email = _writeAbsent,
    Object? name = _writeAbsent,
    Object? nickname = _writeAbsent,
    Object? stamp = _writeAbsent,
  }) => _query.update(
    UserPatch._(
      email: _writeLiteral<String, UserFields>(email),
      name: _writeLiteral<String, UserFields>(name),
      nickname: _writeLiteral<String?, UserFields>(nickname),
      stamp: _writeLiteral<int, UserFields>(stamp),
    ),
  );
}

/// Named literal updates on a complete models.User query.
extension UserWrites
    on orm_model.ModelQuery<models.User, UserFields, UserPatch> {
  /// Executes one update; omitted fields remain unchanged.
  UserPatcher get patch => _UserPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class UserTableSet
    extends
        orm_model.ModelTable<models.User, UserFields, UserInsert, UserPatch> {
  UserTableSet(QueryContext db)
    : super(
        db,
        userTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final UserCreator create = _UserCreator(this);

  orm_model.ModelQuery<models.User, UserFields, UserPatch> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

final _memberCardSlot0 = orm_projection.Slot<types1.UserCard>("user");
final _memberCardSlot1 = orm_projection.Slot<types0.Role>("role");

final class MemberCardFields extends orm_projection.ProjectionOutput {
  MemberCardFields._(orm_projection.ProjectionFields fields)
    : user = fields.read(_memberCardSlot0),
      role = fields.read(_memberCardSlot1),
      super(fields.table);
  final Expr<types1.UserCard> user;
  final Expr<types0.Role> role;
}

final _memberCardProjection =
    orm_projection.ProjectionType<types1.MemberCard, MemberCardFields>(
      slots: [_memberCardSlot0, _memberCardSlot1],
      assemble: (values) => types1.MemberCard(
        user: values[0] as types1.UserCard,
        role: values[1] as types0.Role,
      ),
      fields: MemberCardFields._,
    );
const memberCard = _MemberCardSelectionFactory();

/// Named result binding; .sql explicitly requires scalar SQL expressions.
final class _MemberCardSelectionFactory {
  const _MemberCardSelectionFactory();
  Selection<types1.MemberCard> call({
    required Selection<types1.UserCard> user,
    required Selection<types0.Role> role,
  }) => (user, role)
      .map((v0, v1) => (user: v0, role: v1))
      .map((result) => types1.MemberCard(user: result.user, role: result.role));
  orm_projection.Projection<types1.MemberCard, MemberCardFields> sql({
    required Expr<types1.UserCard> user,
    required Expr<types0.Role> role,
  }) => _memberCardProjection.bind([
    _memberCardSlot0.bind(user),
    _memberCardSlot1.bind(role),
  ]);
}

final _teamViewSlot0 = orm_projection.Slot<int>("id");
final _teamViewSlot1 = orm_projection.Slot<String>("name");
final _teamViewSlot2 = orm_projection.Slot<types1.UserCard?>("owner");
final _teamViewSlot3 = orm_projection.Slot<List<types1.MemberCard>>("members");

final class TeamViewFields extends orm_projection.ProjectionOutput {
  TeamViewFields._(orm_projection.ProjectionFields fields)
    : id = fields.read(_teamViewSlot0),
      name = fields.read(_teamViewSlot1),
      owner = fields.read(_teamViewSlot2),
      members = fields.read(_teamViewSlot3),
      super(fields.table);
  final Expr<int> id;
  final Expr<String> name;
  final Expr<types1.UserCard?> owner;
  final Expr<List<types1.MemberCard>> members;
}

final _teamViewProjection =
    orm_projection.ProjectionType<types1.TeamView, TeamViewFields>(
      slots: [_teamViewSlot0, _teamViewSlot1, _teamViewSlot2, _teamViewSlot3],
      assemble: (values) => types1.TeamView(
        id: values[0] as int,
        name: values[1] as String,
        owner: values[2] as types1.UserCard?,
        members: values[3] as List<types1.MemberCard>,
      ),
      fields: TeamViewFields._,
    );
const teamView = _TeamViewSelectionFactory();

/// Named result binding; .sql explicitly requires scalar SQL expressions.
final class _TeamViewSelectionFactory {
  const _TeamViewSelectionFactory();
  Selection<types1.TeamView> call({
    required Selection<int> id,
    required Selection<String> name,
    required Selection<types1.UserCard?> owner,
    required Selection<List<types1.MemberCard>> members,
  }) => (id, name, owner, members)
      .map((v0, v1, v2, v3) => (id: v0, name: v1, owner: v2, members: v3))
      .map(
        (result) => types1.TeamView(
          id: result.id,
          name: result.name,
          owner: result.owner,
          members: result.members,
        ),
      );
  orm_projection.Projection<types1.TeamView, TeamViewFields> sql({
    required Expr<int> id,
    required Expr<String> name,
    required Expr<types1.UserCard?> owner,
    required Expr<List<types1.MemberCard>> members,
  }) => _teamViewProjection.bind([
    _teamViewSlot0.bind(id),
    _teamViewSlot1.bind(name),
    _teamViewSlot2.bind(owner),
    _teamViewSlot3.bind(members),
  ]);
}

final _userCardSlot0 = orm_projection.Slot<int>("id");
final _userCardSlot1 = orm_projection.Slot<String>("name");

final class UserCardFields extends orm_projection.ProjectionOutput {
  UserCardFields._(orm_projection.ProjectionFields fields)
    : id = fields.read(_userCardSlot0),
      name = fields.read(_userCardSlot1),
      super(fields.table);
  final Expr<int> id;
  final Expr<String> name;
}

final _userCardProjection =
    orm_projection.ProjectionType<types1.UserCard, UserCardFields>(
      slots: [_userCardSlot0, _userCardSlot1],
      assemble: (values) =>
          types1.UserCard(id: values[0] as int, name: values[1] as String),
      fields: UserCardFields._,
    );
const userCard = _UserCardSelectionFactory();

/// Named result binding; .sql explicitly requires scalar SQL expressions.
final class _UserCardSelectionFactory {
  const _UserCardSelectionFactory();
  Selection<types1.UserCard> call({
    required Selection<int> id,
    required Selection<String> name,
  }) => (id, name)
      .map((v0, v1) => (id: v0, name: v1))
      .map((result) => types1.UserCard(id: result.id, name: result.name));
  orm_projection.Projection<types1.UserCard, UserCardFields> sql({
    required Expr<int> id,
    required Expr<String> name,
  }) => _userCardProjection.bind([
    _userCardSlot0.bind(id),
    _userCardSlot1.bind(name),
  ]);
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
