# Company schema

This example defines departments, employees, projects and project memberships in
one [annotated Dart model library](schema.dart). Full reads return these original
DTO classes; generation adds typed queries and an independent migration snapshot.

[Directory synchronization](sync.dart) demonstrates prepared batch upserts on
SQLite/PostgreSQL. Inside an explicit transaction, it updates directory-owned
names and department assignments while retaining existing generated IDs and
locally managed fields. See [batch conflict boundaries](../../doc/api.md) for
omission, repeated keys, statement chunking and RETURNING semantics.

| Model | Relationships |
| --- | --- |
| Department | Has employees |
| Employee | Belongs to a department; optionally reports to another employee |
| Project | Has an employee owner and project memberships |
| ProjectMember | Connects one employee to one project, with a role and joining time |

`@Relation` declares query navigation and, by default, a physical foreign key.
This example also spells out collection navigation with `constraint: false`.
Field lists are checked during generation and must be updated explicitly after
Dart field renames. The membership's two `@Id()` fields form a composite primary
key that prevents an employee from joining the same project twice.

Deleting a manager clears their reports' `managerId`. Deleting a project removes
its memberships. Employees who still own projects cannot be deleted; departments
with employees cannot be deleted either.

From the repository root, generate the client and run the example:

```sh
dart pub get
dart run bin/orm.dart generate example/company/schema.dart
dart run example/company/main.dart
```

The program creates an in-memory SQLite database, applies a migration, creates
Alice and Bob in one transaction, and selects Bob's manager:

```text
Bob reports to Alice
```

See [schema declarations](../../doc/authoring.md) for columns and constraints, and
[relationship queries](../../doc/relations.md) for selecting related values.
