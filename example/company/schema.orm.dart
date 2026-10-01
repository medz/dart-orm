// GENERATED CODE - DO NOT MODIFY BY HAND.

import 'package:orm/sql.dart';
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

final class DepartmentTableSet
    extends TableSet<models.Department, DepartmentFields> {
  DepartmentTableSet(QueryContext db) : super(db, departmentTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Department> create({
    Change<int> id = const Change.keep(),
    required String name,
  }) => createRow((row) => [...row.id.change(id), row.name.set(name)]);
  Query<models.Department, DepartmentFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension DepartmentUpdates on Query<models.Department, DepartmentFields> {
  Future<int> patch({Change<String> name = const Change.keep()}) =>
      update((row) => [...row.name.change(name)]).execute();
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

final class EmployeeTableSet extends TableSet<models.Employee, EmployeeFields> {
  EmployeeTableSet(QueryContext db) : super(db, employeeTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Employee> create({
    Change<int> id = const Change.keep(),
    required String name,
    required String email,
    Change<bool> active = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
    required int departmentId,
    int? managerId,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.name.set(name),
      row.email.set(email),
      ...row.active.change(active),
      ...row.createdAt.change(createdAt),
      row.departmentId.set(departmentId),
      row.managerId.set(managerId),
    ],
  );
  Query<models.Employee, EmployeeFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension EmployeeUpdates on Query<models.Employee, EmployeeFields> {
  Future<int> patch({
    Change<String> name = const Change.keep(),
    Change<String> email = const Change.keep(),
    Change<bool> active = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
    Change<int> departmentId = const Change.keep(),
    Change<int?> managerId = const Change.keep(),
  }) => update(
    (row) => [
      ...row.name.change(name),
      ...row.email.change(email),
      ...row.active.change(active),
      ...row.createdAt.change(createdAt),
      ...row.departmentId.change(departmentId),
      ...row.managerId.change(managerId),
    ],
  ).execute();
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

final class ProjectMemberTableSet
    extends TableSet<models.ProjectMember, ProjectMemberFields> {
  ProjectMemberTableSet(QueryContext db) : super(db, projectMemberTable) {
    db.registerSchema(appSchema);
  }
  Future<models.ProjectMember> create({
    required int projectId,
    required int employeeId,
    Change<models.MemberRole> role = const Change.keep(),
    Change<DateTime> joinedAt = const Change.keep(),
  }) => createRow(
    (row) => [
      row.projectId.set(projectId),
      row.employeeId.set(employeeId),
      ...row.role.change(role),
      ...row.joinedAt.change(joinedAt),
    ],
  );
  Query<models.ProjectMember, ProjectMemberFields> byId({
    required int projectId,
    required int employeeId,
  }) => where(
    (row) => orm.allOf([
      row.projectId.eq(.value(projectId)),
      row.employeeId.eq(.value(employeeId)),
    ]),
  );
}

extension ProjectMemberUpdates
    on Query<models.ProjectMember, ProjectMemberFields> {
  Future<int> patch({
    Change<int> projectId = const Change.keep(),
    Change<int> employeeId = const Change.keep(),
    Change<models.MemberRole> role = const Change.keep(),
    Change<DateTime> joinedAt = const Change.keep(),
  }) => update(
    (row) => [
      ...row.projectId.change(projectId),
      ...row.employeeId.change(employeeId),
      ...row.role.change(role),
      ...row.joinedAt.change(joinedAt),
    ],
  ).execute();
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

final class ProjectTableSet extends TableSet<models.Project, ProjectFields> {
  ProjectTableSet(QueryContext db) : super(db, projectTable) {
    db.registerSchema(appSchema);
  }
  Future<models.Project> create({
    Change<int> id = const Change.keep(),
    required String name,
    Change<models.ProjectStatus> status = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
    required int ownerId,
  }) => createRow(
    (row) => [
      ...row.id.change(id),
      row.name.set(name),
      ...row.status.change(status),
      ...row.createdAt.change(createdAt),
      row.ownerId.set(ownerId),
    ],
  );
  Query<models.Project, ProjectFields> byId(int id) =>
      where((row) => row.id.eq(.value(id)));
}

extension ProjectUpdates on Query<models.Project, ProjectFields> {
  Future<int> patch({
    Change<String> name = const Change.keep(),
    Change<models.ProjectStatus> status = const Change.keep(),
    Change<DateTime> createdAt = const Change.keep(),
    Change<int> ownerId = const Change.keep(),
  }) => update(
    (row) => [
      ...row.name.change(name),
      ...row.status.change(status),
      ...row.createdAt.change(createdAt),
      ...row.ownerId.change(ownerId),
    ],
  ).execute();
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
