# Company schema

This example defines departments, employees, projects and project memberships in
one [Record schema](schema.dart). It generates immutable model classes, typed
queries and an independent migration snapshot.

| Model | Relationships |
| --- | --- |
| Department | Has employees |
| Employee | Belongs to a department; optionally reports to another employee |
| Project | Has an employee owner and project memberships |
| ProjectMember | Connects one employee to one project, with a role and joining time |

Each model declares its own query members in `relations`. `references` owns a
foreign key; `referencedBy` exposes its reverse. The membership's composite primary
key prevents an employee from joining the same project twice.

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
