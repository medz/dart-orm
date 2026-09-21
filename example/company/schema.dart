import 'package:orm/schema.dart';

enum ProjectStatus { draft, active, archived }

enum MemberRole { maintainer, member }

// 部门
final department = model('departments', (
  id: identity(),
  name: text(unique: true),
), relations: (d) => (employees: referencedBy(() => employee)));

// 员工：所属部门与直属上级
final Model employee = model(
  'employees',
  (
    id: identity(),
    name: text(),
    email: text(unique: true),
    active: boolean(defaultValue: true),
    createdAt: dateTime(clientDefault: DateTime.now),
    departmentId: integer(),
    managerId: integer().nullable(),
  ),
  relations: (e) => (
    department: references(e.departmentId, () => department),
    manager: references(e.managerId, () => employee, onDelete: .setNull),
    directReports: referencedBy(() => employee),
    ownedProjects: referencedBy(() => project),
    memberships: referencedBy(() => projectMember),
  ),
  indexes: (e) => [
    index((e.departmentId, e.id), name: 'employees_department_id'),
    index((e.managerId, e.id), name: 'employees_manager_id'),
  ],
);

// 项目：负责人及项目状态
final Model project = model(
  'projects',
  (
    id: identity(),
    name: text(),
    status: enumeration(
      ProjectStatus.values,
      defaultValue: ProjectStatus.draft,
    ),
    createdAt: dateTime(clientDefault: DateTime.now),
    ownerId: integer(),
  ),
  relations: (p) => (
    owner: references(p.ownerId, () => employee),
    members: referencedBy(() => projectMember),
  ),
  indexes: (p) => [index((p.ownerId, p.id), name: 'projects_owner_id')],
);

// 项目成员：员工与项目的多对多关系，包含角色和加入时间
final projectMember = model(
  'project_members',
  (
    projectId: integer(),
    employeeId: integer(),
    role: enumeration(MemberRole.values, defaultValue: MemberRole.member),
    joinedAt: dateTime(clientDefault: DateTime.now),
  ),
  primaryKey: (m) => (m.projectId, m.employeeId),
  relations: (m) => (
    project: references(m.projectId, () => project, onDelete: .cascade),
    employee: references(m.employeeId, () => employee, onDelete: .cascade),
  ),
  indexes: (m) => [
    index((
      m.employeeId,
      m.projectId,
    ), name: 'project_members_employee_project'),
  ],
);
