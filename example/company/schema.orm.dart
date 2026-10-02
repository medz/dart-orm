// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
import 'package:orm/schema_model.dart';
import 'package:orm/orm.dart' as orm_model show ModelTable, ModelQuery;
import 'package:orm/values.dart';
import 'package:orm/sql.dart' as orm show allOf;

import "schema.dart" as models;
export "schema.dart"
    show
        Department,
        Employee,
        ProjectStatus,
        Project,
        MemberRole,
        ProjectMember;

final class _OrmWriteAbsent {
  const _OrmWriteAbsent();
}

const _writeAbsent = _OrmWriteAbsent();
WriteValue<T, F> _writeLiteral<T, F extends Fields>(Object? value) =>
    identical(value, _writeAbsent) ? const .keep() : .set(value as T);

final _departmentId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _departmentName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final departmentSchema = TableSchema(
  "departments",
  columns: [_departmentId, _departmentName],
  primaryKey: ["id"],
  uniqueKeys: [
    ["name"],
  ],
  indexes: [],
  foreignKeys: [],
);

final class DepartmentFields extends Fields {
  DepartmentFields(super.table);
  late final id = column(_departmentId);
  late final name = column(_departmentName);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Employee, EmployeeFields> get employees =>
      Relation(employeeTable, parent: [id], child: (row) => [row.departmentId]);
}

final departmentTable = Table<models.Department, DepartmentFields>(
  departmentSchema,
  DepartmentFields.new,
  (row) =>
      (row.id, row.name).map((v0, v1) => models.Department(id: v0, name: v1)),
);

/// Immutable input data; composition belongs to [departmentPatch], not field names.
final class DepartmentPatch {
  final WriteValue<String, DepartmentFields> name;
  DepartmentPatch._({required this.name});

  List<Assignment> _assignments(DepartmentFields fields) => [
    ...fields.name.write(name, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class DepartmentPatchFactory {
  DepartmentPatch call({String name});
  DepartmentPatch values({
    WriteValue<String, DepartmentFields> name = const .keep(),
  });
  DepartmentPatch overlay(Iterable<DepartmentPatch> layers);
  bool isEmpty(DepartmentPatch input);
}

const DepartmentPatchFactory departmentPatch = _DepartmentPatchFactory();

final class _DepartmentPatchFactory implements DepartmentPatchFactory {
  const _DepartmentPatchFactory();
  @override
  DepartmentPatch call({Object? name = _writeAbsent}) =>
      DepartmentPatch._(name: _writeLiteral<String, DepartmentFields>(name));
  @override
  DepartmentPatch values({
    WriteValue<String, DepartmentFields> name = const .keep(),
  }) => DepartmentPatch._(name: name);
  @override
  DepartmentPatch overlay(Iterable<DepartmentPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = DepartmentPatch._(
        name: WriteValue.overlay(earlier.name, later.name),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(DepartmentPatch input) => input.name.isMissing;
}

/// Immutable input data; composition belongs to [departmentInsert], not field names.
final class DepartmentInsert {
  final WriteValue<int, DepartmentFields> id;
  final WriteValue<String, DepartmentFields> name;
  DepartmentInsert._({required this.id, required this.name}) {
    if (name.isMissing) {
      throw ArgumentError.value(name, 'name', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(DepartmentFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class DepartmentInsertFactory {
  DepartmentInsert call({int id, required String name});
  DepartmentInsert values({
    WriteValue<int, DepartmentFields> id = const .keep(),
    required WriteValue<String, DepartmentFields> name,
  });
  DepartmentInsert overlay(
    DepartmentInsert earlier,
    Iterable<DepartmentPatch> layers,
  );
}

const DepartmentInsertFactory departmentInsert = _DepartmentInsertFactory();

final class _DepartmentInsertFactory implements DepartmentInsertFactory {
  const _DepartmentInsertFactory();
  @override
  DepartmentInsert call({Object? id = _writeAbsent, required String name}) =>
      DepartmentInsert._(
        id: _writeLiteral<int, DepartmentFields>(id),
        name: .set(name),
      );
  @override
  DepartmentInsert values({
    WriteValue<int, DepartmentFields> id = const .keep(),
    required WriteValue<String, DepartmentFields> name,
  }) => DepartmentInsert._(id: id, name: name);
  @override
  DepartmentInsert overlay(
    DepartmentInsert earlier,
    Iterable<DepartmentPatch> layers,
  ) {
    for (final later in layers) {
      earlier = DepartmentInsert._(
        id: earlier.id,
        name: WriteValue.overlay(earlier.name, later.name),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Department from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class DepartmentCreator {
  Future<models.Department> call({int id, required String name});
}

final class _DepartmentCreator implements DepartmentCreator {
  final DepartmentTableSet _table;
  const _DepartmentCreator(this._table);
  @override
  Future<models.Department> call({
    Object? id = _writeAbsent,
    required String name,
  }) async => _table.plan
      .insert(
        DepartmentInsert._(
          id: _writeLiteral<int, DepartmentFields>(id),
          name: .set(name),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class DepartmentPatcher {
  Future<int> call({String name});
}

final class _DepartmentPatcher implements DepartmentPatcher {
  final orm_model.ModelQuery<
    models.Department,
    DepartmentFields,
    DepartmentPatch
  >
  _query;
  const _DepartmentPatcher(this._query);
  @override
  Future<int> call({Object? name = _writeAbsent}) => _query.update(
    DepartmentPatch._(name: _writeLiteral<String, DepartmentFields>(name)),
  );
}

/// Named literal updates on a complete models.Department query.
extension DepartmentWrites
    on
        orm_model.ModelQuery<
          models.Department,
          DepartmentFields,
          DepartmentPatch
        > {
  /// Executes one update; omitted fields remain unchanged.
  DepartmentPatcher get patch => _DepartmentPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class DepartmentTableSet
    extends
        orm_model.ModelTable<
          models.Department,
          DepartmentFields,
          DepartmentInsert,
          DepartmentPatch
        > {
  DepartmentTableSet(QueryContext db)
    : super(
        db,
        departmentTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final DepartmentCreator create = _DepartmentCreator(this);

  orm_model.ModelQuery<models.Department, DepartmentFields, DepartmentPatch>
  byId(int id) => where((row) => row.id.eq(.value(id)));
}

final _employeeId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _employeeName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _employeeEmail = Column<String>(
  "email",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _employeeActive = Column<bool>(
  "active",
  Codecs.boolean,
  nullable: false,
  generated: false,
  defaultSql: "true",
);
final _employeeCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  clientDefault: DateTime.now,
);
final _employeeDepartmentId = Column<int>(
  "department_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _employeeManagerId = Column<int?>(
  "manager_id",
  Codecs.integer.nullable(),
  nullable: true,
  generated: false,
);
final employeeSchema = TableSchema(
  "employees",
  columns: [
    _employeeId,
    _employeeName,
    _employeeEmail,
    _employeeActive,
    _employeeCreatedAt,
    _employeeDepartmentId,
    _employeeManagerId,
  ],
  primaryKey: ["id"],
  uniqueKeys: [
    ["email"],
  ],
  indexes: [
    IndexSchema("employees_department_id", [
      "department_id",
      "id",
    ], unique: false),
    IndexSchema("employees_manager_id", ["manager_id", "id"], unique: false),
  ],
  foreignKeys: [
    ForeignKey(["department_id"], "departments", ["id"], onDelete: "RESTRICT"),
    ForeignKey(["manager_id"], "employees", ["id"], onDelete: "SET NULL"),
  ],
);

final class EmployeeFields extends Fields {
  EmployeeFields(super.table);
  late final id = column(_employeeId);
  late final name = column(_employeeName);
  late final email = column(_employeeEmail);
  late final active = column(_employeeActive);
  late final createdAt = column(_employeeCreatedAt);
  late final departmentId = column(_employeeDepartmentId);
  late final managerId = column(_employeeManagerId);
  Relation<models.Department, DepartmentFields> get department => Relation(
    departmentTable,
    parent: [departmentId],
    child: (row) => [row.id],
  );
  Relation<models.Employee, EmployeeFields> get manager =>
      Relation(employeeTable, parent: [managerId], child: (row) => [row.id]);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Employee, EmployeeFields> get directReports =>
      Relation(employeeTable, parent: [id], child: (row) => [row.managerId]);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.Project, ProjectFields> get ownedProjects =>
      Relation(projectTable, parent: [id], child: (row) => [row.ownerId]);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.ProjectMember, ProjectMemberFields> get memberships =>
      Relation(
        projectMemberTable,
        parent: [id],
        child: (row) => [row.employeeId],
      );
}

final employeeTable = Table<models.Employee, EmployeeFields>(
  employeeSchema,
  EmployeeFields.new,
  (row) =>
      (
        (row.id, row.name, row.email, row.active, row.createdAt).map(
          (id, name, email, active, createdAt) => (
            id: id,
            name: name,
            email: email,
            active: active,
            createdAt: createdAt,
          ),
        ),
        (row.departmentId, row.managerId).map(
          (departmentId, managerId) =>
              (departmentId: departmentId, managerId: managerId),
        ),
      ).map(
        (left, right) => models.Employee(
          id: left.id,
          name: left.name,
          email: left.email,
          active: left.active,
          createdAt: left.createdAt,
          departmentId: right.departmentId,
          managerId: right.managerId,
        ),
      ),
);

/// Immutable input data; composition belongs to [employeePatch], not field names.
final class EmployeePatch {
  final WriteValue<String, EmployeeFields> name;
  final WriteValue<String, EmployeeFields> email;
  final WriteValue<bool, EmployeeFields> active;
  final WriteValue<DateTime, EmployeeFields> createdAt;
  final WriteValue<int, EmployeeFields> departmentId;
  final WriteValue<int?, EmployeeFields> managerId;
  EmployeePatch._({
    required this.name,
    required this.email,
    required this.active,
    required this.createdAt,
    required this.departmentId,
    required this.managerId,
  });

  List<Assignment> _assignments(EmployeeFields fields) => [
    ...fields.name.write(name, fields),
    ...fields.email.write(email, fields),
    ...fields.active.write(active, fields),
    ...fields.createdAt.write(createdAt, fields),
    ...fields.departmentId.write(departmentId, fields),
    ...fields.managerId.write(managerId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EmployeePatchFactory {
  EmployeePatch call({
    String name,
    String email,
    bool active,
    DateTime createdAt,
    int departmentId,
    int? managerId,
  });
  EmployeePatch values({
    WriteValue<String, EmployeeFields> name = const .keep(),
    WriteValue<String, EmployeeFields> email = const .keep(),
    WriteValue<bool, EmployeeFields> active = const .keep(),
    WriteValue<DateTime, EmployeeFields> createdAt = const .keep(),
    WriteValue<int, EmployeeFields> departmentId = const .keep(),
    WriteValue<int?, EmployeeFields> managerId = const .keep(),
  });
  EmployeePatch overlay(Iterable<EmployeePatch> layers);
  bool isEmpty(EmployeePatch input);
}

const EmployeePatchFactory employeePatch = _EmployeePatchFactory();

final class _EmployeePatchFactory implements EmployeePatchFactory {
  const _EmployeePatchFactory();
  @override
  EmployeePatch call({
    Object? name = _writeAbsent,
    Object? email = _writeAbsent,
    Object? active = _writeAbsent,
    Object? createdAt = _writeAbsent,
    Object? departmentId = _writeAbsent,
    Object? managerId = _writeAbsent,
  }) => EmployeePatch._(
    name: _writeLiteral<String, EmployeeFields>(name),
    email: _writeLiteral<String, EmployeeFields>(email),
    active: _writeLiteral<bool, EmployeeFields>(active),
    createdAt: _writeLiteral<DateTime, EmployeeFields>(createdAt),
    departmentId: _writeLiteral<int, EmployeeFields>(departmentId),
    managerId: _writeLiteral<int?, EmployeeFields>(managerId),
  );
  @override
  EmployeePatch values({
    WriteValue<String, EmployeeFields> name = const .keep(),
    WriteValue<String, EmployeeFields> email = const .keep(),
    WriteValue<bool, EmployeeFields> active = const .keep(),
    WriteValue<DateTime, EmployeeFields> createdAt = const .keep(),
    WriteValue<int, EmployeeFields> departmentId = const .keep(),
    WriteValue<int?, EmployeeFields> managerId = const .keep(),
  }) => EmployeePatch._(
    name: name,
    email: email,
    active: active,
    createdAt: createdAt,
    departmentId: departmentId,
    managerId: managerId,
  );
  @override
  EmployeePatch overlay(Iterable<EmployeePatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = EmployeePatch._(
        name: WriteValue.overlay(earlier.name, later.name),
        email: WriteValue.overlay(earlier.email, later.email),
        active: WriteValue.overlay(earlier.active, later.active),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
        departmentId: WriteValue.overlay(
          earlier.departmentId,
          later.departmentId,
        ),
        managerId: WriteValue.overlay(earlier.managerId, later.managerId),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(EmployeePatch input) =>
      input.name.isMissing &&
      input.email.isMissing &&
      input.active.isMissing &&
      input.createdAt.isMissing &&
      input.departmentId.isMissing &&
      input.managerId.isMissing;
}

/// Immutable input data; composition belongs to [employeeInsert], not field names.
final class EmployeeInsert {
  final WriteValue<int, EmployeeFields> id;
  final WriteValue<String, EmployeeFields> name;
  final WriteValue<String, EmployeeFields> email;
  final WriteValue<bool, EmployeeFields> active;
  final WriteValue<DateTime, EmployeeFields> createdAt;
  final WriteValue<int, EmployeeFields> departmentId;
  final WriteValue<int?, EmployeeFields> managerId;
  EmployeeInsert._({
    required this.id,
    required this.name,
    required this.email,
    required this.active,
    required this.createdAt,
    required this.departmentId,
    required this.managerId,
  }) {
    if (name.isMissing) {
      throw ArgumentError.value(name, 'name', 'Must be supplied.');
    }
    if (email.isMissing) {
      throw ArgumentError.value(email, 'email', 'Must be supplied.');
    }
    if (departmentId.isMissing) {
      throw ArgumentError.value(
        departmentId,
        'departmentId',
        'Must be supplied.',
      );
    }
  }
  List<Assignment> _assignments(EmployeeFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
    ...fields.email.write(email, fields),
    ...fields.active.write(active, fields),
    ...fields.createdAt.write(createdAt, fields),
    ...fields.departmentId.write(departmentId, fields),
    ...fields.managerId.write(managerId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class EmployeeInsertFactory {
  EmployeeInsert call({
    int id,
    required String name,
    required String email,
    bool active,
    DateTime createdAt,
    required int departmentId,
    int? managerId,
  });
  EmployeeInsert values({
    WriteValue<int, EmployeeFields> id = const .keep(),
    required WriteValue<String, EmployeeFields> name,
    required WriteValue<String, EmployeeFields> email,
    WriteValue<bool, EmployeeFields> active = const .keep(),
    WriteValue<DateTime, EmployeeFields> createdAt = const .keep(),
    required WriteValue<int, EmployeeFields> departmentId,
    WriteValue<int?, EmployeeFields> managerId = const .keep(),
  });
  EmployeeInsert overlay(
    EmployeeInsert earlier,
    Iterable<EmployeePatch> layers,
  );
}

const EmployeeInsertFactory employeeInsert = _EmployeeInsertFactory();

final class _EmployeeInsertFactory implements EmployeeInsertFactory {
  const _EmployeeInsertFactory();
  @override
  EmployeeInsert call({
    Object? id = _writeAbsent,
    required String name,
    required String email,
    Object? active = _writeAbsent,
    Object? createdAt = _writeAbsent,
    required int departmentId,
    Object? managerId = _writeAbsent,
  }) => EmployeeInsert._(
    id: _writeLiteral<int, EmployeeFields>(id),
    name: .set(name),
    email: .set(email),
    active: _writeLiteral<bool, EmployeeFields>(active),
    createdAt: _writeLiteral<DateTime, EmployeeFields>(createdAt),
    departmentId: .set(departmentId),
    managerId: _writeLiteral<int?, EmployeeFields>(managerId),
  );
  @override
  EmployeeInsert values({
    WriteValue<int, EmployeeFields> id = const .keep(),
    required WriteValue<String, EmployeeFields> name,
    required WriteValue<String, EmployeeFields> email,
    WriteValue<bool, EmployeeFields> active = const .keep(),
    WriteValue<DateTime, EmployeeFields> createdAt = const .keep(),
    required WriteValue<int, EmployeeFields> departmentId,
    WriteValue<int?, EmployeeFields> managerId = const .keep(),
  }) => EmployeeInsert._(
    id: id,
    name: name,
    email: email,
    active: active,
    createdAt: createdAt,
    departmentId: departmentId,
    managerId: managerId,
  );
  @override
  EmployeeInsert overlay(
    EmployeeInsert earlier,
    Iterable<EmployeePatch> layers,
  ) {
    for (final later in layers) {
      earlier = EmployeeInsert._(
        id: earlier.id,
        name: WriteValue.overlay(earlier.name, later.name),
        email: WriteValue.overlay(earlier.email, later.email),
        active: WriteValue.overlay(earlier.active, later.active),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
        departmentId: WriteValue.overlay(
          earlier.departmentId,
          later.departmentId,
        ),
        managerId: WriteValue.overlay(earlier.managerId, later.managerId),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Employee from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class EmployeeCreator {
  Future<models.Employee> call({
    int id,
    required String name,
    required String email,
    bool active,
    DateTime createdAt,
    required int departmentId,
    int? managerId,
  });
}

final class _EmployeeCreator implements EmployeeCreator {
  final EmployeeTableSet _table;
  const _EmployeeCreator(this._table);
  @override
  Future<models.Employee> call({
    Object? id = _writeAbsent,
    required String name,
    required String email,
    Object? active = _writeAbsent,
    Object? createdAt = _writeAbsent,
    required int departmentId,
    Object? managerId = _writeAbsent,
  }) async => _table.plan
      .insert(
        EmployeeInsert._(
          id: _writeLiteral<int, EmployeeFields>(id),
          name: .set(name),
          email: .set(email),
          active: _writeLiteral<bool, EmployeeFields>(active),
          createdAt: _writeLiteral<DateTime, EmployeeFields>(createdAt),
          departmentId: .set(departmentId),
          managerId: _writeLiteral<int?, EmployeeFields>(managerId),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class EmployeePatcher {
  Future<int> call({
    String name,
    String email,
    bool active,
    DateTime createdAt,
    int departmentId,
    int? managerId,
  });
}

final class _EmployeePatcher implements EmployeePatcher {
  final orm_model.ModelQuery<models.Employee, EmployeeFields, EmployeePatch>
  _query;
  const _EmployeePatcher(this._query);
  @override
  Future<int> call({
    Object? name = _writeAbsent,
    Object? email = _writeAbsent,
    Object? active = _writeAbsent,
    Object? createdAt = _writeAbsent,
    Object? departmentId = _writeAbsent,
    Object? managerId = _writeAbsent,
  }) => _query.update(
    EmployeePatch._(
      name: _writeLiteral<String, EmployeeFields>(name),
      email: _writeLiteral<String, EmployeeFields>(email),
      active: _writeLiteral<bool, EmployeeFields>(active),
      createdAt: _writeLiteral<DateTime, EmployeeFields>(createdAt),
      departmentId: _writeLiteral<int, EmployeeFields>(departmentId),
      managerId: _writeLiteral<int?, EmployeeFields>(managerId),
    ),
  );
}

/// Named literal updates on a complete models.Employee query.
extension EmployeeWrites
    on orm_model.ModelQuery<models.Employee, EmployeeFields, EmployeePatch> {
  /// Executes one update; omitted fields remain unchanged.
  EmployeePatcher get patch => _EmployeePatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class EmployeeTableSet
    extends
        orm_model.ModelTable<
          models.Employee,
          EmployeeFields,
          EmployeeInsert,
          EmployeePatch
        > {
  EmployeeTableSet(QueryContext db)
    : super(
        db,
        employeeTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final EmployeeCreator create = _EmployeeCreator(this);

  orm_model.ModelQuery<models.Employee, EmployeeFields, EmployeePatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
}

final _projectMemberProjectId = Column<int>(
  "project_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _projectMemberEmployeeId = Column<int>(
  "employee_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final _projectMemberRole = Column<models.MemberRole>(
  "role",
  Codecs.enumeration<models.MemberRole>({
    models.MemberRole.maintainer: "maintainer",
    models.MemberRole.member: "member",
  }),
  nullable: false,
  generated: false,
  defaultSql: "'member'",
);
final _projectMemberJoinedAt = Column<DateTime>(
  "joined_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  clientDefault: DateTime.now,
);
final projectMemberSchema = TableSchema(
  "project_members",
  columns: [
    _projectMemberProjectId,
    _projectMemberEmployeeId,
    _projectMemberRole,
    _projectMemberJoinedAt,
  ],
  primaryKey: ["project_id", "employee_id"],
  uniqueKeys: [],
  indexes: [
    IndexSchema("project_members_employee_project", [
      "employee_id",
      "project_id",
    ], unique: false),
  ],
  foreignKeys: [
    ForeignKey(["project_id"], "projects", ["id"], onDelete: "CASCADE"),
    ForeignKey(["employee_id"], "employees", ["id"], onDelete: "CASCADE"),
  ],
);

final class ProjectMemberFields extends Fields {
  ProjectMemberFields(super.table);
  late final projectId = column(_projectMemberProjectId);
  late final employeeId = column(_projectMemberEmployeeId);
  late final role = column(_projectMemberRole);
  late final joinedAt = column(_projectMemberJoinedAt);
  Relation<models.Project, ProjectFields> get project =>
      Relation(projectTable, parent: [projectId], child: (row) => [row.id]);
  Relation<models.Employee, EmployeeFields> get employee =>
      Relation(employeeTable, parent: [employeeId], child: (row) => [row.id]);
}

final projectMemberTable = Table<models.ProjectMember, ProjectMemberFields>(
  projectMemberSchema,
  ProjectMemberFields.new,
  (row) => (row.projectId, row.employeeId, row.role, row.joinedAt).map(
    (v0, v1, v2, v3) => models.ProjectMember(
      projectId: v0,
      employeeId: v1,
      role: v2,
      joinedAt: v3,
    ),
  ),
);

/// Immutable input data; composition belongs to [projectMemberPatch], not field names.
final class ProjectMemberPatch {
  final WriteValue<int, ProjectMemberFields> projectId;
  final WriteValue<int, ProjectMemberFields> employeeId;
  final WriteValue<models.MemberRole, ProjectMemberFields> role;
  final WriteValue<DateTime, ProjectMemberFields> joinedAt;
  ProjectMemberPatch._({
    required this.projectId,
    required this.employeeId,
    required this.role,
    required this.joinedAt,
  });

  List<Assignment> _assignments(ProjectMemberFields fields) => [
    ...fields.projectId.write(projectId, fields),
    ...fields.employeeId.write(employeeId, fields),
    ...fields.role.write(role, fields),
    ...fields.joinedAt.write(joinedAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ProjectMemberPatchFactory {
  ProjectMemberPatch call({
    int projectId,
    int employeeId,
    models.MemberRole role,
    DateTime joinedAt,
  });
  ProjectMemberPatch values({
    WriteValue<int, ProjectMemberFields> projectId = const .keep(),
    WriteValue<int, ProjectMemberFields> employeeId = const .keep(),
    WriteValue<models.MemberRole, ProjectMemberFields> role = const .keep(),
    WriteValue<DateTime, ProjectMemberFields> joinedAt = const .keep(),
  });
  ProjectMemberPatch overlay(Iterable<ProjectMemberPatch> layers);
  bool isEmpty(ProjectMemberPatch input);
}

const ProjectMemberPatchFactory projectMemberPatch =
    _ProjectMemberPatchFactory();

final class _ProjectMemberPatchFactory implements ProjectMemberPatchFactory {
  const _ProjectMemberPatchFactory();
  @override
  ProjectMemberPatch call({
    Object? projectId = _writeAbsent,
    Object? employeeId = _writeAbsent,
    Object? role = _writeAbsent,
    Object? joinedAt = _writeAbsent,
  }) => ProjectMemberPatch._(
    projectId: _writeLiteral<int, ProjectMemberFields>(projectId),
    employeeId: _writeLiteral<int, ProjectMemberFields>(employeeId),
    role: _writeLiteral<models.MemberRole, ProjectMemberFields>(role),
    joinedAt: _writeLiteral<DateTime, ProjectMemberFields>(joinedAt),
  );
  @override
  ProjectMemberPatch values({
    WriteValue<int, ProjectMemberFields> projectId = const .keep(),
    WriteValue<int, ProjectMemberFields> employeeId = const .keep(),
    WriteValue<models.MemberRole, ProjectMemberFields> role = const .keep(),
    WriteValue<DateTime, ProjectMemberFields> joinedAt = const .keep(),
  }) => ProjectMemberPatch._(
    projectId: projectId,
    employeeId: employeeId,
    role: role,
    joinedAt: joinedAt,
  );
  @override
  ProjectMemberPatch overlay(Iterable<ProjectMemberPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = ProjectMemberPatch._(
        projectId: WriteValue.overlay(earlier.projectId, later.projectId),
        employeeId: WriteValue.overlay(earlier.employeeId, later.employeeId),
        role: WriteValue.overlay(earlier.role, later.role),
        joinedAt: WriteValue.overlay(earlier.joinedAt, later.joinedAt),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(ProjectMemberPatch input) =>
      input.projectId.isMissing &&
      input.employeeId.isMissing &&
      input.role.isMissing &&
      input.joinedAt.isMissing;
}

/// Immutable input data; composition belongs to [projectMemberInsert], not field names.
final class ProjectMemberInsert {
  final WriteValue<int, ProjectMemberFields> projectId;
  final WriteValue<int, ProjectMemberFields> employeeId;
  final WriteValue<models.MemberRole, ProjectMemberFields> role;
  final WriteValue<DateTime, ProjectMemberFields> joinedAt;
  ProjectMemberInsert._({
    required this.projectId,
    required this.employeeId,
    required this.role,
    required this.joinedAt,
  }) {
    if (projectId.isMissing) {
      throw ArgumentError.value(projectId, 'projectId', 'Must be supplied.');
    }
    if (employeeId.isMissing) {
      throw ArgumentError.value(employeeId, 'employeeId', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(ProjectMemberFields fields) => [
    ...fields.projectId.write(projectId, fields),
    ...fields.employeeId.write(employeeId, fields),
    ...fields.role.write(role, fields),
    ...fields.joinedAt.write(joinedAt, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ProjectMemberInsertFactory {
  ProjectMemberInsert call({
    required int projectId,
    required int employeeId,
    models.MemberRole role,
    DateTime joinedAt,
  });
  ProjectMemberInsert values({
    required WriteValue<int, ProjectMemberFields> projectId,
    required WriteValue<int, ProjectMemberFields> employeeId,
    WriteValue<models.MemberRole, ProjectMemberFields> role = const .keep(),
    WriteValue<DateTime, ProjectMemberFields> joinedAt = const .keep(),
  });
  ProjectMemberInsert overlay(
    ProjectMemberInsert earlier,
    Iterable<ProjectMemberPatch> layers,
  );
}

const ProjectMemberInsertFactory projectMemberInsert =
    _ProjectMemberInsertFactory();

final class _ProjectMemberInsertFactory implements ProjectMemberInsertFactory {
  const _ProjectMemberInsertFactory();
  @override
  ProjectMemberInsert call({
    required int projectId,
    required int employeeId,
    Object? role = _writeAbsent,
    Object? joinedAt = _writeAbsent,
  }) => ProjectMemberInsert._(
    projectId: .set(projectId),
    employeeId: .set(employeeId),
    role: _writeLiteral<models.MemberRole, ProjectMemberFields>(role),
    joinedAt: _writeLiteral<DateTime, ProjectMemberFields>(joinedAt),
  );
  @override
  ProjectMemberInsert values({
    required WriteValue<int, ProjectMemberFields> projectId,
    required WriteValue<int, ProjectMemberFields> employeeId,
    WriteValue<models.MemberRole, ProjectMemberFields> role = const .keep(),
    WriteValue<DateTime, ProjectMemberFields> joinedAt = const .keep(),
  }) => ProjectMemberInsert._(
    projectId: projectId,
    employeeId: employeeId,
    role: role,
    joinedAt: joinedAt,
  );
  @override
  ProjectMemberInsert overlay(
    ProjectMemberInsert earlier,
    Iterable<ProjectMemberPatch> layers,
  ) {
    for (final later in layers) {
      earlier = ProjectMemberInsert._(
        projectId: WriteValue.overlay(earlier.projectId, later.projectId),
        employeeId: WriteValue.overlay(earlier.employeeId, later.employeeId),
        role: WriteValue.overlay(earlier.role, later.role),
        joinedAt: WriteValue.overlay(earlier.joinedAt, later.joinedAt),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.ProjectMember from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class ProjectMemberCreator {
  Future<models.ProjectMember> call({
    required int projectId,
    required int employeeId,
    models.MemberRole role,
    DateTime joinedAt,
  });
}

final class _ProjectMemberCreator implements ProjectMemberCreator {
  final ProjectMemberTableSet _table;
  const _ProjectMemberCreator(this._table);
  @override
  Future<models.ProjectMember> call({
    required int projectId,
    required int employeeId,
    Object? role = _writeAbsent,
    Object? joinedAt = _writeAbsent,
  }) async => _table.plan
      .insert(
        ProjectMemberInsert._(
          projectId: .set(projectId),
          employeeId: .set(employeeId),
          role: _writeLiteral<models.MemberRole, ProjectMemberFields>(role),
          joinedAt: _writeLiteral<DateTime, ProjectMemberFields>(joinedAt),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class ProjectMemberPatcher {
  Future<int> call({
    int projectId,
    int employeeId,
    models.MemberRole role,
    DateTime joinedAt,
  });
}

final class _ProjectMemberPatcher implements ProjectMemberPatcher {
  final orm_model.ModelQuery<
    models.ProjectMember,
    ProjectMemberFields,
    ProjectMemberPatch
  >
  _query;
  const _ProjectMemberPatcher(this._query);
  @override
  Future<int> call({
    Object? projectId = _writeAbsent,
    Object? employeeId = _writeAbsent,
    Object? role = _writeAbsent,
    Object? joinedAt = _writeAbsent,
  }) => _query.update(
    ProjectMemberPatch._(
      projectId: _writeLiteral<int, ProjectMemberFields>(projectId),
      employeeId: _writeLiteral<int, ProjectMemberFields>(employeeId),
      role: _writeLiteral<models.MemberRole, ProjectMemberFields>(role),
      joinedAt: _writeLiteral<DateTime, ProjectMemberFields>(joinedAt),
    ),
  );
}

/// Named literal updates on a complete models.ProjectMember query.
extension ProjectMemberWrites
    on
        orm_model.ModelQuery<
          models.ProjectMember,
          ProjectMemberFields,
          ProjectMemberPatch
        > {
  /// Executes one update; omitted fields remain unchanged.
  ProjectMemberPatcher get patch => _ProjectMemberPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class ProjectMemberTableSet
    extends
        orm_model.ModelTable<
          models.ProjectMember,
          ProjectMemberFields,
          ProjectMemberInsert,
          ProjectMemberPatch
        > {
  ProjectMemberTableSet(QueryContext db)
    : super(
        db,
        projectMemberTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final ProjectMemberCreator create = _ProjectMemberCreator(this);

  orm_model.ModelQuery<
    models.ProjectMember,
    ProjectMemberFields,
    ProjectMemberPatch
  >
  byId({required int projectId, required int employeeId}) => where(
    (row) => orm.allOf([
      row.projectId.eq(.value(projectId)),
      row.employeeId.eq(.value(employeeId)),
    ]),
  );
}

final _projectId = Column<int>(
  "id",
  Codecs.integer,
  nullable: false,
  generated: true,
);
final _projectName = Column<String>(
  "name",
  Codecs.text,
  nullable: false,
  generated: false,
);
final _projectStatus = Column<models.ProjectStatus>(
  "status",
  Codecs.enumeration<models.ProjectStatus>({
    models.ProjectStatus.draft: "draft",
    models.ProjectStatus.active: "active",
    models.ProjectStatus.archived: "archived",
  }),
  nullable: false,
  generated: false,
  defaultSql: "'draft'",
);
final _projectCreatedAt = Column<DateTime>(
  "created_at",
  Codecs.dateTime,
  nullable: false,
  generated: false,
  clientDefault: DateTime.now,
);
final _projectOwnerId = Column<int>(
  "owner_id",
  Codecs.integer,
  nullable: false,
  generated: false,
);
final projectSchema = TableSchema(
  "projects",
  columns: [
    _projectId,
    _projectName,
    _projectStatus,
    _projectCreatedAt,
    _projectOwnerId,
  ],
  primaryKey: ["id"],
  uniqueKeys: [],
  indexes: [
    IndexSchema("projects_owner_id", ["owner_id", "id"], unique: false),
  ],
  foreignKeys: [
    ForeignKey(["owner_id"], "employees", ["id"], onDelete: "RESTRICT"),
  ],
);

final class ProjectFields extends Fields {
  ProjectFields(super.table);
  late final id = column(_projectId);
  late final name = column(_projectName);
  late final status = column(_projectStatus);
  late final createdAt = column(_projectCreatedAt);
  late final ownerId = column(_projectOwnerId);
  Relation<models.Employee, EmployeeFields> get owner =>
      Relation(employeeTable, parent: [ownerId], child: (row) => [row.id]);

  /// Read-only navigation; no database foreign key or write effects.
  Relation<models.ProjectMember, ProjectMemberFields> get members => Relation(
    projectMemberTable,
    parent: [id],
    child: (row) => [row.projectId],
  );
}

final projectTable = Table<models.Project, ProjectFields>(
  projectSchema,
  ProjectFields.new,
  (row) => (row.id, row.name, row.status, row.createdAt, row.ownerId).map(
    (v0, v1, v2, v3, v4) => models.Project(
      id: v0,
      name: v1,
      status: v2,
      createdAt: v3,
      ownerId: v4,
    ),
  ),
);

/// Immutable input data; composition belongs to [projectPatch], not field names.
final class ProjectPatch {
  final WriteValue<String, ProjectFields> name;
  final WriteValue<models.ProjectStatus, ProjectFields> status;
  final WriteValue<DateTime, ProjectFields> createdAt;
  final WriteValue<int, ProjectFields> ownerId;
  ProjectPatch._({
    required this.name,
    required this.status,
    required this.createdAt,
    required this.ownerId,
  });

  List<Assignment> _assignments(ProjectFields fields) => [
    ...fields.name.write(name, fields),
    ...fields.status.write(status, fields),
    ...fields.createdAt.write(createdAt, fields),
    ...fields.ownerId.write(ownerId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ProjectPatchFactory {
  ProjectPatch call({
    String name,
    models.ProjectStatus status,
    DateTime createdAt,
    int ownerId,
  });
  ProjectPatch values({
    WriteValue<String, ProjectFields> name = const .keep(),
    WriteValue<models.ProjectStatus, ProjectFields> status = const .keep(),
    WriteValue<DateTime, ProjectFields> createdAt = const .keep(),
    WriteValue<int, ProjectFields> ownerId = const .keep(),
  });
  ProjectPatch overlay(Iterable<ProjectPatch> layers);
  bool isEmpty(ProjectPatch input);
}

const ProjectPatchFactory projectPatch = _ProjectPatchFactory();

final class _ProjectPatchFactory implements ProjectPatchFactory {
  const _ProjectPatchFactory();
  @override
  ProjectPatch call({
    Object? name = _writeAbsent,
    Object? status = _writeAbsent,
    Object? createdAt = _writeAbsent,
    Object? ownerId = _writeAbsent,
  }) => ProjectPatch._(
    name: _writeLiteral<String, ProjectFields>(name),
    status: _writeLiteral<models.ProjectStatus, ProjectFields>(status),
    createdAt: _writeLiteral<DateTime, ProjectFields>(createdAt),
    ownerId: _writeLiteral<int, ProjectFields>(ownerId),
  );
  @override
  ProjectPatch values({
    WriteValue<String, ProjectFields> name = const .keep(),
    WriteValue<models.ProjectStatus, ProjectFields> status = const .keep(),
    WriteValue<DateTime, ProjectFields> createdAt = const .keep(),
    WriteValue<int, ProjectFields> ownerId = const .keep(),
  }) => ProjectPatch._(
    name: name,
    status: status,
    createdAt: createdAt,
    ownerId: ownerId,
  );
  @override
  ProjectPatch overlay(Iterable<ProjectPatch> layers) {
    var earlier = call();
    for (final later in layers) {
      earlier = ProjectPatch._(
        name: WriteValue.overlay(earlier.name, later.name),
        status: WriteValue.overlay(earlier.status, later.status),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
        ownerId: WriteValue.overlay(earlier.ownerId, later.ownerId),
      );
    }
    return earlier;
  }

  @override
  bool isEmpty(ProjectPatch input) =>
      input.name.isMissing &&
      input.status.isMissing &&
      input.createdAt.isMissing &&
      input.ownerId.isMissing;
}

/// Immutable input data; composition belongs to [projectInsert], not field names.
final class ProjectInsert {
  final WriteValue<int, ProjectFields> id;
  final WriteValue<String, ProjectFields> name;
  final WriteValue<models.ProjectStatus, ProjectFields> status;
  final WriteValue<DateTime, ProjectFields> createdAt;
  final WriteValue<int, ProjectFields> ownerId;
  ProjectInsert._({
    required this.id,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.ownerId,
  }) {
    if (name.isMissing) {
      throw ArgumentError.value(name, 'name', 'Must be supplied.');
    }
    if (ownerId.isMissing) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Must be supplied.');
    }
  }
  List<Assignment> _assignments(ProjectFields fields) => [
    ...fields.id.write(id, fields),
    ...fields.name.write(name, fields),
    ...fields.status.write(status, fields),
    ...fields.createdAt.write(createdAt, fields),
    ...fields.ownerId.write(ownerId, fields),
  ];
}

/// Literal and intent input construction share the same immutable representation.
abstract interface class ProjectInsertFactory {
  ProjectInsert call({
    int id,
    required String name,
    models.ProjectStatus status,
    DateTime createdAt,
    required int ownerId,
  });
  ProjectInsert values({
    WriteValue<int, ProjectFields> id = const .keep(),
    required WriteValue<String, ProjectFields> name,
    WriteValue<models.ProjectStatus, ProjectFields> status = const .keep(),
    WriteValue<DateTime, ProjectFields> createdAt = const .keep(),
    required WriteValue<int, ProjectFields> ownerId,
  });
  ProjectInsert overlay(ProjectInsert earlier, Iterable<ProjectPatch> layers);
}

const ProjectInsertFactory projectInsert = _ProjectInsertFactory();

final class _ProjectInsertFactory implements ProjectInsertFactory {
  const _ProjectInsertFactory();
  @override
  ProjectInsert call({
    Object? id = _writeAbsent,
    required String name,
    Object? status = _writeAbsent,
    Object? createdAt = _writeAbsent,
    required int ownerId,
  }) => ProjectInsert._(
    id: _writeLiteral<int, ProjectFields>(id),
    name: .set(name),
    status: _writeLiteral<models.ProjectStatus, ProjectFields>(status),
    createdAt: _writeLiteral<DateTime, ProjectFields>(createdAt),
    ownerId: .set(ownerId),
  );
  @override
  ProjectInsert values({
    WriteValue<int, ProjectFields> id = const .keep(),
    required WriteValue<String, ProjectFields> name,
    WriteValue<models.ProjectStatus, ProjectFields> status = const .keep(),
    WriteValue<DateTime, ProjectFields> createdAt = const .keep(),
    required WriteValue<int, ProjectFields> ownerId,
  }) => ProjectInsert._(
    id: id,
    name: name,
    status: status,
    createdAt: createdAt,
    ownerId: ownerId,
  );
  @override
  ProjectInsert overlay(ProjectInsert earlier, Iterable<ProjectPatch> layers) {
    for (final later in layers) {
      earlier = ProjectInsert._(
        id: earlier.id,
        name: WriteValue.overlay(earlier.name, later.name),
        status: WriteValue.overlay(earlier.status, later.status),
        createdAt: WriteValue.overlay(earlier.createdAt, later.createdAt),
        ownerId: WriteValue.overlay(earlier.ownerId, later.ownerId),
      );
    }
    return earlier;
  }
}

/// Creates a complete models.Project from named literal values.
/// Omission is preserved when this callable is passed as a typed function.
abstract interface class ProjectCreator {
  Future<models.Project> call({
    int id,
    required String name,
    models.ProjectStatus status,
    DateTime createdAt,
    required int ownerId,
  });
}

final class _ProjectCreator implements ProjectCreator {
  final ProjectTableSet _table;
  const _ProjectCreator(this._table);
  @override
  Future<models.Project> call({
    Object? id = _writeAbsent,
    required String name,
    Object? status = _writeAbsent,
    Object? createdAt = _writeAbsent,
    required int ownerId,
  }) async => _table.plan
      .insert(
        ProjectInsert._(
          id: _writeLiteral<int, ProjectFields>(id),
          name: .set(name),
          status: _writeLiteral<models.ProjectStatus, ProjectFields>(status),
          createdAt: _writeLiteral<DateTime, ProjectFields>(createdAt),
          ownerId: .set(ownerId),
        ),
      )
      .row();
}

/// Updates named literal fields and returns the affected-row count.
/// Omitted fields remain unchanged; explicit null clears a nullable field.
/// For execution options or composed inputs use the query's update method;
/// for RETURNING use its plan. Empty patches fail without executing SQL.
abstract interface class ProjectPatcher {
  Future<int> call({
    String name,
    models.ProjectStatus status,
    DateTime createdAt,
    int ownerId,
  });
}

final class _ProjectPatcher implements ProjectPatcher {
  final orm_model.ModelQuery<models.Project, ProjectFields, ProjectPatch>
  _query;
  const _ProjectPatcher(this._query);
  @override
  Future<int> call({
    Object? name = _writeAbsent,
    Object? status = _writeAbsent,
    Object? createdAt = _writeAbsent,
    Object? ownerId = _writeAbsent,
  }) => _query.update(
    ProjectPatch._(
      name: _writeLiteral<String, ProjectFields>(name),
      status: _writeLiteral<models.ProjectStatus, ProjectFields>(status),
      createdAt: _writeLiteral<DateTime, ProjectFields>(createdAt),
      ownerId: _writeLiteral<int, ProjectFields>(ownerId),
    ),
  );
}

/// Named literal updates on a complete models.Project query.
extension ProjectWrites
    on orm_model.ModelQuery<models.Project, ProjectFields, ProjectPatch> {
  /// Executes one update; omitted fields remain unchanged.
  ProjectPatcher get patch => _ProjectPatcher(this);
}

/// The generated root; all read composition uses the common Query core.
final class ProjectTableSet
    extends
        orm_model.ModelTable<
          models.Project,
          ProjectFields,
          ProjectInsert,
          ProjectPatch
        > {
  ProjectTableSet(QueryContext db)
    : super(
        db,
        projectTable,
        (fields, input) => input._assignments(fields),
        (fields, input) => input._assignments(fields),
      ) {
    db.registerSchema(appSchema);
  }
  late final ProjectCreator create = _ProjectCreator(this);

  orm_model.ModelQuery<models.Project, ProjectFields, ProjectPatch> byId(
    int id,
  ) => where((row) => row.id.eq(.value(id)));
}

final appSchema = List<TableSchema>.unmodifiable([
  departmentSchema,
  employeeSchema,
  projectMemberSchema,
  projectSchema,
]);

extension AppTables on QueryContext {
  DepartmentTableSet get department => DepartmentTableSet(this);
  EmployeeTableSet get employee => EmployeeTableSet(this);
  ProjectMemberTableSet get projectMember => ProjectMemberTableSet(this);
  ProjectTableSet get project => ProjectTableSet(this);
}
