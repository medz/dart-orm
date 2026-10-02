// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "schema.dart" as models;
export "schema.dart" show User, Team, MembershipRole, Membership;

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

/// Immutable input data; composition belongs to [membershipPatch], not field names.
final class MembershipPatch {
  final WriteValue<int, MembershipFields> teamId;
  final WriteValue<int, MembershipFields> userId;
  final WriteValue<models.MembershipRole, MembershipFields> role;
  final WriteValue<DateTime, MembershipFields> joinedAt;
  MembershipPatch._({
    required this.teamId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  List<Assignment> _assignments(MembershipFields fields) => [
    ...fields.teamId.write(teamId, fields),
    ...fields.userId.write(userId, fields),
    ...fields.role.write(role, fields),
    ...fields.joinedAt.write(joinedAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class MembershipPatchFactory {
  MembershipPatch call({
    int teamId,
    int userId,
    models.MembershipRole role,
    DateTime joinedAt,
  });
  MembershipPatch values({
    WriteValue<int, MembershipFields> teamId = const .keep(),
    WriteValue<int, MembershipFields> userId = const .keep(),
    WriteValue<models.MembershipRole, MembershipFields> role = const .keep(),
    WriteValue<DateTime, MembershipFields> joinedAt = const .keep(),
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
    Object? joinedAt = _writeAbsent,
  }) => MembershipPatch._(
    teamId: _writeLiteral<int, MembershipFields>(teamId),
    userId: _writeLiteral<int, MembershipFields>(userId),
    role: _writeLiteral<models.MembershipRole, MembershipFields>(role),
    joinedAt: _writeLiteral<DateTime, MembershipFields>(joinedAt),
  );
  @override
  MembershipPatch values({
    WriteValue<int, MembershipFields> teamId = const .keep(),
    WriteValue<int, MembershipFields> userId = const .keep(),
    WriteValue<models.MembershipRole, MembershipFields> role = const .keep(),
    WriteValue<DateTime, MembershipFields> joinedAt = const .keep(),
  }) => MembershipPatch._(
    teamId: teamId,
    userId: userId,
    role: role,
    joinedAt: joinedAt,
  );
  @override
  MembershipPatch overlay(Iterable<MembershipPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = MembershipPatch._(
        teamId: WriteValue.overlay(earlier.teamId, later.teamId),
        userId: WriteValue.overlay(earlier.userId, later.userId),
        role: WriteValue.overlay(earlier.role, later.role),
        joinedAt: WriteValue.overlay(earlier.joinedAt, later.joinedAt),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(MembershipPatch input) =>
      input.teamId.isMissing &&
      input.userId.isMissing &&
      input.role.isMissing &&
      input.joinedAt.isMissing;
}

/// Immutable input data; composition belongs to [membershipInsert], not field names.
final class MembershipInsert {
  final WriteValue<int, MembershipFields> teamId;
  final WriteValue<int, MembershipFields> userId;
  final WriteValue<models.MembershipRole, MembershipFields> role;
  final WriteValue<DateTime, MembershipFields> joinedAt;
  MembershipInsert._({
    required this.teamId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  }) {
    if (teamId.isMissing) {
      throw ArgumentError.value(teamId, 'teamId', 'Must be supplied.');
    }
    if (userId.isMissing) {
      throw ArgumentError.value(userId, 'userId', 'Must be supplied.');
    }
    if (joinedAt.isMissing) {
      throw ArgumentError.value(joinedAt, 'joinedAt', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(MembershipFields fields) => [
    ...fields.teamId.write(teamId, fields),
    ...fields.userId.write(userId, fields),
    ...fields.role.write(role, fields),
    ...fields.joinedAt.write(joinedAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class MembershipInsertFactory {
  MembershipInsert call({
    required int teamId,
    required int userId,
    models.MembershipRole role,
    required DateTime joinedAt,
  });
  MembershipInsert values({
    required WriteValue<int, MembershipFields> teamId,
    required WriteValue<int, MembershipFields> userId,
    WriteValue<models.MembershipRole, MembershipFields> role = const .keep(),
    required WriteValue<DateTime, MembershipFields> joinedAt,
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
    required DateTime joinedAt,
  }) => MembershipInsert._(
    teamId: .set(teamId),
    userId: .set(userId),
    role: _writeLiteral<models.MembershipRole, MembershipFields>(role),
    joinedAt: .set(joinedAt),
  );
  @override
  MembershipInsert values({
    required WriteValue<int, MembershipFields> teamId,
    required WriteValue<int, MembershipFields> userId,
    WriteValue<models.MembershipRole, MembershipFields> role = const .keep(),
    required WriteValue<DateTime, MembershipFields> joinedAt,
  }) => MembershipInsert._(
    teamId: teamId,
    userId: userId,
    role: role,
    joinedAt: joinedAt,
  );
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
        joinedAt: WriteValue.overlay(earlier.joinedAt, later.joinedAt),
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
    models.MembershipRole role,
    required DateTime joinedAt,
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
    required DateTime joinedAt,
  }) async => _table.plan
      .insert(
        MembershipInsert._(
          teamId: .set(teamId),
          userId: .set(userId),
          role: _writeLiteral<models.MembershipRole, MembershipFields>(role),
          joinedAt: .set(joinedAt),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class MembershipPatcher {
  Future<int> call({
    int teamId,
    int userId,
    models.MembershipRole role,
    DateTime joinedAt,
  });
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
    Object? joinedAt = _writeAbsent,
  }) => _query.update(
    MembershipPatch._(
      teamId: _writeLiteral<int, MembershipFields>(teamId),
      userId: _writeLiteral<int, MembershipFields>(userId),
      role: _writeLiteral<models.MembershipRole, MembershipFields>(role),
      joinedAt: _writeLiteral<DateTime, MembershipFields>(joinedAt),
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

/// Immutable input data; composition belongs to [teamPatch], not field names.
final class TeamPatch {
  final WriteValue<int, TeamFields> id;
  final WriteValue<String, TeamFields> name;
  TeamPatch._({required this.id, required this.name});

  List<Assignment> _assignments(TeamFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class TeamPatchFactory {
  TeamPatch call({int id, String name});
  TeamPatch values({
    WriteValue<int, TeamFields> id = const .keep(),
    WriteValue<String, TeamFields> name = const .keep(),
  });
  TeamPatch overlay(Iterable<TeamPatch> layers);
  bool isEmpty(TeamPatch input);
}

const TeamPatchFactory teamPatch = _TeamPatchFactory();

final class _TeamPatchFactory implements TeamPatchFactory {
  const _TeamPatchFactory();
  @override
  TeamPatch call({Object? id = _writeAbsent, Object? name = _writeAbsent}) =>
      TeamPatch._(
        id: _writeLiteral<int, TeamFields>(id),
        name: _writeLiteral<String, TeamFields>(name),
      );
  @override
  TeamPatch values({
    WriteValue<int, TeamFields> id = const .keep(),
    WriteValue<String, TeamFields> name = const .keep(),
  }) => TeamPatch._(id: id, name: name);
  @override
  TeamPatch overlay(Iterable<TeamPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = TeamPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        name: WriteValue.overlay(earlier.name, later.name),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(TeamPatch input) => input.id.isMissing && input.name.isMissing;
}

/// Immutable input data; composition belongs to [teamInsert], not field names.
final class TeamInsert {
  final WriteValue<int, TeamFields> id;
  final WriteValue<String, TeamFields> name;
  TeamInsert._({required this.id, required this.name}) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (name.isMissing) {
      throw ArgumentError.value(name, 'name', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(TeamFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class TeamInsertFactory {
  TeamInsert call({required int id, required String name});
  TeamInsert values({
    required WriteValue<int, TeamFields> id,
    required WriteValue<String, TeamFields> name,
  });
  TeamInsert overlay(TeamInsert earlier, Iterable<TeamPatch> layers);
}

const TeamInsertFactory teamInsert = _TeamInsertFactory();

final class _TeamInsertFactory implements TeamInsertFactory {
  const _TeamInsertFactory();
  @override
  TeamInsert call({required int id, required String name}) =>
      TeamInsert._(id: .set(id), name: .set(name));
  @override
  TeamInsert values({
    required WriteValue<int, TeamFields> id,
    required WriteValue<String, TeamFields> name,
  }) => TeamInsert._(id: id, name: name);
  @override
  TeamInsert overlay(TeamInsert earlier, Iterable<TeamPatch> layers) {
    for (final later in layers) {
      earlier = TeamInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        name: WriteValue.overlay(earlier.name, later.name),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Team from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class TeamCreator {
  Future<models.Team> call({required int id, required String name});
}

final class _TeamCreator implements TeamCreator {
  final TeamTableSet _table;
  const _TeamCreator(this._table);
  @override
  Future<models.Team> call({required int id, required String name}) async =>
      _table.plan.insert(TeamInsert._(id: .set(id), name: .set(name))).row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class TeamPatcher {
  Future<int> call({int id, String name});
}

final class _TeamPatcher implements TeamPatcher {
  final orm_model.ModelQuery<models.Team, TeamFields, TeamPatch> _query;
  const _TeamPatcher(this._query);
  @override
  Future<int> call({Object? id = _writeAbsent, Object? name = _writeAbsent}) =>
      _query.update(
        TeamPatch._(
          id: _writeLiteral<int, TeamFields>(id),
          name: _writeLiteral<String, TeamFields>(name),
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

/// Immutable input data; composition belongs to [userPatch], not field names.
final class UserPatch {
  final WriteValue<int, UserFields> id;
  final WriteValue<String, UserFields> name;
  UserPatch._({required this.id, required this.name});

  List<Assignment> _assignments(UserFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserPatchFactory {
  UserPatch call({int id, String name});
  UserPatch values({
    WriteValue<int, UserFields> id = const .keep(),
    WriteValue<String, UserFields> name = const .keep(),
  });
  UserPatch overlay(Iterable<UserPatch> layers);
  bool isEmpty(UserPatch input);
}

const UserPatchFactory userPatch = _UserPatchFactory();

final class _UserPatchFactory implements UserPatchFactory {
  const _UserPatchFactory();
  @override
  UserPatch call({Object? id = _writeAbsent, Object? name = _writeAbsent}) =>
      UserPatch._(
        id: _writeLiteral<int, UserFields>(id),
        name: _writeLiteral<String, UserFields>(name),
      );
  @override
  UserPatch values({
    WriteValue<int, UserFields> id = const .keep(),
    WriteValue<String, UserFields> name = const .keep(),
  }) => UserPatch._(id: id, name: name);
  @override
  UserPatch overlay(Iterable<UserPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = UserPatch._(
        id: WriteValue.overlay(earlier.id, later.id),
        name: WriteValue.overlay(earlier.name, later.name),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(UserPatch input) => input.id.isMissing && input.name.isMissing;
}

/// Immutable input data; composition belongs to [userInsert], not field names.
final class UserInsert {
  final WriteValue<int, UserFields> id;
  final WriteValue<String, UserFields> name;
  UserInsert._({required this.id, required this.name}) {
    if (id.isMissing) {
      throw ArgumentError.value(id, 'id', 'Must be supplied.');
    }
    if (name.isMissing) {
      throw ArgumentError.value(name, 'name', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(UserFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class UserInsertFactory {
  UserInsert call({required int id, required String name});
  UserInsert values({
    required WriteValue<int, UserFields> id,
    required WriteValue<String, UserFields> name,
  });
  UserInsert overlay(UserInsert earlier, Iterable<UserPatch> layers);
}

const UserInsertFactory userInsert = _UserInsertFactory();

final class _UserInsertFactory implements UserInsertFactory {
  const _UserInsertFactory();
  @override
  UserInsert call({required int id, required String name}) =>
      UserInsert._(id: .set(id), name: .set(name));
  @override
  UserInsert values({
    required WriteValue<int, UserFields> id,
    required WriteValue<String, UserFields> name,
  }) => UserInsert._(id: id, name: name);
  @override
  UserInsert overlay(UserInsert earlier, Iterable<UserPatch> layers) {
    for (final later in layers) {
      earlier = UserInsert._(
        id: WriteValue.overlay(earlier.id, later.id),
        name: WriteValue.overlay(earlier.name, later.name),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.User from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class UserCreator {
  Future<models.User> call({required int id, required String name});
}

final class _UserCreator implements UserCreator {
  final UserTableSet _table;
  const _UserCreator(this._table);
  @override
  Future<models.User> call({required int id, required String name}) async =>
      _table.plan.insert(UserInsert._(id: .set(id), name: .set(name))).row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class UserPatcher {
  Future<int> call({int id, String name});
}

final class _UserPatcher implements UserPatcher {
  final orm_model.ModelQuery<models.User, UserFields, UserPatch> _query;
  const _UserPatcher(this._query);
  @override
  Future<int> call({Object? id = _writeAbsent, Object? name = _writeAbsent}) =>
      _query.update(
        UserPatch._(
          id: _writeLiteral<int, UserFields>(id),
          name: _writeLiteral<String, UserFields>(name),
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
