import 'package:orm/schema.dart';

enum ProjectStatus { draft, active, archived }

enum MemberRole { maintainer, member }

// Departments.
@Model(table: "departments")
@Unique(["name"])
@Relation(
  target: Employee,
  name: "employees",
  fields: ["id"],
  keys: ["departmentId"],
  constraint: false,
)
final class Department({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "name") required final String name,
});

// Employees, departments and direct managers.
@Model(table: "employees")
@Unique(["email"])
@Index(["departmentId", "id"], name: "employees_department_id", unique: false)
@Index(["managerId", "id"], name: "employees_manager_id", unique: false)
@Relation(
  target: Department,
  name: "department",
  fields: ["departmentId"],
  keys: ["id"],
  onDelete: .restrict,
)
@Relation(
  target: Employee,
  name: "manager",
  fields: ["managerId"],
  keys: ["id"],
  onDelete: .setNull,
)
@Relation(
  target: Employee,
  name: "directReports",
  fields: ["id"],
  keys: ["managerId"],
  constraint: false,
)
@Relation(
  target: Project,
  name: "ownedProjects",
  fields: ["id"],
  keys: ["ownerId"],
  constraint: false,
)
@Relation(
  target: ProjectMember,
  name: "memberships",
  fields: ["id"],
  keys: ["employeeId"],
  constraint: false,
)
final class Employee({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "name") required final String name,
  @Column(name: "email") required final String email,
  @Column(name: "active")
  @DatabaseDefault.sql("true")
  required final bool active,
  @Column(name: "created_at")
  @ClientDefault(DateTime.now)
  required final DateTime createdAt,
  @Column(name: "department_id") required final int departmentId,
  @Column(name: "manager_id") required final int? managerId,
});

// Projects, their owners and status.
@Model(table: "projects")
@Index(["ownerId", "id"], name: "projects_owner_id", unique: false)
@Relation(
  target: Employee,
  name: "owner",
  fields: ["ownerId"],
  keys: ["id"],
  onDelete: .restrict,
)
@Relation(
  target: ProjectMember,
  name: "members",
  fields: ["id"],
  keys: ["projectId"],
  constraint: false,
)
final class Project({
  @Id(generated: true) @Column(name: "id") required final int id,
  @Column(name: "name") required final String name,
  @Column(
    name: "status",
    labels: {
      ProjectStatus.draft: "draft",
      ProjectStatus.active: "active",
      ProjectStatus.archived: "archived",
    },
  )
  @DatabaseDefault.sql("'draft'")
  required final ProjectStatus status,
  @Column(name: "created_at")
  @ClientDefault(DateTime.now)
  required final DateTime createdAt,
  @Column(name: "owner_id") required final int ownerId,
});

// Project membership records the employee, role and joining time.
@Model(table: "project_members")
@Index(
  ["employeeId", "projectId"],
  name: "project_members_employee_project",
  unique: false,
)
@Relation(
  target: Project,
  name: "project",
  fields: ["projectId"],
  keys: ["id"],
  onDelete: .cascade,
)
@Relation(
  target: Employee,
  name: "employee",
  fields: ["employeeId"],
  keys: ["id"],
  onDelete: .cascade,
)
final class ProjectMember({
  @Id(generated: false)
  @Column(name: "project_id")
  required final int projectId,
  @Id(generated: false)
  @Column(name: "employee_id")
  required final int employeeId,
  @Column(
    name: "role",
    labels: {MemberRole.maintainer: "maintainer", MemberRole.member: "member"},
  )
  @DatabaseDefault.sql("'member'")
  required final MemberRole role,
  @Column(name: "joined_at")
  @ClientDefault(DateTime.now)
  required final DateTime joinedAt,
});
