# Teams and memberships

[The models](schema.dart) are ordinary annotated Dart DTOs: `User`, `Team` and
`Membership`. `@Relation` describes navigation and foreign keys. The explicit
membership model stores a role and joining time, with a composite `@Id()` key
preventing duplicate memberships.

Generation preserves the original DTO types and adds `db.user`, `db.team` and
`db.membership`. Field names in relation and index annotations are strings,
validated by generation; maintain them explicitly when renaming Dart fields.
Physical names come from `@Model(table: ...)` and `@Column(name: ...)`.

From the repository root:

```sh
dart pub get
dart run bin/orm.dart generate example/teams/schema.dart
dart run example/teams/main.dart
```

The program creates an in-memory SQLite database, adds two memberships in one
transaction, filters through the association to find the Core owner, and selects
an ordered per-user membership collection. It prints the inspected SQL plan and
observed query, acquisition and decode counts rather than hiding relationship
loading behind model properties.

See [model authoring](../../doc/authoring.md) and
[relationship queries](../../doc/relations.md).
